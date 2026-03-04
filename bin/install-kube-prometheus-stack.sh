#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="kube-prometheus-stack"
SERVICE_NAMESPACE="prometheus"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="prometheus-community"
HELM_REPO_URL_DEFAULT="https://prometheus-community.github.io/helm-charts"

# Directory Paths
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Prometheus Rules directory (specific to this service)
GENESTACK_PROMETHEUS_RULES_DIR="${SERVICE_BASE_OVERRIDES}/rules"

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

# Helm Repository Setup
HELM_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$SERVICE_NAME")

# Overrides Collection
# Overrides Collection
# Custom logic for Prometheus Rules directory
if [[ -d "$GENESTACK_PROMETHEUS_RULES_DIR" ]]; then
    echo "Including rules files from: $GENESTACK_PROMETHEUS_RULES_DIR"
    for file in "$GENESTACK_PROMETHEUS_RULES_DIR"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file (Base Rules)"
            overrides_args+=("-f" "$file")
        fi
    done
fi

process_overrides "$GLOBAL_OVERRIDES_DIR" overrides_args "global overrides"
process_overrides "$SERVICE_CUSTOM_OVERRIDES" overrides_args "service config overrides"

# Lazy Secret Retrieval
# Managing Grafana admin password if Grafana is enabled within the stack
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_GRAFANA_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "grafana-admin-credentials" "admin-password" 32 "$ROTATE_SECRETS")

set_args=(
    --set "grafana.adminPassword=$S_GRAFANA_ADMIN"
)

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "Helm upgrade successful. Waiting for Prometheus Operator..."
    wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 "${SERVICE_NAME_DEFAULT}-operator"
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
