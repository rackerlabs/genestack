#!/bin/bash
# Description: Fetches the version for Kube-OVN and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="kube-ovn"
SERVICE_NAMESPACE="kube-system"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="kubeovn"
HELM_REPO_URL_DEFAULT="https://kubeovn.github.io/kube-ovn"

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

# Node Discovery for OVN Central
MASTER_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json | jq -r '.items[].metadata.name' | tr '\n' ',' | sed 's/,$//')
MASTER_NODE_COUNT=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l)

if [ -z "$MASTER_NODES" ]; then
    echo "Error: Could not find control-plane nodes for Kube-OVN placement." >&2
    exit 1
fi

# Version Extraction
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME_DEFAULT}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME_DEFAULT}: *//")
if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME_DEFAULT' from $VERSION_FILE" >&2
    exit 1
fi

# Helm Repository Setup
if [[ "$HELM_REPO_URL_DEFAULT" == oci://* ]]; then
    HELM_CHART_PATH="$HELM_REPO_URL_DEFAULT/$HELM_REPO_NAME_DEFAULT/$SERVICE_NAME_DEFAULT"
else
    update_helm_repo "$HELM_REPO_NAME_DEFAULT" "$HELM_REPO_URL_DEFAULT"
    HELM_CHART_PATH="$HELM_REPO_NAME_DEFAULT/$SERVICE_NAME_DEFAULT"
fi

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

set_args=(
    --set "MASTER_NODES=${MASTER_NODES}"
    --set "replicaCount=${MASTER_NODE_COUNT}"
)

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "Helm upgrade successful. Waiting for Kube-OVN components..."
    wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 kube-ovn-controller
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
