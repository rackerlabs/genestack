#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="openstack"
MARIADB_NAME="mariadb-cluster"

# Base directory that already holds the MariaDB cluster's kustomization.
# Generated Backup CRs are written to a "mariadb-backups" subdirectory
# here, and that subdirectory is wired into this base's kustomization.yaml.
MARIADB_BASE_DIR="${MARIADB_BASE_DIR:-/opt/genestack/base-kustomize/mariadb-cluster/base}"
BACKUP_DIR="${BACKUP_DIR:-${MARIADB_BASE_DIR}/mariadb-backups}"

SCHEDULE="${SCHEDULE:-0 0 * * *}"
PVC_SIZE="${PVC_SIZE:-1Gi}"

# Set to "false" to only generate manifests without applying them.
AUTO_APPLY="${AUTO_APPLY:-true}"

# Set to "true" to also (re)generate the per-database S3 overlay patches
# used in prod to redirect backups from PVC storage to S3. These patches
# are only written to disk, never applied directly by this script -- they
# are consumed via `kubectl apply -k /etc/genestack/kustomize/mariadb-cluster/overlay`.
GENERATE_S3_PATCHES="${GENERATE_S3_PATCHES:-false}"
S3_OVERLAY_DIR="${S3_OVERLAY_DIR:-/etc/genestack/kustomize/mariadb-cluster/overlay}"
S3_PREFIX_BASE="${S3_PREFIX_BASE:-cron}"
S3_SECRET_NAME="${S3_SECRET_NAME:-mariadb-backup-secrets}"

# Required only when GENERATE_S3_PATCHES=true.
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_REGION="${S3_REGION:-}"
S3_BUCKET="${S3_BUCKET:-}"

# Minutes to offset each successive Backup CR's cron schedule by, so
# that backups for different databases don't all fire at once.
SCHEDULE_STAGGER_MINUTES="${SCHEDULE_STAGGER_MINUTES:-5}"

# Existing Genestack Backup settings
SERVICE_ACCOUNT="backup"
COMPRESSION="gzip"

# Arguments currently used by Genestack's Backup CR
DUMP_ARGS=(
  "--single-transaction"
  "--verbose"
)

# Labels applied to every generated Backup CR.
COMMON_LABELS=(
  "app.kubernetes.io/instance=${MARIADB_NAME}"
  "app.kubernetes.io/component=mariadb-backup"
  "app.kubernetes.io/managed-by=mariadb-backup-discovery"
)

# System databases which will be skipped for backup.
SYSTEM_DATABASES_REGEX='^(information_schema|performance_schema|sys)$'

log() {
    echo "[INFO] $*"
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# --------------------------------------------------------------------
# Compute a staggered cron schedule for the Nth database (0-indexed),
# offsetting the base SCHEDULE by N * SCHEDULE_STAGGER_MINUTES minutes.
#
# Only the minute and hour fields are adjusted; minute overflow rolls
# into the hour field and hour overflow wraps back around (mod 24).
# The day-of-month/month/day-of-week fields are left untouched, since
# this is meant for small stagger windows (a handful of databases a
# few minutes apart), not for spreading backups across whole days.
#
# If the base schedule's minute/hour fields aren't plain integers
# (e.g. "*", "*/15", "1-5"), staggering is skipped and the original
# schedule is returned unchanged, since offsetting those is ambiguous.
# --------------------------------------------------------------------
stagger_cron_schedule() {
    local base_schedule="$1"
    local index="$2"
    local offset_minutes=$((index * SCHEDULE_STAGGER_MINUTES))

    local minute hour rest
    minute="$(awk '{print $1}' <<< "$base_schedule")"
    hour="$(awk '{print $2}' <<< "$base_schedule")"
    rest="$(awk '{$1=""; $2=""; sub(/^  */, ""); print}' <<< "$base_schedule")"

    if [ "$offset_minutes" -eq 0 ] ||
        ! [[ "$minute" =~ ^[0-9]+$ ]] ||
        ! [[ "$hour" =~ ^[0-9]+$ ]]; then
        echo "$base_schedule"
        return
    fi

    local total_minutes=$(( (hour * 60 + minute + offset_minutes) % (24 * 60) ))
    local new_hour=$(( total_minutes / 60 ))
    local new_minute=$(( total_minutes % 60 ))

    echo "${new_minute} ${new_hour} ${rest}"
}

command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [ "$GENERATE_S3_PATCHES" = "true" ]; then
    [ -n "$S3_ENDPOINT" ] ||
        die "S3_ENDPOINT is required when GENERATE_S3_PATCHES=true"
    [ -n "$S3_REGION" ] ||
        die "S3_REGION is required when GENERATE_S3_PATCHES=true"
    [ -n "$S3_BUCKET" ] ||
        die "S3_BUCKET is required when GENERATE_S3_PATCHES=true"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 ||
    die "Namespace $NAMESPACE does not exist"

kubectl -n "$NAMESPACE" get mariadb "$MARIADB_NAME" >/dev/null 2>&1 ||
    die "MariaDB CR $MARIADB_NAME not found"

# --------------------------------------------------------------------
# Find MariaDB pod
# --------------------------------------------------------------------
MARIADB_POD="$(
    kubectl -n "$NAMESPACE" get pods \
        -l "app.kubernetes.io/instance=$MARIADB_NAME" \
        -o json |
    jq -r '
        .items[]
        | select(
            any(.status.containerStatuses[]?;
                .ready == true
            )
        )
        | .metadata.name
    ' |
    head -n 1
)"

[ -n "$MARIADB_POD" ] ||
    die "Could not find a Ready MariaDB pod"

log "MariaDB pod: $MARIADB_POD"

# --------------------------------------------------------------------
# Find root password Secret dynamically from MariaDB CR
# --------------------------------------------------------------------
ROOT_SECRET="$(
    kubectl -n "$NAMESPACE" get mariadb "$MARIADB_NAME" \
        -o jsonpath='{.spec.rootPasswordSecretKeyRef.name}'
)"

ROOT_KEY="$(
    kubectl -n "$NAMESPACE" get mariadb "$MARIADB_NAME" \
        -o jsonpath='{.spec.rootPasswordSecretKeyRef.key}'
)"

[ -n "$ROOT_SECRET" ] ||
    die "MariaDB root password Secret name is empty"

[ -n "$ROOT_KEY" ] ||
    die "MariaDB root password Secret key is empty"

log "Root password Secret: $ROOT_SECRET"
log "Root password Secret key: $ROOT_KEY"

# --------------------------------------------------------------------
# Read root password without putting it into the kubectl argument list
# --------------------------------------------------------------------
ROOT_PASSWORD="$(
    kubectl -n "$NAMESPACE" get secret "$ROOT_SECRET" -o json |
    jq -r --arg key "$ROOT_KEY" '.data[$key]' |
    base64 -d
)"


[ -n "$ROOT_PASSWORD" ] ||
    die "Could not retrieve MariaDB root password"

# --------------------------------------------------------------------
# Discover databases
# --------------------------------------------------------------------
log "Discovering databases from MariaDB..."

DATABASES="$(
    printf '%s\n' "$ROOT_PASSWORD" |
    kubectl -n "$NAMESPACE" exec -i "$MARIADB_POD" -- \
        sh -c '
            read -r MYSQL_PWD
            export MYSQL_PWD
            mariadb \
                --user=root \
                --batch \
                --skip-column-names \
                --execute="SHOW DATABASES;"
        ' |
    grep -Ev "$SYSTEM_DATABASES_REGEX" |
    sed '/^[[:space:]]*$/d' |
    sort -u
)"

[ -n "$DATABASES" ] ||
    die "No application databases were discovered"

log "Discovered databases:"
printf '%s\n' "$DATABASES"

# --------------------------------------------------------------------
# Discover Backup CRs that already exist in the cluster, so we can
# skip regenerating/reapplying a Backup for a database that already
# has one. This avoids clobbering an existing Backup CR (and any
# manual edits/overlay patches applied to it) on repeat runs.
# --------------------------------------------------------------------
log "Checking for existing Backup CRs in namespace $NAMESPACE..."

EXISTING_BACKUPS="$(
    kubectl -n "$NAMESPACE" get backups.k8s.mariadb.com \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true
)"

existing_backup_exists() {
    local name="$1"
    local existing
    for existing in $EXISTING_BACKUPS; do
        [ "$existing" = "$name" ] && return 0
    done
    return 1
}

# --------------------------------------------------------------------
# Recreate generated directory
# --------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
rm -f "$BACKUP_DIR"/mariadb-backup-*.yaml

# --------------------------------------------------------------------
# Generate one Backup CR per database (skipping ones that already exist)
# --------------------------------------------------------------------
RESOURCE_LIST=()
SKIPPED_LIST=()
S3_PATCH_LIST=()
DB_INDEX=0

if [ "$GENERATE_S3_PATCHES" = "true" ]; then
    mkdir -p "$S3_OVERLAY_DIR/patches"
    rm -f "$S3_OVERLAY_DIR/patches"/mariadb-backup-*-s3.yaml
fi

while IFS= read -r DB; do
    # Kubernetes resource names cannot contain arbitrary DB characters.
    # Convert everything except [a-z0-9-] into '-'.
    SAFE_NAME="$(
        printf '%s' "$DB" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9-]/-/g'
    )"

    FILE="$BACKUP_DIR/mariadb-backup-${SAFE_NAME}.yaml"
    RESOURCE_NAME="mariadb-backup-${SAFE_NAME}"

    # Index is based on position in the full (sorted) database list,
    # not on how many CRs were actually generated. This keeps each
    # database's stagger offset stable across reruns, even if some
    # databases are skipped because a Backup CR already exists for them.
    THIS_DB_INDEX=$DB_INDEX
    DB_INDEX=$((DB_INDEX + 1))

    if existing_backup_exists "$RESOURCE_NAME"; then
        log "Backup CR '$RESOURCE_NAME' already exists, skipping database: $DB"
        SKIPPED_LIST+=("$DB")
        continue
    fi

    DB_SCHEDULE="$(stagger_cron_schedule "$SCHEDULE" "$THIS_DB_INDEX")"

    log "Generating backup CR for database: $DB (schedule: \"$DB_SCHEDULE\")"

    {
        echo "---"
        echo "apiVersion: k8s.mariadb.com/v1alpha1"
        echo "kind: Backup"
        echo "metadata:"
        echo "  name: ${RESOURCE_NAME}"
        echo "  namespace: ${NAMESPACE}"
        echo "  labels:"
        for LABEL in "${COMMON_LABELS[@]}"; do
            LABEL_KEY="${LABEL%%=*}"
            LABEL_VALUE="${LABEL#*=}"
            echo "    ${LABEL_KEY}: ${LABEL_VALUE}"
        done
        echo "    app.kubernetes.io/name: ${SAFE_NAME}"
        echo "spec:"
        echo "  mariaDbRef:"
        echo "    name: ${MARIADB_NAME}"
        echo "    namespace: ${NAMESPACE}"
        echo "  schedule:"
        echo "    cron: \"${DB_SCHEDULE}\""
        echo "  serviceAccountName: ${SERVICE_ACCOUNT}"
        echo "  compression: ${COMPRESSION}"
        echo "  databases:"
        echo "    - ${DB}"
        echo "  storage:"
        echo "    persistentVolumeClaim:"
        echo "      resources:"
        echo "        requests:"
        echo "          storage: ${PVC_SIZE}"
        echo "      accessModes:"
        echo "        - ReadWriteOnce"
        echo "  args:"
        for ARG in "${DUMP_ARGS[@]}"; do
            echo "    - ${ARG}"
        done
        echo "  resources:"
        echo "    requests:"
        echo "      cpu: 100m"
        echo "      memory: 128Mi"
        echo "    limits:"
        echo "      cpu: 300m"
        echo "      memory: 512Mi"
        echo "  affinity:"
        echo "    podAntiAffinity:"
        echo "      preferredDuringSchedulingIgnoredDuringExecution:"
        echo "        - weight: 100"
        echo "          podAffinityTerm:"
        echo "            labelSelector:"
        echo "              matchExpressions:"
        echo "                - key: app.kubernetes.io/instance"
        echo "                  operator: In"
        echo "                  values:"
        echo "                    - mariadb-cluster"
        echo "            topologyKey: kubernetes.io/hostname"
    } > "$FILE"

    RESOURCE_LIST+=("$(basename "$FILE")")

    # ----------------------------------------------------------------
    # Generate the matching S3 overlay patch for this database.
    # Each Backup CR gets its own prefix (one per database) so that
    # backups land in distinct S3 locations:
    #   s3://<bucket>/<S3_PREFIX_BASE>/<db-name>/
    # ----------------------------------------------------------------
    if [ "$GENERATE_S3_PATCHES" = "true" ]; then
        PATCH_FILE="$S3_OVERLAY_DIR/patches/${RESOURCE_NAME}-s3.yaml"

        # endpoint/region/bucket are baked in as plain literals (from
        # the S3_ENDPOINT/S3_REGION/S3_BUCKET arguments) directly into
        # each patch -- no ConfigMap or replacements indirection.
        {
            echo "- op: replace"
            echo "  path: /spec/storage"
            echo "  value:"
            echo "    s3:"
            echo "      bucket: ${S3_BUCKET}"
            echo "      prefix: ${S3_PREFIX_BASE}/${SAFE_NAME}"
            echo "      endpoint: ${S3_ENDPOINT}"
            echo "      region: ${S3_REGION}"
            echo "      accessKeyIdSecretKeyRef:"
            echo "        name: ${S3_SECRET_NAME}"
            echo "        key: access-key-id"
            echo "      secretAccessKeySecretKeyRef:"
            echo "        name: ${S3_SECRET_NAME}"
            echo "        key: secret-access-key"
            echo "      tls:"
            echo "        enabled: true"
        } > "$PATCH_FILE"

        S3_PATCH_LIST+=("${RESOURCE_NAME}|$(basename "$PATCH_FILE")")
    fi
done <<< "$DATABASES"

# --------------------------------------------------------------------
# Wire the newly generated per-database S3 patches into the existing
# S3 overlay kustomization.yaml, without disturbing anything already
# in that file. In particular:
#   - The "resources:" section is never written or modified here. The
#     overlay's kustomization.yaml is expected to already exist with
#     "resources:" populated; it is left completely untouched.
#   - Only new "patches:" entries (one per patch generated this run)
#     are appended; entries for databases that already have a patch
#     wired up are left as-is.
# --------------------------------------------------------------------
add_s3_patch_entry_to_overlay() {
    local overlay_file="$1"
    local resource_name="$2"
    local patch_basename="$3"

    [ -f "$overlay_file" ] ||
        die "S3 overlay kustomization.yaml not found at $overlay_file -- create it first with a 'resources:' section"

    # Skip if a patch entry for this path is already wired up, so
    # reruns don't produce duplicate "patches:" entries.
    if grep -qE "^\s*path:\s*patches/${patch_basename}\s*$" "$overlay_file"; then
        return
    fi

    local entry
    entry="$(
        printf '  - path: patches/%s\n' "$patch_basename"
        printf '    target:\n'
        printf '      kind: Backup\n'
        printf '      name: %s\n' "$resource_name"
        printf '      namespace: openstack\n'
    )"

    if ! grep -qE '^patches:\s*$' "$overlay_file"; then
        # No "patches:" key yet; add one along with the first entry,
        # at the end of the file.
        {
            echo "patches:"
            printf '%s' "$entry"
        } >> "$overlay_file"
        return
    fi

    # "patches:" already exists. Insert the new entry directly after
    # the last line belonging to that list (i.e. right before the
    # next top-level "key:" line, or at EOF if "patches:" is the last
    # top-level key), so it lands inside the "patches:" list rather
    # than after whatever top-level key happens to come last in the
    # file.
    local tmp_file
    tmp_file="$(mktemp)"
    PATCH_ENTRY="$entry" awk '
        BEGIN { in_patches = 0; inserted = 0; entry = ENVIRON["PATCH_ENTRY"] }
        /^patches:[[:space:]]*$/ { in_patches = 1; print; next }
        in_patches && !inserted && /^[A-Za-z0-9_.-]+:/ {
            printf "%s\n", entry
            inserted = 1
            in_patches = 0
        }
        { print }
        END {
            if (in_patches && !inserted) {
                printf "%s\n", entry
            }
        }
    ' "$overlay_file" > "$tmp_file"
    mv "$tmp_file" "$overlay_file"
}

if [ "$GENERATE_S3_PATCHES" = "true" ] && [ "${#S3_PATCH_LIST[@]}" -gt 0 ]; then
    for ENTRY in "${S3_PATCH_LIST[@]}"; do
        PATCH_RESOURCE_NAME="${ENTRY%%|*}"
        PATCH_BASENAME="${ENTRY#*|}"
        add_s3_patch_entry_to_overlay "$S3_OVERLAY_DIR/kustomization.yaml" \
            "$PATCH_RESOURCE_NAME" "$PATCH_BASENAME"
    done

    log "Updated S3 overlay: $S3_OVERLAY_DIR/kustomization.yaml (+${#S3_PATCH_LIST[@]} patches, endpoint=$S3_ENDPOINT, region=$S3_REGION)"
fi

# --------------------------------------------------------------------
# Generate nested kustomization.yaml (only if there is anything new)
# --------------------------------------------------------------------
if [ "${#RESOURCE_LIST[@]}" -gt 0 ]; then
    {
        echo "resources:"
        for RESOURCE in "${RESOURCE_LIST[@]}"; do
            echo "  - ${RESOURCE}"
        done
    } > "$BACKUP_DIR/kustomization.yaml"
fi

# --------------------------------------------------------------------
# Ensure the parent MariaDB base kustomization.yaml references the
# "mariadb-backups" subdirectory, so `kubectl apply -k` on the base
# also picks up every generated per-database Backup CR. Only appends
# the entry if it isn't already present, leaving all existing
# resources untouched.
# --------------------------------------------------------------------
BASE_KUSTOMIZATION="$MARIADB_BASE_DIR/kustomization.yaml"
BACKUP_SUBDIR_NAME="$(basename "$BACKUP_DIR")"

if [ -f "$BASE_KUSTOMIZATION" ]; then
    if grep -qE "^\s*-\s*${BACKUP_SUBDIR_NAME}\s*$" "$BASE_KUSTOMIZATION"; then
        log "Base kustomization already references '$BACKUP_SUBDIR_NAME': $BASE_KUSTOMIZATION"
    else
        if grep -qE '^resources:\s*$' "$BASE_KUSTOMIZATION"; then
            # Insert right after the "resources:" line, preserving
            # every existing entry.
            TMP_KUSTOMIZATION="$(mktemp)"
            awk -v entry="  - ${BACKUP_SUBDIR_NAME}" '
                { print }
                /^resources:[[:space:]]*$/ && !inserted { print entry; inserted=1 }
            ' "$BASE_KUSTOMIZATION" > "$TMP_KUSTOMIZATION"
            mv "$TMP_KUSTOMIZATION" "$BASE_KUSTOMIZATION"
        else
            # No "resources:" key found at all; add one.
            {
                echo "resources:"
                echo "  - ${BACKUP_SUBDIR_NAME}"
            } >> "$BASE_KUSTOMIZATION"
        fi
        log "Added '$BACKUP_SUBDIR_NAME' to: $BASE_KUSTOMIZATION"
    fi
else
    log "WARNING: base kustomization not found at $BASE_KUSTOMIZATION, skipping update"
fi

log "Generated ${#RESOURCE_LIST[@]} new Backup CRs"
log "Skipped ${#SKIPPED_LIST[@]} database(s) with existing Backup CRs"

if [ "${#SKIPPED_LIST[@]}" -gt 0 ]; then
    echo
    echo "Skipped (Backup CR already exists):"
    printf '  %s\n' "${SKIPPED_LIST[@]}"
fi

if [ "${#RESOURCE_LIST[@]}" -eq 0 ]; then
    log "Nothing new to generate or apply."
    exit 0
fi

echo
echo "Generated files:"
printf '  %s\n' "${RESOURCE_LIST[@]}"
echo
log "Generated Kustomization: $BACKUP_DIR/kustomization.yaml"

# --------------------------------------------------------------------
# Apply automatically, unless disabled via AUTO_APPLY=false
# --------------------------------------------------------------------
if [ "$AUTO_APPLY" = "true" ]; then
    log "Applying generated Backup CRs with: kubectl apply -k $BACKUP_DIR"
    kubectl apply -k "$BACKUP_DIR"
    log "Apply complete."
else
    echo
    echo "AUTO_APPLY is disabled. Review the generated manifests with:"
    echo "  kubectl kustomize $BACKUP_DIR"
    echo
    echo "Apply them manually with:"
    echo "  kubectl apply -k $BACKUP_DIR"
fi

if [ "$GENERATE_S3_PATCHES" = "true" ] && [ "${#S3_PATCH_LIST[@]}" -gt 0 ]; then
    echo
    echo "S3 overlay generated at: $S3_OVERLAY_DIR"
    echo "  endpoint: $S3_ENDPOINT"
    echo "  region:   $S3_REGION"
    echo "  bucket:   $S3_BUCKET"
    echo "This overlay is NOT applied automatically. Before using it:"
    echo "  1. Ensure the '$S3_SECRET_NAME' Secret (access-key-id,"
    echo "     secret-access-key) exists in namespace '$NAMESPACE'."
    echo "  2. Review it with:"
    echo "       kubectl kustomize $S3_OVERLAY_DIR"
    echo "  3. Apply it INSTEAD OF the plain PVC-based base with:"
    echo "       kubectl apply -k $S3_OVERLAY_DIR"
fi
