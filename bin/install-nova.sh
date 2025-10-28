#!/bin/bash
# Description: Fetches the version for SERVICE_NAME from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME="nova"
SERVICE_NAMESPACE="openstack"

# Helm
HELM_REPO_NAME="openstack-helm"
HELM_REPO_URL="https://tarballs.opendev.org/openstack/openstack-helm"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME}"
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract version dynamically using the SERVICE_NAME variable
SERVICE_VERSION=$(grep "${SERVICE_NAME}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME}: *//")

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME: $SERVICE_VERSION"

# Prepare an array to collect --values arguments
values_args=()

#  Include all YAML files from the BASE configuration directory
if [[ -d "$SERVICE_BASE_OVERRIDES" ]]; then
  echo "Including base overrides from directory: $SERVICE_BASE_OVERRIDES"
  for file in "$SERVICE_BASE_OVERRIDES"/*.yaml; do
    # Check that there is at least one match
    if [[ -e "$file" ]]; then
      echo " - $file"
      values_args+=("--values" "$file")
    fi
  done
else
  echo "Warning: Base override directory not found: $SERVICE_BASE_OVERRIDES"
fi

# Include all YAML files from the GLOBAL configuration directory
if [[ -d "$GLOBAL_OVERRIDES_DIR" ]]; then
  echo "Including overrides from global config directory:"
  for file in "$GLOBAL_OVERRIDES_DIR"/*.yaml; do
    if [[ -e "$file" ]]; then
      echo " - $file"
      values_args+=("--values" "$file")
    fi
  done
else
  echo "Warning: Global config directory not found: $GLOBAL_OVERRIDES_DIR"
fi

# Include all YAML files from the custom SERVICE configuration directory
if [[ -d "$SERVICE_CUSTOM_OVERRIDES" ]]; then
  echo "Including overrides from service config directory:"
  for file in "$SERVICE_CUSTOM_OVERRIDES"/*.yaml; do
    if [[ -e "$file" ]]; then
      echo " - $file"
      values_args+=("--values" "$file")
    fi
  done
else
  echo "Warning: Service config directory not found: $SERVICE_CUSTOM_OVERRIDES"
fi

echo

# --- Helm Repository and Execution ---
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
helm repo update

helm_command=(
    helm upgrade --install "$SERVICE_NAME" "$HELM_REPO_NAME/$SERVICE_NAME"
    --version "${SERVICE_VERSION}"
    --namespace=openstack
    --timeout 120m
    
    "${values_args[@]}" 

    --set "conf.nova.neutron.metadata_proxy_shared_secret=$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.admin.password=$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.nova.password=$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.neutron.password=$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.ironic.password=$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.placement.password=$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.cinder.password=$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.admin.password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.nova.password=$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_db_api.auth.admin.password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
    --set "endpoints.oslo_db_api.auth.nova.password=$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_db_cell0.auth.admin.password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
    --set "endpoints.oslo_db_cell0.auth.nova.password=$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
    --set "conf.nova.keystone_authtoken.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
    --set "endpoints.oslo_messaging.auth.admin.password=$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_messaging.auth.nova.password=$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
    
    --set "network.ssh.public_key=$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.public_key}' | base64 -d)"
    --set "network.ssh.private_key=$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.private_key}' | base64 -d)"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"
