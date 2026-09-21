#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
# The service name is used for both the release name and the chart name.
SERVICE_NAME_DEFAULT="barbican"
SERVICE_NAMESPACE="openstack"

# Helm
HELM_REPO_NAME_DEFAULT="openstack-helm"
HELM_REPO_URL_DEFAULT="https://tarballs.opendev.org/openstack/openstack-helm"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

# Define the Global Overrides directory used in the original script
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract version dynamically using the SERVICE_NAME_DEFAULT variable
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME_DEFAULT}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME_DEFAULT}: *//")

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME_DEFAULT' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# Load chart metadata from custom override YAML if defined
for yaml_file in "${SERVICE_CUSTOM_OVERRIDES}"/*.yaml; do
    if [ -f "$yaml_file" ]; then
        HELM_REPO_URL=$(yq eval '.chart.repo_url // ""' "$yaml_file")
        HELM_REPO_NAME=$(yq eval '.chart.repo_name // ""' "$yaml_file")
        SERVICE_NAME=$(yq eval '.chart.service_name // ""' "$yaml_file")
        break  # use the first match and stop
    fi
done

# Fallback to defaults if variables not set
: "${HELM_REPO_URL:=$HELM_REPO_URL_DEFAULT}"
: "${HELM_REPO_NAME:=$HELM_REPO_NAME_DEFAULT}"
: "${SERVICE_NAME:=$SERVICE_NAME_DEFAULT}"


# Determine Helm chart path
if [[ "$HELM_REPO_URL" == oci://* ]]; then
    # OCI registry path
    HELM_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$SERVICE_NAME"
else
    # --- Helm Repository and Execution ---
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
    helm repo update
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi


# Debug output
echo "[DEBUG] HELM_REPO_URL=$HELM_REPO_URL"
echo "[DEBUG] HELM_REPO_NAME=$HELM_REPO_NAME"
echo "[DEBUG] SERVICE_NAME=$SERVICE_NAME"
echo "[DEBUG] HELM_CHART_PATH=$HELM_CHART_PATH"

# Prepare an array to collect -f arguments
overrides_args=()

# Include all YAML files from the BASE configuration directory
# NOTE: Files in this directory are included first.
if [[ -d "$SERVICE_BASE_OVERRIDES" ]]; then
    echo "Including base overrides from directory: $SERVICE_BASE_OVERRIDES"
    for file in "$SERVICE_BASE_OVERRIDES"/*.yaml; do
        # Check that there is at least one match
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Base override directory not found: $SERVICE_BASE_OVERRIDES"
fi

# Include all YAML files from the GLOBAL configuration directory
# NOTE: Files here override base settings and are applied before service-specific ones.
if [[ -d "$GLOBAL_OVERRIDES_DIR" ]]; then
    echo "Including global overrides from directory: $GLOBAL_OVERRIDES_DIR"
    for file in "$GLOBAL_OVERRIDES_DIR"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Global override directory not found: $GLOBAL_OVERRIDES_DIR"
fi

# Include all YAML files from the custom SERVICE configuration directory
# NOTE: Files here have the highest precedence.
if [[ -d "$SERVICE_CUSTOM_OVERRIDES" ]]; then
    echo "Including overrides from service config directory:"
    for file in "$SERVICE_CUSTOM_OVERRIDES"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Service config directory not found: $SERVICE_CUSTOM_OVERRIDES"
fi

echo

# Collect all --set arguments, executing commands and quoting safely
set_args=(
    --set "endpoints.identity.auth.admin.password=$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.barbican.password=$(kubectl --namespace openstack get secret barbican-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.admin.password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.barbican.password=$(kubectl --namespace openstack get secret barbican-db-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "conf.barbican.database.connection=mysql+pymysql://barbican:$(kubectl --namespace openstack get secret barbican-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-primary:3306/barbican?charset=utf8"
    --set "endpoints.oslo_messaging.auth.admin.password=$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_messaging.auth.barbican.password=$(kubectl --namespace openstack get secret barbican-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
    --set "conf.barbican.keystone_authtoken.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
)

# SoftHSM p11 is the default in base helm. Treat it as enabled when any
# values file (base, global, or site) has both p11_crypto and libsofthsm2,
# or when a hyperconverged/lab flag is set.
override_file="${SERVICE_CUSTOM_OVERRIDES}/barbican-helm-overrides.yaml"
SOFTHSM_P11=false
for ((i = 0; i < ${#overrides_args[@]}; i++)); do
    if [[ "${overrides_args[$i]}" == "-f" ]]; then
        f="${overrides_args[$((i + 1))]}"
        if [[ -f "${f}" ]] \
            && grep -q "p11_crypto" "${f}" 2>/dev/null \
            && grep -q "libsofthsm2" "${f}" 2>/dev/null; then
            SOFTHSM_P11=true
            break
        fi
    fi
done
if [[ "${BARBICAN_HSM_ENABLED:-false}" == "true" ]] || [[ "${HYPERCONVERGED_BARBICAN_HSM:-false}" == "true" ]]; then
    SOFTHSM_P11=true
    # Generate a SoftHSM overlay only when no site file exists. Never rewrite
    # an existing environment override (region, images, policy would be lost).
    if [[ ! -f "${override_file}" ]]; then
        echo "HSM enabled and ${override_file} is missing. Generating SoftHSM overlay..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/../scripts/lib/hyperconverged-common.sh"
        writeServiceHelmOverrides "${GENESTACK_OVERRIDES_DIR}/helm-configs"
    fi
fi

# Ensure barbican-hsm-credentials exists. create-secrets.sh does this on
# greenfield; brownfield never re-runs that script, so the install path
# creates the secret once and leaves it alone on later upgrades.
if [[ "${SOFTHSM_P11}" == "true" ]]; then
    existing_pin="$(kubectl --namespace openstack get secret barbican-hsm-credentials \
        -o jsonpath='{.data.pin}' 2>/dev/null | base64 -d)" || true
    if [[ -n "${existing_pin}" ]]; then
        echo "barbican-hsm-credentials already present — leaving PIN unchanged"
    else
        echo "Creating barbican-hsm-credentials (missing on this brownfield cluster)"
        hsm_pin="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(32)))')"
        kubectl --namespace openstack create secret generic barbican-hsm-credentials \
            --from-literal=pin="${hsm_pin}" --dry-run=client -o yaml | \
            kubectl apply -f -
        unset hsm_pin
    fi
    unset existing_pin
fi

# PKCS#11 SoftHSM2 PIN Injection
hsm_pin="$(kubectl --namespace openstack get secret barbican-hsm-credentials \
    -o jsonpath='{.data.pin}' 2>/dev/null | base64 -d)" || true
if [[ -n "${hsm_pin}" ]]; then
    echo "HSM credentials found - injecting p11_crypto_plugin.login"
    set_args+=(
        --set "conf.barbican.p11_crypto_plugin.login=${hsm_pin}"
    )
fi
unset hsm_pin

# =============================================================================
# Barbican simple_crypto master KEK
#
# Gazpacho barbican has no built-in default kek: with simple_crypto enabled and
# no kek rendered into barbican.conf, barbican-api crashloops with
# "SimpleCrypto KEK is undefined". A kek set in an override file is deployed as
# is. Otherwise the source of truth is the Kubernetes Secret
# barbican-simple-crypto-kek, written by create-secrets.sh on greenfield:
#   kek       44-char Fernet key -> [simple_crypto_plugin] kek
#   old_keks  comma-separated history -> db-sync rewrap old_kek
#
# The chart's db-sync job rewraps every simple_crypto project KEK one-way from
# old_kek onto the rendered kek; a row it cannot unwrap fails the job, which
# barbican-api waits on (an outage, not data loss). Rotations of a
# Secret-managed kek are staged with scripts/rotate-barbican-kek.py, which this
# script never calls.
#
# PROLOGUE
#   override_kek = conf.barbican.simple_crypto_plugin.kek from the -f files,
#                  last file wins
#   secret_kek   = read_secret(barbican-simple-crypto-kek, kek)
#
# CASE 1  override_kek set          -> deploy as is: the -f files carry the
#                                      kek and any old_kek; nothing is
#                                      injected, no Secret is written
#                                      (NOTICE if a Secret also exists)
#
# CASE 2  secret_kek set            -> abort if it fails kek_format_ok
#                                      -> GUARD + INJECT
#
# CASE 3  no Secret, rows > 0       -> abort: barbican data is wrapped with
#         (or rows unreadable)         a kek nobody manages. Adopt it into
#                                      the Secret (scripts/rotate-barbican-kek.py
#                                      --adopt checks it against the
#                                      database first), then re-run
#
# CASE 4  no Secret, no rows        -> kubectl apply Secret
#                                      {kek: 32 random bytes, old_keks: ""}
#                                      -> INJECT (nothing to rewrap, no GUARD)
#
# GUARD   secret_old   = read_secret(..., old_keks)
#         deployed_kek = kek_deployed(): the first "kek =" under
#                        [simple_crypto_plugin] in the rendered barbican.conf;
#                        no kek line: the upstream default; no release: empty
#   no release               -> deploy  (nothing to compare)
#   secret_kek == deployed   -> deploy  (rewrap is a no-op)
#   deployed in secret_old   -> deploy with WARNING: staged rotation,
#                               one-way rewrap, back up the DB first
#   kek_data_rows() == 0     -> deploy  (nothing to rewrap)
#   otherwise                -> abort   (rewrap could not succeed)
#
# INJECT
#   --set-string conf.barbican.simple_crypto_plugin.kek=secret_kek
#   --set-string conf.simple_crypto_kek_rewrap.old_kek=secret_old
# =============================================================================
KEK_SECRET="barbican-simple-crypto-kek"
# Upstream default kek that every pre-Gazpacho deploy without an explicit kek
# ran on. Public knowledge (OpenStack docs, OSH chart values); derived at
# runtime so no key-shaped blob sits in the repo.
KEK_WELL_KNOWN="$(printf '%s' 'thirty_two_byte_keyblahblahblahh' | base64 | tr -d '\n')"

# Decoded data key of a Secret in the service namespace; empty when absent.
read_secret() {
    kubectl --namespace "$SERVICE_NAMESPACE" get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null \
        | base64 -d 2>/dev/null || true
}

# 44 chars that base64-decode to exactly 32 bytes: a Fernet key.
kek_format_ok() {
    [[ ${#1} -eq 44 ]] && (( $(printf '%s' "$1" | tr -- '-_' '+/' | base64 -d 2>/dev/null | wc -c) == 32 ))
}

# The kek the running release renders into barbican.conf: the first "kek ="
# line under [simple_crypto_plugin] in the barbican-etc Secret (the rule the
# rotation tool applies too, so a kek option in another section is never
# mistaken for it). Prints nothing when there is no release. A release with no
# kek line is a pre-Gazpacho deploy on the implicit upstream default, so that
# default is what it prints then.
kek_deployed() {
    local conf section line
    conf="$(read_secret barbican-etc 'barbican\.conf')"
    [[ -n "$conf" ]] || return 0
    # the [simple_crypto_plugin] section only: from its header up to the next header
    section="$(sed -n '/^\[simple_crypto_plugin\]/,/^\[/p' <<< "$conf")"
    # the first kek line; when there are several, the first one encrypts
    line="$(grep -m1 -E '^[[:space:]]*kek[[:space:]]*=' <<< "$section")"
    if [[ -z "$line" ]]; then
        printf '%s' "$KEK_WELL_KNOWN"
        return 0
    fi
    line="${line#*=}"                     # drop "kek =", keeping the key's own trailing =
    printf '%s' "${line//[[:space:]]/}"  # and any surrounding whitespace
}

# Number of simple_crypto project KEKs in barbican.kek_data, read on the MariaDB
# primary. Uses the root credential the deploy already holds: the barbican
# database user does not exist before the first barbican deploy, and cases 3
# and 4 need this probe to answer "no table yet" rather than "access denied"
# then. The password travels over stdin, never argv. Prints 0 when barbican has
# no schema yet; fails when the database cannot be reached.
kek_data_rows() {
    local pod pw out err
    pod="$(kubectl --namespace "$SERVICE_NAMESPACE" get pod \
        -l app.kubernetes.io/name=mariadb,k8s.mariadb.com/role=primary \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
    pw="$(read_secret mariadb root-password)"
    [[ -n "$pod" && -n "$pw" ]] || return 1
    err="$(mktemp)"
    # stderr goes to a file so client warnings can never be mistaken for the count
    out="$(kubectl --namespace "$SERVICE_NAMESPACE" exec -i "$pod" -c mariadb -- \
        sh -c "MYSQL_PWD=\$(cat) mariadb -uroot -N -B -e \"SELECT COUNT(*) FROM barbican.kek_data WHERE plugin_name = 'barbican.plugin.crypto.simple_crypto.SimpleCryptoPlugin'\"" \
        <<< "$pw" 2>"$err" | tail -n1)"
    if [[ "$out" =~ ^[0-9]+$ ]]; then
        rm -f "$err"; echo "$out"
    elif grep -qE "ERROR (1146|1049)" "$err"; then
        rm -f "$err"; echo 0        # no barbican schema or table yet
    else
        rm -f "$err"; return 1      # connection or auth failure
    fi
}

# kek set in an override file: the last file wins (helm precedence). Only its
# presence matters here; the -f files deliver the value to helm as is.
override_kek=""
for f in "${overrides_args[@]}"; do
    [[ "$f" == "-f" ]] && continue
    v="$(yq eval '.conf.barbican.simple_crypto_plugin.kek // ""' "$f" 2>/dev/null | head -n1)"
    [[ -n "$v" && "$v" != "null" ]] && override_kek="$v"
done
secret_kek="$(read_secret "$KEK_SECRET" kek)"

if [[ -n "$override_kek" ]]; then
    # Case 1: the override files carry the kek (and any old_kek).
    echo "conf.barbican.simple_crypto_plugin.kek is set in the override files: deploying it as is."
    if [[ -n "$secret_kek" ]]; then
        echo "NOTICE: ${KEK_SECRET} exists but is ignored while the override files set the kek."
    fi
elif [[ -n "$secret_kek" ]]; then
    # Case 2: the Secret is the kek. Guard the db-sync rewrap before injecting it.
    if ! kek_format_ok "$secret_kek"; then
        echo "ERROR: ${KEK_SECRET} holds a value that is not a 44-char Fernet key; refusing to deploy" >&2
        exit 1
    fi
    secret_old="$(read_secret "$KEK_SECRET" old_keks)"
    deployed_kek="$(kek_deployed)"
    if [[ -z "$deployed_kek" ]]; then
        echo "no barbican release yet: injecting the kek from ${KEK_SECRET}."
    elif [[ "$secret_kek" == "$deployed_kek" ]]; then
        echo "Secret kek matches the deployed kek; the db-sync rewrap is a no-op."
    elif [[ ",${secret_old}," == *",${deployed_kek},"* ]]; then
        # A staged rotation. rotate-barbican-kek.py --stage records the deployed
        # kek in old_keks, and old_keks is exactly what is injected below, so the
        # rewrap's decryptor set never depends on a chart default.
        echo "WARNING: Secret kek differs from the deployed kek: this deploy performs a ONE-WAY rewrap of"
        echo "         every simple_crypto project KEK during db-sync. Back up the barbican DB first."
        echo "         Afterwards run: ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --validate deployed"
        echo "         and confirm the db-sync job logs show zero rewrap failures."
    elif rows="$(kek_data_rows)" && (( rows == 0 )); then
        # Nothing is wrapped yet (a first install that crashlooped before db-sync
        # wrapped anything): there is no rotation to arm, the Secret simply becomes
        # the kek.
        echo "Secret kek differs from the deployed kek, but barbican.kek_data holds no simple_crypto"
        echo "project keys; there is nothing to rewrap."
    else
        echo "ERROR: Secret kek differs from the deployed kek, and the deployed kek is not in" >&2
        echo "       ${KEK_SECRET}/old_keks, so the db-sync rewrap could not unwrap the existing project" >&2
        echo "       keys and barbican would not start. Not deploying. Stage rotations only with" >&2
        echo "       ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --stage (it records the deployed" >&2
        echo "       kek in old_keks), or delete the Secret deliberately and re-adopt the deployed kek with" >&2
        echo "       ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --adopt before re-running this install." >&2
        exit 1
    fi
else
    # No Secret and no override: whether barbican already holds data decides.
    if ! rows="$(kek_data_rows)"; then
        echo "ERROR: ${KEK_SECRET} is absent and barbican.kek_data could not be read on the MariaDB primary," >&2
        echo "       so whether barbican data exists is unknown. Refusing to generate a kek that existing data" >&2
        echo "       may not be wrapped with. Restore database access and re-run." >&2
        exit 1
    fi
    if (( rows > 0 )); then
        # Case 3: the rows are wrapped with a kek nothing manages. Deploying
        # without one crashloops barbican-api; guessing one strands the rows.
        echo "ERROR: barbican.kek_data holds ${rows} simple_crypto project KEK(s) and ${KEK_SECRET} is absent:" >&2
        echo "       the kek they are wrapped with is not managed anywhere, and a Gazpacho barbican without a" >&2
        echo "       kek does not start. Not deploying. Adopt the deployed kek into the Secret (it is" >&2
        echo "       checked against the database first), then re-run this install:" >&2
        echo "         ${GENESTACK_BASE_DIR}/scripts/rotate-barbican-kek.py --adopt" >&2
        exit 1
    fi
    # Case 4 (also recovers a first Gazpacho install that crashlooped before wrapping anything)
    echo "no simple_crypto data in barbican.kek_data and ${KEK_SECRET} is absent: generating a fresh kek."
    # 32 random bytes, urlsafe base64: the Fernet key format. The Secret is
    # written over stdin so the kek never appears in argv or ps.
    new_kek="$(head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')"
    kubectl --namespace "$SERVICE_NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${KEK_SECRET}
  namespace: ${SERVICE_NAMESPACE}
type: Opaque
data:
  kek: $(printf '%s' "$new_kek" | base64 | tr -d '\n')
  old_keks: ""
EOF
    unset new_kek
    # Read it back: only a kek that is actually stored gets injected.
    secret_kek="$(read_secret "$KEK_SECRET" kek)"
    secret_old=""
    if ! kek_format_ok "$secret_kek"; then
        echo "ERROR: ${KEK_SECRET} still holds no valid kek after generating one" >&2
        exit 1
    fi
    echo "fresh kek: the db-sync rewrap has no project keys to process."
fi

# Inject (cases 2 and 4).
if [[ -z "$override_kek" ]]; then
    set_args+=(--set-string "conf.barbican.simple_crypto_plugin.kek=${secret_kek}")
    if [[ -n "$secret_old" ]]; then
        # a comma is --set list syntax; escape it so the whole history survives as one string
        set_args+=(--set-string "conf.simple_crypto_kek_rewrap.old_kek=${secret_old//,/\\,}")
    fi
fi

helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"

# Post-Install SoftHSM2 Key Initialization (token, MKEK, HMAC).
# Runs when the site override already enables SoftHSM p11, or when the
# hyperconverged/lab HSM flags are set. No extra env var required.
if [[ "${SOFTHSM_P11}" == "true" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if ! declare -f initBarbicanHSMKeys >/dev/null 2>&1; then
        common_sh="${SCRIPT_DIR}/../scripts/lib/hyperconverged-common.sh"
        if [[ -f "${common_sh}" ]]; then
            # shellcheck source=/dev/null
            source "${common_sh}" >/dev/null 2>&1 || true
        fi
    fi

    if declare -f initBarbicanHSMKeys >/dev/null 2>&1; then
        initBarbicanHSMKeys
    else
        echo "ERROR: initBarbicanHSMKeys not found; SoftHSM keys were not initialized"
        exit 1
    fi
fi
