#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="postgres-operator"
SERVICE_NAMESPACE="postgres-system"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="postgres-operator-charts"
HELM_REPO_URL_DEFAULT="https://opensource.zalando.com/postgres-operator/charts/postgres-operator"

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
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

# Version Extraction
SERVICE_VERSION=$(get_chart_version "$SERVICE_NAME_DEFAULT")
echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# Chart Metadata Extraction
extract_chart_metadata "$SERVICE_CUSTOM_OVERRIDES" HELM_REPO_URL HELM_REPO_NAME SERVICE_NAME \
    "$HELM_REPO_URL_DEFAULT" "$HELM_REPO_NAME_DEFAULT" "$SERVICE_NAME_DEFAULT"

# Helm Repository Setup
HELM_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$SERVICE_NAME")

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "Helm upgrade successful. Waiting for Postgres Operator..."
    wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 "$SERVICE_NAME_DEFAULT"
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
