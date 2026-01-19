#!/bin/bash
# Description: Fetches the version for Manila and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="manila"
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
check_dependencies "kubectl" "helm" "yq" "base64" "sed" "grep" "ssh-keygen"
check_cluster_connection

# Argument Parsing
ROTATE_SECRETS=false
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rotate-secret) ROTATE_SECRETS=true; shift ;;
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

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
overrides_args=()
process_overrides "$SERVICE_BASE_OVERRIDES" overrides_args "base overrides"
process_overrides "$GLOBAL_OVERRIDES_DIR" overrides_args "global overrides"
process_overrides "$SERVICE_CUSTOM_OVERRIDES" overrides_args "service config overrides"

# Lazy Secret Retrieval
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_KEYSTONE_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-admin" "password" 32 "$ROTATE_SECRETS")
S_MANILA_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "manila-admin" "password" 32 "$ROTATE_SECRETS")
S_MARIADB_ROOT=$(get_or_create_secret "$SERVICE_NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
S_MANILA_DB=$(get_or_create_secret "$SERVICE_NAMESPACE" "manila-db-password" "password" 32 "$ROTATE_SECRETS")
S_RABBIT_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "rabbitmq-admin-password" "password" 32 "$ROTATE_SECRETS")
S_MANILA_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "manila-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")

# SSH Key Management for Manila
SECRET_SSH="manila-ssh-key"
if ! kubectl -n "$SERVICE_NAMESPACE" get secret "$SECRET_SSH" >/dev/null 2>&1 || [ "$ROTATE_SECRETS" = true ]; then
    echo "Generating new SSH key pair for Manila..."
    tmpdir=$(mktemp -d)
    ssh-keygen -t rsa -b 4096 -f "${tmpdir}/id_rsa" -N "" -q
    kubectl -n "$SERVICE_NAMESPACE" create secret generic "$SECRET_SSH" \
        --from-file=public_key="${tmpdir}/id_rsa.pub" \
        --from-file=private_key="${tmpdir}/id_rsa" \
        --dry-run=client -o yaml | kubectl apply -f -
    rm -rf "$tmpdir"
fi
S_SSH_PUB=$(kubectl -n "$SERVICE_NAMESPACE" get secret "$SECRET_SSH" -o jsonpath='{.data.public_key}' | base64 -d)
S_SSH_PRIV=$(kubectl -n "$SERVICE_NAMESPACE" get secret "$SECRET_SSH" -o jsonpath='{.data.private_key}' | base64 -d)

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.manila.password=$S_MANILA_ADMIN"
    --set "endpoints.oslo_db.auth.admin.password=$S_MARIADB_ROOT"
    --set "endpoints.oslo_db.auth.manila.password=$S_MANILA_DB"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.manila.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
    --set "endpoints.oslo_messaging.auth.admin.password=$S_RABBIT_ADMIN"
    --set "endpoints.oslo_messaging.auth.manila.password=$S_MANILA_RABBIT"
    --set "network.ssh.public_key=$(echo "$S_SSH_PUB" | base64 | tr -d '\n')"
    --set "network.ssh.private_key=$(echo "$S_SSH_PRIV" | base64 | tr -d '\n')"
)

# Command Execution
HELM_CHART_PATH="${HELM_REPO_NAME_DEFAULT}/${SERVICE_NAME_DEFAULT}"
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
    echo "✓ $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
