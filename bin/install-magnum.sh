#!/bin/bash
# Description: Fetches the version for Magnum and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="magnum"
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

# Overrides Collection
collect_service_overrides "$SERVICE_NAME_DEFAULT" overrides_args

# Lazy Secret Retrieval
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_KEYSTONE_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_MAGNUM_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "magnum-admin" "password" 32 "$ROTATE_SECRETS")
S_MARIADB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_MAGNUM_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "magnum-db-password" "password" 32 "$ROTATE_SECRETS")
S_RABBIT_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "rabbitmq-admin-password" "password" 32 "$ROTATE_SECRETS")
S_MAGNUM_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "magnum-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.magnum.password=$S_MAGNUM_ADMIN"
    --set "endpoints.oslo_db.auth.admin.password=$S_MARIADB_ROOT"
    --set "endpoints.oslo_db.auth.magnum.password=$S_MAGNUM_DB"
    --set "endpoints.oslo_messaging.auth.admin.password=$S_RABBIT_ADMIN"
    --set "endpoints.oslo_messaging.auth.magnum.password=$S_MAGNUM_RABBIT"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.magnum.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
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
