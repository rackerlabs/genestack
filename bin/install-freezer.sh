#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="freezer"
SERVICE_NAMESPACE="openstack"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="openstack-helm"
HELM_REPO_URL_DEFAULT="https://tarballs.opendev.org/openstack/openstack-helm"

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

# Helm Repository Setup
HELM_CHART_PATH=$(setup_helm_chart_path "$HELM_REPO_URL" "$HELM_REPO_NAME" "$SERVICE_NAME")

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

# Lazy Secret Retrieval
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_KEYSTONE=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_FREEZER=$(get_or_create_secret "$SERVICE_NAMESPACE" "freezer-admin" "password" 32 "$ROTATE_SECRETS")
S_FREEZER_TEST=$(get_or_create_secret "$SERVICE_NAMESPACE" "freezer-keystone-test-password" "password" 32 "$ROTATE_SECRETS")
S_FREEZER_SVC=$(get_or_create_secret "$SERVICE_NAMESPACE" "freezer-keystone-service-password" "password" 32 "$ROTATE_SECRETS")
S_DB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_FREEZER_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "freezer-db-password" "password" 32 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE"
    --set "endpoints.identity.auth.freezer.password=$S_FREEZER"
    --set "endpoints.identity.auth.test.password=$S_FREEZER_TEST"
    --set "endpoints.identity.auth.service.password=$S_FREEZER_SVC"
    --set "endpoints.oslo_db.auth.admin.password=$S_DB_ROOT"
    --set "endpoints.oslo_db.auth.freezer.password=$S_FREEZER_DB"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.freezer.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
)

# Command Execution
# Command Execution

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "Helm upgrade successful. Waiting for Freezer deployments..."
    kubectl -n "$SERVICE_NAMESPACE" wait --for=condition=available --timeout=300s \
        deployment/freezer-api \
        deployment/freezer-scheduler
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
