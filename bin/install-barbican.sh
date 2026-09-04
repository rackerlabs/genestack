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

# Detects if missing PKCS#11 HSM p11_crypto_plugin and regenerates the file automatically.
if [[ "${BARBICAN_HSM_ENABLED:-false}" == "true" ]] || [[ "${HYPERCONVERGED_BARBICAN_HSM:-false}" == "true" ]]; then

    override_file="${SERVICE_CUSTOM_OVERRIDES}/barbican-helm-overrides.yaml"

    # If override file is missing OR does not contain p11_crypto_plugin, regenerate it
    if [[ ! -f "${override_file}" ]] || ! grep -q "p11_crypto_plugin" "${override_file}" 2>/dev/null; then
        echo "HSM enabled but p11_crypto_plugin missing in ${override_file}. Regenerating..."
        rm -f "${override_file}"
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/../scripts/lib/hyperconverged-common.sh"
        writeServiceHelmOverrides "${GENESTACK_OVERRIDES_DIR}/helm-configs"
    fi
fi

# PKCS#11 HSM PIN Injection
# Reads PIN from barbican-hsm-credentials K8s Secret (created by create-secrets.sh).
# No-op when secret doesn't exist or PIN is empty.
hsm_pin="$(kubectl --namespace openstack get secret barbican-hsm-credentials \
    -o jsonpath='{.data.pin}' 2>/dev/null | base64 -d)" || true
if [[ -n "${hsm_pin}" ]]; then
    echo "HSM credentials found - injecting p11_crypto_plugin.login"
    set_args+=(
        --set "conf.barbican.p11_crypto_plugin.login=${hsm_pin}"
    )
fi
unset hsm_pin

# ============================================================================
# Barbican simple_crypto master KEK injection
#
# Reads the KEK from the barbican-simple-crypto-plugin-kek Kubernetes Secret
# and injects it via --set (highest helm precedence, overrides all -f files).
# If the Secret is absent or empty, the --set is skipped and the kek must
# come from the helm-overrides files: Gazpacho barbican has no built-in
# default and fails to start without an explicit kek.
#
# *** WARNING: CHANGING THE SECRET TRIGGERS KEY ROTATION ON NEXT DEPLOY ***
# The chart defaults simple_crypto_kek_rewrap.old_kek to the well-known
# default, so as soon as this --set supplies a kek, the db-sync job's rewrap
# gate is armed. While the Secret holds the well-known default the rewrap is
# an idempotent no-op. The FIRST deploy after the Secret is changed to a new
# key performs a ONE-WAY rewrap of every project KEK in the barbican DB
# during db-sync. Before changing the Secret's value:
#   1. Back up the barbican database (and verify the restore).
#   2. Stage rotations ONLY with scripts/barbican-kek-rewrite-planner.py
#      (--apply / --adopt); it validates the deployed kek against the DB
#      and records the old_keks history the rewrap depends on.
#   3. Plan for the brief window where not-yet-rolled API pods hold the
#      old kek after the rewrap completes.
#   4. Afterward: 'barbican-kek-rewrite-planner.py --validate deployed'
#      must pass, and the db-sync job logs must show zero rewrap failures.
# Do NOT edit the Secret as part of a routine chart/version bump.
# ============================================================================
barbican_kek="$(kubectl --namespace openstack get secret barbican-simple-crypto-plugin-kek \
    -o jsonpath='{.data.barbican_simple_crypto_plugin_kek}' 2>/dev/null | base64 -d 2>/dev/null || true)"

if [[ -n "$barbican_kek" ]]; then
    if [[ ${#barbican_kek} -eq 44 ]] && \
       (( $(printf '%s' "$barbican_kek" | tr -- '-_' '+/' | base64 -d 2>/dev/null | wc -c) == 32 )); then
        set_args+=(--set "conf.barbican.simple_crypto_plugin.kek=${barbican_kek}")
    else
        echo "ERROR: barbican-simple-crypto-plugin-kek exists but is not a valid 44-char Fernet key; refusing to deploy" >&2
        exit 1
    fi
else
    echo "NOTICE: barbican-simple-crypto-plugin-kek absent/empty; kek must come from helm overrides" >&2
    # Gazpacho barbican has NO built-in default kek: if nothing renders a
    # kek into barbican.conf, barbican-api fails to start with
    # 'SimpleCrypto KEK is undefined'. Predict that here instead of
    # discovering it in crashlooping pods. Advisory only, not fatal:
    # simple_crypto may be legitimately disabled (e.g. HSM-only).
    kek_in_overrides=false
    for f in "${overrides_args[@]}"; do
        [[ "$f" == "-f" ]] && continue
        if grep -Eq '^[[:space:]]*kek[[:space:]]*:' "$f" 2>/dev/null; then
            kek_in_overrides=true
            break
        fi
    done
    if [[ "$kek_in_overrides" == "false" ]]; then
        echo "WARNING: no 'kek:' found in any override file either." >&2
        echo "         Gazpacho barbican requires an explicit kek; if simple_crypto is" >&2
        echo "         enabled this deploy WILL fail: 'SimpleCrypto KEK is undefined'." >&2
        if kubectl --namespace openstack get secret barbican-etc >/dev/null 2>&1; then
            echo "         Existing barbican detected: run" >&2
            echo "         scripts/barbican-kek-rewrite-planner.py --adopt (see release notes)" >&2
            echo "         to stage the currently active kek, then re-run this install." >&2
        fi
    fi
fi
unset barbican_kek

barbican_old_keks="$(kubectl --namespace openstack get secret barbican-simple-crypto-plugin-kek \
    -o jsonpath='{.data.old_keks}' 2>/dev/null | base64 -d 2>/dev/null || true)"

if [[ -n "$barbican_old_keks" ]]; then
    # comma is --set list syntax; escape so the whole history survives as one string
    set_args+=(--set-string "conf.simple_crypto_kek_rewrap.old_kek=${barbican_old_keks//,/\\,}")
fi
# absent/empty -> chart default old_kek (well-known) applies; no action needed
unset barbican_old_keks

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

# Post-Install HSM Key Initialization
# Runs ONLY in Hyperconverged lab when:
#   1. BARBICAN_HSM_ENABLED=true (exported during automated hyperconverged lab run)
#   2. HYPERCONVERGED_BARBICAN_HSM=true (set manually when running script directly)
if [[ "${BARBICAN_HSM_ENABLED:-false}" == "true" ]] || [[ "${HYPERCONVERGED_BARBICAN_HSM:-false}" == "true" ]]; then
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
    fi
fi
