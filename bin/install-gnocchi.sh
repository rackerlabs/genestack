#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="gnocchi"
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
# Storage & Cache
S_CEPH_ADMIN=$(get_or_create_secret "rook-ceph" "rook-ceph-admin-keyring" "keyring" 128 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")

# Identity
S_KEYSTONE_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_GNOCCHI_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "gnocchi-admin" "password" 32 "$ROTATE_SECRETS")

# Databases (MariaDB & PostgreSQL)
S_MARIADB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_GNOCCHI_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "gnocchi-db-password" "password" 32 "$ROTATE_SECRETS")
S_PG_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "postgres.postgres-cluster.credentials.postgresql.acid.zalan.do" "password" 32 "$ROTATE_SECRETS")
S_GNOCCHI_PG=$(get_or_create_secret "$SERVICE_NAMESPACE" "gnocchi-pgsql-password" "password" 32 "$ROTATE_SECRETS")

set_args=(
    --set "conf.ceph.admin_keyring=$S_CEPH_ADMIN"
    --set "conf.gnocchi.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.gnocchi.password=$S_GNOCCHI_ADMIN"
    --set "endpoints.oslo_db.auth.admin.password=$S_MARIADB_ROOT"
    --set "endpoints.oslo_db.auth.gnocchi.password=$S_GNOCCHI_DB"
    --set "endpoints.oslo_db_postgresql.auth.admin.password=$S_PG_ADMIN"
    --set "endpoints.oslo_db_postgresql.auth.gnocchi.password=$S_GNOCCHI_PG"
)

# Command Execution
# Command Execution

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "Helm upgrade successful. Waiting for Gnocchi deployments..."
    kubectl -n "$SERVICE_NAMESPACE" wait --for=condition=available --timeout=300s \
        deployment/gnocchi-api \
        deployment/gnocchi-metricd \
        deployment/gnocchi-statsd
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
