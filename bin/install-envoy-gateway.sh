#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

set -eo pipefail

# Service
SERVICE_NAME_DEFAULT="envoyproxy-gateway"
SERVICE_NAMESPACE="envoyproxy-gateway-system"

GATEWAY_CONFIG_FILE=""
HELM_EXTRA_ARGS=()
POST_RENDERER_KUSTOMIZE="${SERVICE_NAME_DEFAULT}/overlay"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Missing secrets are generated in Kubernetes and
# existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|--gateway-config)
            if [[ $# -lt 2 ]]; then
                echo "Error: $1 requires a configuration file" >&2
                exit 1
            fi
            GATEWAY_CONFIG_FILE="$2"
            shift 2
            ;;
        --config=*|--gateway-config=*)
            GATEWAY_CONFIG_FILE="${1#*=}"
            shift
            ;;
        *)
            HELM_EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [ -n "${GATEWAY_CONFIG_FILE}" ]; then
    POST_RENDERER_KUSTOMIZE="${SERVICE_NAME_DEFAULT}/config-mode"
fi

ensure_post_renderer_kustomize() {
    local service_kustomize_dir="${GENESTACK_OVERRIDES_DIR}/kustomize/${SERVICE_NAME_DEFAULT}"
    local base_kustomize_dir="${GENESTACK_BASE_DIR}/base-kustomize/${SERVICE_NAME_DEFAULT}"
    local renderer_name="${POST_RENDERER_KUSTOMIZE#"${SERVICE_NAME_DEFAULT}"/}"

    if [ ! -x "${GENESTACK_OVERRIDES_DIR}/kustomize/kustomize.sh" ]; then
        if [ ! -f "${GENESTACK_BASE_DIR}/base-kustomize/kustomize.sh" ]; then
            echo "Error: kustomize post-renderer script not found" >&2
            exit 1
        fi
        mkdir -p "${GENESTACK_OVERRIDES_DIR}/kustomize"
        ln -sfn "${GENESTACK_BASE_DIR}/base-kustomize/kustomize.sh" "${GENESTACK_OVERRIDES_DIR}/kustomize/kustomize.sh"
    fi

    mkdir -p "${service_kustomize_dir}"
    for renderer_part in base "${renderer_name}"; do
        if [ ! -e "${service_kustomize_dir}/${renderer_part}" ] && [ ! -L "${service_kustomize_dir}/${renderer_part}" ]; then
            if [ ! -d "${base_kustomize_dir}/${renderer_part}" ]; then
                echo "Error: Envoy post-renderer path not found: ${base_kustomize_dir}/${renderer_part}" >&2
                exit 1
            fi
            ln -s "${base_kustomize_dir}/${renderer_part}" "${service_kustomize_dir}/${renderer_part}"
        fi
    done
}

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

ensure_post_renderer_kustomize

# Collect Helm values files in override order.
build_helm_args "$SERVICE_NAME_DEFAULT" || exit 1

# Collect all --set arguments, executing commands and quoting safely
# Collect secret-backed --set arguments from bin/services/${SERVICE_NAME_DEFAULT}.yaml.
collect_service_secret_set_args "$SERVICE_NAME_DEFAULT"
set_args=("${SECRET_HELM_SET_ARGS[@]}")


helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace "${SERVICE_NAMESPACE}"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$POST_RENDERER_KUSTOMIZE"

    "${HELM_EXTRA_ARGS[@]}"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"

## Install egctl Binary (Post-Installation)

GITHUB_MIRROR_URL="${GITHUB_MIRROR_URL:-https://github.com}"

# Install egctl
if [ ! -f "/usr/local/bin/egctl" ]; then
    echo "Installing egctl CLI..."
    EGCTL_COMPLETION_FILE="$(mk_tmp_file)"
    sudo mkdir -p /opt/egctl-install
    pushd /opt/egctl-install || exit 1
        # Use the extracted version for wget
        sudo wget "${GITHUB_MIRROR_URL}/envoyproxy/gateway/releases/download/${SERVICE_VERSION}/egctl_${SERVICE_VERSION}_linux_amd64.tar.gz" -O egctl.tar.gz
        sudo tar -xvf egctl.tar.gz
        sudo install -o root -g root -m 0755 bin/linux/amd64/egctl /usr/local/bin/egctl
        /usr/local/bin/egctl completion bash > "${EGCTL_COMPLETION_FILE}"
        sudo install -o root -g root -m 0644 "${EGCTL_COMPLETION_FILE}" /etc/bash_completion.d/egctl
    popd || exit 1
fi

if [ -n "${GATEWAY_CONFIG_FILE}" ]; then
    echo "Waiting for the envoyproxy-gateway to be available"
    kubectl -n "${SERVICE_NAMESPACE}" wait --timeout=5m deployments.apps/envoy-gateway --for=condition=available

    echo "Applying Envoy Gateway configuration from ${GATEWAY_CONFIG_FILE}"
    "${SCRIPT_DIR}/setup-envoy-gateway.sh" --config "${GATEWAY_CONFIG_FILE}"
fi
