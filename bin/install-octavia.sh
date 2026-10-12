#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME_DEFAULT="octavia"
SERVICE_NAMESPACE="openstack"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Missing secrets are generated in Kubernetes and
# existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT

# Load the service configuration once for this installer.
service_config=$(load_service_config "$SERVICE_NAME_DEFAULT" --log-sources) || exit 1

# Resolve the chart version from the service config or chart versions file.
SERVICE_VERSION=$(resolve_chart_version "$SERVICE_NAME_DEFAULT" "$service_config") || exit 1

if [[ -z "$SERVICE_VERSION" ]]; then
    log_error "No chart version found for '$SERVICE_NAME_DEFAULT'."
    exit 1
fi

# Resolve the chart location from the service configuration.
resolve_service_chart "$SERVICE_NAME_DEFAULT" "$service_config" || exit 1

# Resolve Kube-OVN's effective TLS setting, including chart defaults.
source "${GENESTACK_BASE_DIR}/scripts/lib/functions.sh"
ensureYq

if ! KUBE_OVN_VALUES=$(helm --namespace kube-system get values kube-ovn --all --output yaml); then
    echo "Error: Unable to read effective values for the kube-ovn release." >&2
    exit 1
fi

KUBE_OVN_ENABLE_SSL=$(printf '%s\n' "$KUBE_OVN_VALUES" | yq eval -r '.networking.ENABLE_SSL // false' -)
OVN_TLS_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}/ssl/octavia-ovn-tls-overrides.yaml"

case "$KUBE_OVN_ENABLE_SSL" in
    true)
        CONNECTION_STRING="ssl"

        if [[ ! -f "$OVN_TLS_OVERRIDES" ]]; then
            echo "Error: Octavia OVN TLS overrides not found at $OVN_TLS_OVERRIDES" >&2
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

if [[ "$KUBE_OVN_ENABLE_SSL" == "true" ]]; then
    build_helm_args "$SERVICE_NAME_DEFAULT" "$OVN_TLS_OVERRIDES" || exit 1
else
    build_helm_args "$SERVICE_NAME_DEFAULT" || exit 1
fi

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
    --set "conf.octavia.ovn.ovn_nb_connection=$CONNECTION_STRING:$OVN_NB_ENDPOINT"
    --set "conf.octavia.ovn.ovn_sb_connection=$CONNECTION_STRING:$OVN_SB_ENDPOINT"
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
    --post-renderer "$GENESTACK_BASE_DIR/base-kustomize/octavia/post-renderer.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
export GENESTACK_OVERRIDES_DIR
export GENESTACK_KUBE_OVN_ENABLE_SSL="$KUBE_OVN_ENABLE_SSL"
"${helm_command[@]}"
