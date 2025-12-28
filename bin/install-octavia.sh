#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="octavia"
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
check_dependencies "kubectl" "helm" "yq" "base64" "sed" "grep"
check_cluster_connection

# Argument Parsing
ROTATE_SECRETS=false
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rotate-secrets) ROTATE_SECRETS=true; shift ;;
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

# Version Management
SERVICE_VERSION=$(get_chart_version "$SERVICE_NAME_DEFAULT")

# Helm Repository Setup
HELM_REPO_URL="${HELM_REPO_URL:-$HELM_REPO_URL_DEFAULT}"
HELM_REPO_NAME="${HELM_REPO_NAME:-$HELM_REPO_NAME_DEFAULT}"
SERVICE_NAME="${SERVICE_NAME:-$SERVICE_NAME_DEFAULT}"

if [[ "$HELM_REPO_URL" == oci://* ]]; then
    HELM_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$SERVICE_NAME"
else
    update_helm_repo "$HELM_REPO_NAME" "$HELM_REPO_URL"
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi

# Overrides Collection
overrides_args=()
process_overrides "$SERVICE_BASE_OVERRIDES" overrides_args "base overrides"
process_overrides "$GLOBAL_OVERRIDES_DIR" overrides_args "global overrides"
process_overrides "$SERVICE_CUSTOM_OVERRIDES" overrides_args "service config overrides"

# OVN Endpoints retrieval
OVN_NB_EP=$(kubectl -n openstack get svc ovn-nb -o jsonpath='{.spec.clusterIP}')
OVN_SB_EP=$(kubectl -n openstack get svc ovn-sb -o jsonpath='{.spec.clusterIP}')

# Lazy Secret Retrieval
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_KEYSTONE_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_OCTAVIA_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "octavia-admin-password" "password" 32 "$ROTATE_SECRETS")
S_DB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_OCTAVIA_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "octavia-db-password" "password" 32 "$ROTATE_SECRETS")
S_RABBIT_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "rabbitmq-admin-password" "password" 64 "$ROTATE_SECRETS")
S_OCTAVIA_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "octavia-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")
S_CERT_PASS=$(get_or_create_secret "$SERVICE_NAMESPACE" "octavia-ca-password" "password" 32 "$ROTATE_SECRETS")

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.octavia.password=$S_OCTAVIA_ADMIN"
    --set "endpoints.oslo_db.auth.admin.password=$S_DB_ROOT"
    --set "endpoints.oslo_db.auth.octavia.password=$S_OCTAVIA_DB"
    --set "endpoints.oslo_db_persistence.auth.octavia.password=$S_OCTAVIA_DB"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.octavia.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
    --set "endpoints.oslo_messaging.auth.admin.password=$S_RABBIT_ADMIN"
    --set "endpoints.oslo_messaging.auth.octavia.password=$S_OCTAVIA_RABBIT"
    --set "conf.octavia.certificates.ca_private_key_passphrase=$S_CERT_PASS"
    --set "conf.octavia.ovn.ovn_nb_connection=$OVN_NB_EP"
    --set "conf.octavia.ovn.ovn_sb_connection=$OVN_SB_EP"
)

# Command Execution
helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout "${HELM_TIMEOUT:-$HELM_TIMEOUT_DEFAULT}"
    --create-namespace
    --atomic
    --cleanup-on-fail
    "${overrides_args[@]}"
    "${set_args[@]}"
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"
)

echo "Executing Helm command:"
printf '%q ' "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"
echo

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "Helm upgrade successful. Waiting for Octavia deployments..."
    kubectl -n "$SERVICE_NAMESPACE" wait --for=condition=available --timeout=300s \
        deployment/octavia-api \
        deployment/octavia-worker \
        deployment/octavia-health-manager \
        deployment/octavia-housekeeping
else
    echo "Error: Helm upgrade failed for $SERVICE_NAME_DEFAULT" >&2
    exit 1
fi
