#!/bin/bash
# Description: Fetches the version for Zaqar and executes helm upgrade with dynamic secrets.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="zaqar"
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
S_KEYSTONE_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_ZAQAR_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "zaqar-admin" "password" 32 "$ROTATE_SECRETS")
S_ZAQAR_TEST=$(get_or_create_secret "$SERVICE_NAMESPACE" "zaqar-keystone-test-password" "password" 32 "$ROTATE_SECRETS")
S_DB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_ZAQAR_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "zaqar-db-password" "password" 32 "$ROTATE_SECRETS")
S_RABBIT_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "rabbitmq-admin-password" "password" 32 "$ROTATE_SECRETS")
S_ZAQAR_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "zaqar-rabbitmq-password" "password" 32 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")
S_ZAQAR_SIGNED_URL=$(get_or_create_secret "$SERVICE_NAMESPACE" "zaqar-signed-url-secret-key" "zaqar_signed_url_secret_key" 64 "$ROTATE_SECRETS")

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.zaqar.password=$S_ZAQAR_ADMIN"
    --set "endpoints.identity.auth.test.password=$S_ZAQAR_TEST"
    --set "endpoints.oslo_db.auth.admin.password=$S_DB_ROOT"
    --set "endpoints.oslo_db.auth.zaqar.password=$S_ZAQAR_DB"
    --set "endpoints.oslo_messaging.auth.admin.password=$S_RABBIT_ADMIN"
    --set "endpoints.oslo_messaging.auth.zaqar.password=$S_ZAQAR_RABBIT"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.zaqar.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
    --set "conf.zaqar.signed_url.secret_key=$S_ZAQAR_SIGNED_URL"
)

# Command Execution
build_helm_command "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH" "$SERVICE_VERSION" \
    "$SERVICE_NAMESPACE" set_args overrides_args helm_command

if execute_helm_upgrade helm_command HELM_PASS_THROUGH; then
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
