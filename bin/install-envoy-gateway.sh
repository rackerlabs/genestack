#!/bin/bash
# Description: Fetches the version for Envoy Gateway and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="envoyproxy-gateway"
SERVICE_NAMESPACE="envoyproxy-gateway-system"

# Helm Defaults (OCI Registry)
HELM_REPO_NAME_DEFAULT="gateway-helm"
HELM_REPO_URL_DEFAULT="oci://docker.io/envoyproxy"

# Directory Paths
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Import Shared Library
LIB_PATH="${GENESTACK_BASE_DIR}/scripts/common-functions.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: Shared library not found at $LIB_PATH" >&2
    exit 1
fi

# Pre-flight Checks
perform_preflight_checks

# Argument Parsing
parse_install_args ROTATE_SECRETS HELM_PASS_THROUGH "$@"

# Version Extraction
SERVICE_VERSION=$(get_chart_version "$SERVICE_NAME_DEFAULT")
echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# Chart Metadata Extraction
extract_chart_metadata "$SERVICE_CUSTOM_OVERRIDES" HELM_REPO_URL HELM_REPO_NAME SERVICE_NAME \
    "$HELM_REPO_URL_DEFAULT" "$HELM_REPO_NAME_DEFAULT" "$SERVICE_NAME_DEFAULT"

# Helm Repository Setup (OCI Support)
if [[ "$HELM_REPO_URL" == oci://* ]]; then
    HELM_CHART_PATH="$HELM_REPO_URL/$SERVICE_NAME"
else
    update_helm_repo "$HELM_REPO_NAME" "$HELM_REPO_URL"
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

set_args=()

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "Helm upgrade successful. Verifying Envoy Gateway deployment..."
    wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 envoy-gateway
    
    # Optional egctl installation logic
    if [ ! -f "/usr/local/bin/egctl" ]; then
        echo "Installing egctl CLI..."
        sudo mkdir -p /opt/egctl-install
        pushd /opt/egctl-install >/dev/null
            sudo wget -q "https://github.com/envoyproxy/gateway/releases/download/${SERVICE_VERSION}/egctl_${SERVICE_VERSION}_linux_amd64.tar.gz" -O egctl.tar.gz
            sudo tar -xzf egctl.tar.gz
            sudo install -m 755 bin/linux/amd64/egctl /usr/local/bin/egctl
        popd >/dev/null
        sudo rm -rf /opt/egctl-install
        echo "SUCCESS: egctl installed."
    fi
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
