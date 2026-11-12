#!/usr/bin/env bash

set -euo pipefail

# This script works for both MariaDB topologies supported by Genestack:
# Primary/Replica (replication) and Galera. Galera is enabled by patching
# the *same* MariaDB CR (see base-kustomize/mariadb-cluster/galera), it is
# not a separate resource -- so the name/namespace below are correct for
# either topology. The actual topology is detected at runtime further down
# (purely for logging/sanity-checking); database discovery and Backup CR
# generation are identical either way.
NAMESPACE="openstack"
MARIADB_NAME="mariadb-cluster"

# Base directory that already holds the MariaDB cluster's kustomization.
# Generated Backup CRs are written to a "mariadb-backups" subdirectory
# here, and that subdirectory is wired into this base's kustomization.yaml.
#
# This defaults to the Primary/Replica base, but it also covers Galera
# clusters: base-kustomize/mariadb-cluster/galera/kustomization.yaml lists
# "../base" among its own resources, so anything added to the base's
# kustomization.yaml (including the generated "mariadb-backups" resource)
# is pulled in transitively, regardless of whether a given site deploys
# the base or galera overlay. If your site's mariadb-cluster kustomize
# tree doesn't follow that layout, point this at the correct directory
# explicitly via the MARIADB_BASE_DIR env var -- the runtime check below
# will warn if the detected topology doesn't match what it finds here.
MARIADB_BASE_DIR="${MARIADB_BASE_DIR:-/opt/genestack/base-kustomize/mariadb-cluster/base}"
BACKUP_DIR="${BACKUP_DIR:-${MARIADB_BASE_DIR}/mariadb-backups}"

# Space/comma separated list of additional database names to always skip,
# on top of the system databases below. Use this to permanently opt a
# database out of per-database backup generation. This is the supported
# way to do so -- deleting a generated Backup CR from the cluster is NOT
# sufficient, since it will be regenerated on the next run as long as the
# database still exists (see "skip if exists" logic below).
EXCLUDE_DATABASES="${EXCLUDE_DATABASES:-}"

# Set to "true" to delete the local manifest (and, if S3 patches are
# enabled, the matching S3 patch) for a database that no longer exists in
# MariaDB, and to also delete its live Backup CR from the cluster. Off by
# default: orphaned databases are only reported as a warning, since
# deleting a Backup CR is a destructive, hard-to-reverse action.
PRUNE_ORPHANED_BACKUPS="${PRUNE_ORPHANED_BACKUPS:-false}"

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

# Required only when GENERATE_S3_PATCHES=true. Plain literals, no
# ConfigMap -- baked directly into each generated patch file.
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_REGION="${S3_REGION:-}"
S3_BUCKET="${S3_BUCKET:-}"

# Minutes to offset each successive Backup CR's cron schedule by, so
# that backups for different databases don't all fire at once.
SCHEDULE_STAGGER_MINUTES="${SCHEDULE_STAGGER_MINUTES:-5}"

# Existing Genestack Backup settings
SERVICE_ACCOUNT="backup"
COMPRESSION="gzip"

# Arguments currently used by Genestack's Backup CR. Matches the dump
# options used by scripts/backup-mariadb.sh and docs/infrastructure-mariadb-ops.md
# (--routines/--triggers/--events are required so that stored procedures,
# triggers and scheduled events -- used by services such as keystone and
# nova -- aren't silently dropped from per-database dumps).
DUMP_ARGS=(
  "--single-transaction"
  "--routines"
  "--triggers"
  "--events"
  "--verbose"
)

# Labels applied to every generated Backup CR. Each per-database Backup
# is matched by name in the S3 overlay's patches (see "patches:" target
# below), so these labels are informational/discovery-oriented only --
# the S3 overlay patches do not select or modify them.
COMMON_LABELS=(
  "app.kubernetes.io/instance=${MARIADB_NAME}"
  "app.kubernetes.io/component=mariadb-backup"
  "app.kubernetes.io/managed-by=mariadb-backup-discovery"
)

SYSTEM_DATABASES_REGEX='^(information_schema|mysql|performance_schema|sys|test)$'

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

    local raw_total_minutes=$(( hour * 60 + minute + offset_minutes ))
    local total_minutes=$(( raw_total_minutes % (24 * 60) ))
    local new_hour=$(( total_minutes / 60 ))
    local new_minute=$(( total_minutes % 60 ))

    if [ "$raw_total_minutes" -ge "$((24 * 60))" ]; then
        log "WARNING: stagger offset for index $index wraps past midnight" \
            "(base \"$base_schedule\" + ${offset_minutes}m -> \"${new_minute} ${new_hour} ${rest}\")," \
            "this backup now runs on the following day relative to the base schedule."
    fi

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
# Detect cluster topology (Galera vs Primary/Replica). This is purely
# informational/sanity-checking -- discovery and generation below work
# the same way for both, since Galera is a patch on top of the same
# MariaDB CR rather than a different resource.
# --------------------------------------------------------------------
GALERA_ENABLED="$(
    kubectl -n "$NAMESPACE" get mariadb "$MARIADB_NAME" \
        -o jsonpath='{.spec.galera.enabled}' 2>/dev/null || true
)"

if [ "$GALERA_ENABLED" = "true" ]; then
    log "Detected topology: Galera"

    # Sanity-check that the directory we're about to wire "mariadb-backups"
    # into (MARIADB_BASE_DIR) is actually reachable from the Galera overlay.
    # The default layout satisfies this via base-kustomize/mariadb-cluster/galera's
    # "../base" resource entry; warn loudly if a customized layout doesn't.
    GALERA_DIR="$(dirname "$MARIADB_BASE_DIR")/galera"
    GALERA_KUSTOMIZATION="$GALERA_DIR/kustomization.yaml"
    BASE_DIR_NAME="$(basename "$MARIADB_BASE_DIR")"
    if [ -f "$GALERA_KUSTOMIZATION" ] &&
        ! grep -qE "^\s*-\s*\.\./${BASE_DIR_NAME}\s*$" "$GALERA_KUSTOMIZATION"; then
        log "WARNING: Galera cluster detected, but $GALERA_KUSTOMIZATION does not" \
            "reference \"../${BASE_DIR_NAME}\" as a resource. Generated Backup CRs" \
            "may not be picked up unless MARIADB_BASE_DIR is pointed at the" \
            "kustomization directory actually deployed for this cluster."
    fi
else
    log "Detected topology: Primary/Replica (replication)"
fi

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
# Apply EXCLUDE_DATABASES (comma/space separated) on top of the system
# database filter above, so operators can permanently opt a database out
# of generation.
# --------------------------------------------------------------------
is_excluded_database() {
    local db="$1"
    local excluded
    for excluded in ${EXCLUDE_DATABASES//,/ }; do
        [ "$excluded" = "$db" ] && return 0
    done
    return 1
}

if [ -n "$EXCLUDE_DATABASES" ]; then
    FILTERED_DATABASES=""
    while IFS= read -r DB; do
        if is_excluded_database "$DB"; then
            log "Excluding database (EXCLUDE_DATABASES): $DB"
            continue
        fi
        FILTERED_DATABASES="${FILTERED_DATABASES}${DB}"$'\n'
    done <<< "$DATABASES"
    DATABASES="$(printf '%s' "$FILTERED_DATABASES" | sed '/^[[:space:]]*$/d')"

    [ -n "$DATABASES" ] ||
        die "No application databases remain after applying EXCLUDE_DATABASES"
fi

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
# Ensure the generated directory exists.
#
# NOTE: earlier versions of this script wiped *all* mariadb-backup-*.yaml
# (and, for S3, all *-s3.yaml patch) files here on every run, then only
# rewrote files for databases generated in that particular run. That
# left the nested kustomization.yaml / the S3 overlay's "patches:"
# entries pointing at files that had just been deleted and never
# recreated (for every database skipped because its Backup CR already
# existed), breaking `kubectl apply -k` / `kubectl kustomize` on the
# very next run. Nothing is deleted here anymore -- see the orphan
# handling below for the (opt-in) way to clean up files/CRs for
# databases that no longer exist.
# --------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"

# --------------------------------------------------------------------
# Generate one Backup CR per database (skipping ones that already exist)
# --------------------------------------------------------------------
NEW_RESOURCE_LIST=()
SKIPPED_LIST=()
S3_PATCH_LIST=()
DISCOVERED_SAFE_NAMES=()
DB_INDEX=0

if [ "$GENERATE_S3_PATCHES" = "true" ]; then
    mkdir -p "$S3_OVERLAY_DIR/patches"
fi

while IFS= read -r DB; do
    # Kubernetes resource names cannot contain arbitrary DB characters.
    # Convert everything except [a-z0-9-] into '-'.
    SAFE_NAME="$(
        printf '%s' "$DB" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9-]/-/g'
    )"
    DISCOVERED_SAFE_NAMES+=("$SAFE_NAME")

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

    NEW_RESOURCE_LIST+=("$(basename "$FILE")")

    # ----------------------------------------------------------------
    # Generate the matching S3 overlay patch for this database.
    # Each Backup CR gets its own prefix (one per database) so that
    # backups land in distinct S3 locations:
    #   s3://<bucket>/<S3_PREFIX_BASE>/<db-name>/
    #
    # A single JSON6902 "replace" on /spec/storage swaps the entire
    # PVC storage block for the S3 block in one operation (no separate
    # remove/add pair). Labels are left untouched by this patch.
    #
    # Note: the mariadb-operator Backup CRD nests S3 settings under
    # spec.storage.s3 (bucket/prefix/endpoint/... are fields of that
    # "s3" object, not direct children of "storage"), so the "s3:" key
    # below is required for the resulting Backup CR to validate.
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
        printf '  - target:\n'
        printf '      group: k8s.mariadb.com\n'
        printf '      version: v1alpha1\n'
        printf '      kind: Backup\n'
        printf '      name: %s\n' "$resource_name"
        printf '    path: patches/%s\n' "$patch_basename"
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

# --------------------------------------------------------------------
# Inverse of add_s3_patch_entry_to_overlay: removes the "patches:" list
# entry (if any) pointing at the given patch file, for a database that
# is being pruned. Leaves every other entry, and every other top-level
# key, untouched.
# --------------------------------------------------------------------
remove_s3_patch_entry_from_overlay() {
    local overlay_file="$1"
    local patch_basename="$2"

    [ -f "$overlay_file" ] || return 0

    grep -qE "^\s*path:\s*patches/${patch_basename}\s*$" "$overlay_file" || return 0

    local tmp_file
    tmp_file="$(mktemp)"
    PATCH_BASENAME="$patch_basename" awk '
        BEGIN { buf = ""; drop = 0; patch = "patches/" ENVIRON["PATCH_BASENAME"] }
        /^[[:space:]]*-[[:space:]]*target:[[:space:]]*$/ {
            if (buf != "" && !drop) printf "%s", buf
            buf = $0 "\n"
            drop = 0
            next
        }
        {
            if (buf != "") {
                buf = buf $0 "\n"
                if ($0 ~ ("^[[:space:]]*path:[[:space:]]*" patch "[[:space:]]*$")) drop = 1
            } else {
                print
            }
        }
        END { if (buf != "" && !drop) printf "%s", buf }
    ' "$overlay_file" > "$tmp_file"
    mv "$tmp_file" "$overlay_file"
}

# --------------------------------------------------------------------
# Orphan handling: a "mariadb-backup-*.yaml" file in BACKUP_DIR whose
# database is no longer in the current (filtered) discovery list means
# that database was dropped from MariaDB (or newly added to
# EXCLUDE_DATABASES). Report these always; only act on them -- deleting
# the file, the S3 patch, the overlay's patches: entry, and the live
# Backup CR -- when PRUNE_ORPHANED_BACKUPS=true, since removing a
# Backup CR is destructive and hard to reverse.
# --------------------------------------------------------------------
ORPHANED_LIST=()

is_discovered_safe_name() {
    local name="$1"
    local candidate
    for candidate in "${DISCOVERED_SAFE_NAMES[@]}"; do
        [ "$candidate" = "$name" ] && return 0
    done
    return 1
}

if [ -d "$BACKUP_DIR" ]; then
    for EXISTING_FILE in "$BACKUP_DIR"/mariadb-backup-*.yaml; do
        [ -e "$EXISTING_FILE" ] || continue
        EXISTING_BASENAME="$(basename "$EXISTING_FILE")"
        EXISTING_SAFE_NAME="${EXISTING_BASENAME#mariadb-backup-}"
        EXISTING_SAFE_NAME="${EXISTING_SAFE_NAME%.yaml}"

        is_discovered_safe_name "$EXISTING_SAFE_NAME" && continue

        ORPHANED_LIST+=("$EXISTING_SAFE_NAME")

        if [ "$PRUNE_ORPHANED_BACKUPS" = "true" ]; then
            ORPHAN_RESOURCE_NAME="mariadb-backup-${EXISTING_SAFE_NAME}"
            log "Pruning orphaned backup: $ORPHAN_RESOURCE_NAME (database no longer discovered)"

            rm -f "$EXISTING_FILE"

            kubectl -n "$NAMESPACE" delete backups.k8s.mariadb.com \
                "$ORPHAN_RESOURCE_NAME" --ignore-not-found >/dev/null 2>&1 || true

            if [ "$GENERATE_S3_PATCHES" = "true" ]; then
                ORPHAN_PATCH_BASENAME="${ORPHAN_RESOURCE_NAME}-s3.yaml"
                rm -f "$S3_OVERLAY_DIR/patches/${ORPHAN_PATCH_BASENAME}"
                remove_s3_patch_entry_from_overlay \
                    "$S3_OVERLAY_DIR/kustomization.yaml" "$ORPHAN_PATCH_BASENAME"
            fi
        fi
    done
fi

if [ "${#ORPHANED_LIST[@]}" -gt 0 ]; then
    if [ "$PRUNE_ORPHANED_BACKUPS" = "true" ]; then
        log "Pruned ${#ORPHANED_LIST[@]} orphaned backup(s): ${ORPHANED_LIST[*]}"
    else
        log "WARNING: ${#ORPHANED_LIST[@]} generated backup(s) no longer match a discovered database: ${ORPHANED_LIST[*]}"
        log "WARNING: their Backup CRs are left running as-is. Re-run with PRUNE_ORPHANED_BACKUPS=true to delete them, or ignore if intentional."
    fi
fi

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
# (Re)generate the nested kustomization.yaml from the full, current set
# of per-database manifests on disk -- not just the ones generated in
# this run -- so that databases skipped this run (because their Backup
# CR already exists) stay referenced, and pruned ones drop out.
# --------------------------------------------------------------------
FINAL_RESOURCE_LIST=()
if [ -d "$BACKUP_DIR" ]; then
    for EXISTING_FILE in "$BACKUP_DIR"/mariadb-backup-*.yaml; do
        [ -e "$EXISTING_FILE" ] || continue
        FINAL_RESOURCE_LIST+=("$(basename "$EXISTING_FILE")")
    done
fi

if [ "${#FINAL_RESOURCE_LIST[@]}" -gt 0 ]; then
    {
        echo "sortOptions:"
        echo "  order: fifo"
        echo "resources:"
        for RESOURCE in "${FINAL_RESOURCE_LIST[@]}"; do
            echo "  - ${RESOURCE}"
        done
    } > "$BACKUP_DIR/kustomization.yaml"
else
    log "WARNING: no per-database Backup manifests remain in $BACKUP_DIR; leaving kustomization.yaml untouched"
fi

# --------------------------------------------------------------------
# Ensure the parent MariaDB base kustomization.yaml references the
# "mariadb-backups" subdirectory, so `kubectl apply -k` on the base
# also picks up every generated per-database Backup CR. Only appends
# the entry if it isn't already present, leaving all existing
# resources (mariadb-configmap.yaml, mariadb-replication.yaml, etc.)
# untouched.
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

log "Generated ${#NEW_RESOURCE_LIST[@]} new Backup CRs"
log "Skipped ${#SKIPPED_LIST[@]} database(s) with existing Backup CRs"

if [ "${#SKIPPED_LIST[@]}" -gt 0 ]; then
    echo
    echo "Skipped (Backup CR already exists):"
    printf '  %s\n' "${SKIPPED_LIST[@]}"
fi

PRUNED_SOMETHING=false
if [ "$PRUNE_ORPHANED_BACKUPS" = "true" ] && [ "${#ORPHANED_LIST[@]}" -gt 0 ]; then
    PRUNED_SOMETHING=true
fi

if [ "${#NEW_RESOURCE_LIST[@]}" -eq 0 ] && [ "$PRUNED_SOMETHING" = "false" ]; then
    log "Nothing new to generate, prune, or apply."
    exit 0
fi

if [ "${#NEW_RESOURCE_LIST[@]}" -gt 0 ]; then
    echo
    echo "Generated files:"
    printf '  %s\n' "${NEW_RESOURCE_LIST[@]}"
fi
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
