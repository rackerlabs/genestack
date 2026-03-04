#!/bin/bash
# Description: Installs Redis Operator followed by the Redis Replication configuration.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="redis-replication"
OPERATOR_NAME_DEFAULT="redis-operator"
SERVICE_NAMESPACE="redis-systems"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="ot-helm"
HELM_REPO_URL_DEFAULT="https://ot-container-kit.github.io/helm-charts"

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
REDIS_OPERATOR_VERSION=$(get_chart_version "redis-operator")
SERVICE_VERSION=$(get_chart_version "redis-replication")

echo "Found version for redis-operator: $REDIS_OPERATOR_VERSION"
echo "Found version for redis-replication: $SERVICE_VERSION"

# Chart Metadata Extraction
extract_chart_metadata "$SERVICE_CUSTOM_OVERRIDES" HELM_REPO_URL HELM_REPO_NAME SERVICE_NAME \
    "$HELM_REPO_URL_DEFAULT" "$HELM_REPO_NAME_DEFAULT" "$SERVICE_NAME_DEFAULT"

# Helm Repository Setup
OPERATOR_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "redis-operator")
REPLICATION_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$SERVICE_NAME")

# --- Step 1: Install Redis Operator ---
echo "Installing Redis Operator..."
helm upgrade --install "$OPERATOR_NAME_DEFAULT" "$OPERATOR_CHART_PATH" \
    --namespace "$SERVICE_NAMESPACE" \
    --version "${REDIS_OPERATOR_VERSION}" \
    --create-namespace \
    --wait

wait_for_resource_ready "$SERVICE_NAMESPACE" deployment 300 "$OPERATOR_NAME_DEFAULT"

# --- Step 2: Install Redis Replication ---
echo "Installing Redis Replication configuration..."

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

# Secret Handling (e.g., for Redis AUTH)
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_REDIS_PASSWORD=$(get_or_create_secret "$SERVICE_NAMESPACE" "redis-password" "password" 32 "$ROTATE_SECRETS")

set_args=(
    --set "redisPassword=$S_REDIS_PASSWORD"
)

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$REPLICATION_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "SUCCESS: $SERVICE_NAME_DEFAULT (and Operator) is ready."
else
    exit 1
fi
