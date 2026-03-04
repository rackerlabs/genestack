#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="ceilometer"
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
S_CEILO_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "ceilometer-keystone-admin-password" "password" 32 "$ROTATE_SECRETS")
S_CEILO_TEST=$(get_or_create_secret "$SERVICE_NAMESPACE" "ceilometer-keystone-test-password" "password" 32 "$ROTATE_SECRETS")
S_MEMCACHE=$(get_or_create_secret "$SERVICE_NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")
S_RABBIT_ADMIN=$(get_or_create_secret "$SERVICE_NAMESPACE" "rabbitmq-admin-password" "password" 32 "$ROTATE_SECRETS")

# Transport Passwords for Notification Bus
S_CEILO_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "ceilometer-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_KEYSTONE_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "keystone-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_GLANCE_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "glance-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_NOVA_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "nova-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_NEUTRON_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "neutron-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_CINDER_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "cinder-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_HEAT_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "heat-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_OCTAVIA_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "octavia-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")
S_MAGNUM_RABBIT=$(get_or_create_secret "$SERVICE_NAMESPACE" "magnum-rabbitmq-password" "password" 64 "$ROTATE_SECRETS")

set_args=(
    --set "endpoints.identity.auth.admin.password=$S_KEYSTONE_ADMIN"
    --set "endpoints.identity.auth.ceilometer.password=$S_CEILO_ADMIN"
    --set "endpoints.identity.auth.test.password=$S_CEILO_TEST"
    --set "endpoints.oslo_messaging.auth.admin.password=$S_RABBIT_ADMIN"
    --set "endpoints.oslo_messaging.auth.ceilometer.password=$S_CEILO_RABBIT"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$S_MEMCACHE"
    --set "conf.ceilometer.keystone_authtoken.memcache_secret_key=$S_MEMCACHE"
    --set "conf.ceilometer.oslo_messaging.transport_url=rabbit://ceilometer:$S_CEILO_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/ceilometer"
    --set "conf.ceilometer.notification.messaging_urls.values={\
rabbit://ceilometer:$S_CEILO_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/ceilometer,\
rabbit://keystone:$S_KEYSTONE_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/keystone,\
rabbit://glance:$S_GLANCE_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/glance,\
rabbit://nova:$S_NOVA_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/nova,\
rabbit://neutron:$S_NEUTRON_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/neutron,\
rabbit://cinder:$S_CINDER_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/cinder,\
rabbit://heat:$S_HEAT_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/heat,\
rabbit://octavia:$S_OCTAVIA_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/octavia,\
rabbit://magnum:$S_MAGNUM_RABBIT@rabbitmq.openstack.svc.cluster.local:5672/magnum}"
)

# Command Execution
# Command Execution

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "Helm upgrade successful. Waiting for Ceilometer deployments..."
    kubectl -n "$SERVICE_NAMESPACE" wait --for=condition=available --timeout=300s \
        deployment/ceilometer-agent-notification \
        deployment/ceilometer-agent-central
    echo "SUCCESS: $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
