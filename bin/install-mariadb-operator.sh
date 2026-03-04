#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="mariadb-operator"
CRDS_NAME_DEFAULT="mariadb-operator-crds"
SERVICE_NAMESPACE="mariadb-system"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="mariadb-operator"
HELM_REPO_URL_DEFAULT="https://helm.mariadb.com/mariadb-operator"

# Directory Paths
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

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
ROTATE_SECRETS=false
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rotate-secrets) ROTATE_SECRETS=true; shift ;;
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

# Version Extraction
SERVICE_VERSION=$(get_chart_version "$SERVICE_NAME_DEFAULT")
echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# MariaDB Specific: Cluster Name Logic
export CLUSTER_NAME=${CLUSTER_NAME:-cluster.local}
if [ "${CLUSTER_NAME}" != "cluster.local" ]; then
    SERVICE_CONFIG_FILE="$SERVICE_CUSTOM_OVERRIDES/mariadb-operator-helm-overrides.yaml"
    mkdir -p "$SERVICE_CUSTOM_OVERRIDES"
    touch "$SERVICE_CONFIG_FILE"
    if [ ! -s "$SERVICE_CONFIG_FILE" ]; then
        echo "clusterName: $CLUSTER_NAME" > "$SERVICE_CONFIG_FILE"
    else
        if grep -q "^clusterName:" "$SERVICE_CONFIG_FILE"; then
            sed -i -e "s/^clusterName: .*/clusterName: ${CLUSTER_NAME}/" "$SERVICE_CONFIG_FILE"
        else
            echo "clusterName: $CLUSTER_NAME" >> "$SERVICE_CONFIG_FILE"
        fi
    fi
fi

# Chart Metadata Extraction
extract_chart_metadata "$SERVICE_CUSTOM_OVERRIDES" HELM_REPO_URL HELM_REPO_NAME SERVICE_NAME \
    "$HELM_REPO_URL_DEFAULT" "$HELM_REPO_NAME_DEFAULT" "$SERVICE_NAME_DEFAULT"
: "${CRDS_NAME:=$CRDS_NAME_DEFAULT}"

# Helm Repository Setup
HELM_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$SERVICE_NAME")
CRDS_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$CRDS_NAME")

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

# Install CRDs First
echo "Installing MariaDB Operator CRDs..."
helm upgrade --install "$CRDS_NAME_DEFAULT" "$CRDS_CHART_PATH" \
    --namespace="$SERVICE_NAMESPACE" \
    --create-namespace \
    --version "${SERVICE_VERSION}" \
    --wait

# Main Operator Installation
set_args=()
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "Helm upgrade successful. Waiting for MariaDB Operator..."
    wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 "$SERVICE_NAME_DEFAULT"
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    exit 1
fi
