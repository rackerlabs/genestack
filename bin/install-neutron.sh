#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME_DEFAULT="neutron"
SERVICE_NAMESPACE="openstack"

# Helm
HELM_REPO_NAME_DEFAULT="openstack-helm"
HELM_REPO_URL_DEFAULT="https://tarballs.opendev.org/openstack/openstack-helm"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Missing secrets are generated in Kubernetes and
# existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

# Define the Global Overrides directory used in the original script
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Read the desired chart version from VERSION_FILE
# NOTE: Ensure this file exists and contains an entry for SERVICE_NAME_DEFAULT.
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
    helm repo add --force-update "$HELM_REPO_NAME" "$HELM_REPO_URL" 2>/dev/null || true
    helm repo update
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi

# Debug output
echo "[DEBUG] HELM_REPO_URL=$HELM_REPO_URL"
echo "[DEBUG] HELM_REPO_NAME=$HELM_REPO_NAME"
echo "[DEBUG] SERVICE_NAME=$SERVICE_NAME"
echo "[DEBUG] HELM_CHART_PATH=$HELM_CHART_PATH"

# Resolve Kube-OVN's effective TLS setting, including chart defaults.
source "${GENESTACK_BASE_DIR}/scripts/lib/functions.sh"
ensureYq

if ! KUBE_OVN_VALUES=$(helm --namespace kube-system get values kube-ovn --all --output yaml); then
    echo "Error: Unable to read effective values for the kube-ovn release." >&2
    exit 1
fi

KUBE_OVN_ENABLE_SSL=$(printf '%s\n' "$KUBE_OVN_VALUES" | yq eval -r '.networking.ENABLE_SSL // false' -)
OVN_TLS_OVERRIDES="${SERVICE_BASE_OVERRIDES}/ssl/neutron-ovn-tls-overrides.yaml"

case "$KUBE_OVN_ENABLE_SSL" in
    true)
        CONNECTION_STRING="ssl"

        if [[ ! -f "$OVN_TLS_OVERRIDES" ]]; then
            echo "Error: Neutron OVN TLS overrides not found at $OVN_TLS_OVERRIDES" >&2
            exit 1
        fi

        if ! secret_exists kube-system kube-ovn-tls; then
            echo "Error: kube-ovn has networking.ENABLE_SSL=true, but kube-system/kube-ovn-tls is unavailable." >&2
            exit 1
        fi

        if ! secret_has_keys kube-system kube-ovn-tls cacert cert key; then
            echo "Error: kube-system/kube-ovn-tls must contain cacert, cert, and key." >&2
            exit 1
        fi

        if ! ensure_ovn_client_tls_secret kube-system openstack kube-ovn-tls ovn-client-tls; then
            echo "Error: Unable to synchronize openstack/ovn-client-tls." >&2
            exit 1
        fi
        ;;
    false)
        CONNECTION_STRING="tcp"
        ;;
    *)
        echo "Error: networking.ENABLE_SSL must be true or false; got '$KUBE_OVN_ENABLE_SSL'." >&2
        exit 1
        ;;
esac

echo "Using ${CONNECTION_STRING} connections for the OVN northbound and southbound databases."

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

# TLS mounts and client settings must only be rendered when Kube-OVN uses SSL.
if [[ "$KUBE_OVN_ENABLE_SSL" == "true" ]]; then
    echo "Including Kube-OVN TLS overrides: $OVN_TLS_OVERRIDES"
    overrides_args+=("-f" "$OVN_TLS_OVERRIDES")
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

if ! OVN_NB_ENDPOINT=$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}') \
    || [[ -z "$OVN_NB_ENDPOINT" ]]; then
    echo "Error: Unable to resolve the ovn-nb service endpoint." >&2
    exit 1
fi

if ! OVN_SB_ENDPOINT=$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}') \
    || [[ -z "$OVN_SB_ENDPOINT" ]]; then
    echo "Error: Unable to resolve the ovn-sb service endpoint." >&2
    exit 1
fi

# Collect all --set arguments, executing commands and quoting safely
# NOTE: This array contains OpenStack-specific secret retrievals and MUST be updated
#       with the necessary --set arguments for your target SERVICE_NAME_DEFAULT.
# Collect secret-backed --set arguments from bin/services/${SERVICE_NAME_DEFAULT}.yaml.
collect_service_secret_set_args "$SERVICE_NAME_DEFAULT"
set_args=("${SECRET_HELM_SET_ARGS[@]}")

set_args+=(
    --set "conf.neutron.ovn.ovn_nb_connection=$CONNECTION_STRING:$OVN_NB_ENDPOINT"
    --set "conf.neutron.ovn.ovn_sb_connection=$CONNECTION_STRING:$OVN_SB_ENDPOINT"
    --set "conf.plugins.ml2_conf.ovn.ovn_nb_connection=$CONNECTION_STRING:$OVN_NB_ENDPOINT"
    --set "conf.plugins.ml2_conf.ovn.ovn_sb_connection=$CONNECTION_STRING:$OVN_SB_ENDPOINT"
    --set "conf.ovn_metadata_agent.ovn.ovn_nb_connection=$CONNECTION_STRING:$OVN_NB_ENDPOINT"
    --set "conf.ovn_metadata_agent.ovn.ovn_sb_connection=$CONNECTION_STRING:$OVN_SB_ENDPOINT"
)


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
