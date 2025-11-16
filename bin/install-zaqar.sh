#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
# The service name is used for both the release name and the chart name.
SERVICE_NAME_DEFAULT="zaqar"
SERVICE_NAMESPACE="openstack"

# Helm
HELM_REPO_NAME_DEFAULT="openstack-helm"
HELM_REPO_URL_DEFAULT="https://tarballs.opendev.org/openstack/openstack-helm"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

# Define the Global Overrides directory used in the original script
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract version dynamically using the SERVICE_NAME_DEFAULT variable
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME_DEFAULT}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME_DEFAULT}: *//")

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME_DEFAULT' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# Load chart metadata from custom override YAML if defined
for yaml_file in "${SERVICE_CUSTOM_OVERRIDES}"/*.yaml; do
    if [ -f "$yaml_file" ]; then
        HELM_REPO_URL=$(yq eval '.chart.repo_url // ""' "$yaml_file")
        HELM_REPO_NAME=$(yq eval '.chart.repo_name // ""' "$yaml_file")
        SERVICE_NAME=$(yq eval '.chart.service_name // ""' "$yaml_file")
        break  # use the first match and stop
    fi
done

# Fallback to defaults if variables not set
: "${HELM_REPO_URL:=$HELM_REPO_URL_DEFAULT}"
: "${HELM_REPO_NAME:=$HELM_REPO_NAME_DEFAULT}"
: "${SERVICE_NAME:=$SERVICE_NAME_DEFAULT}"


# Determine Helm chart path
if [[ "$HELM_REPO_URL" == oci://* ]]; then
    # OCI registry path
    HELM_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$SERVICE_NAME"
else
    # --- Helm Repository and Execution ---
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"   # uncomment if needed
    helm repo update
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi


# Debug output
echo "[DEBUG] HELM_REPO_URL=$HELM_REPO_URL"
echo "[DEBUG] HELM_REPO_NAME=$HELM_REPO_NAME"
echo "[DEBUG] SERVICE_NAME=$SERVICE_NAME"
echo "[DEBUG] HELM_CHART_PATH=$HELM_CHART_PATH"

# Prepare an array to collect -f arguments
overrides_args=()

# Include all YAML files from the BASE configuration directory
# NOTE: Files in this directory are included first.
if [[ -d "$SERVICE_BASE_OVERRIDES" ]]; then
    echo "Including base overrides from directory: $SERVICE_BASE_OVERRIDES"
    for file in "$SERVICE_BASE_OVERRIDES"/*.yaml; do
        # Check that there is at least one match
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Base override directory not found: $SERVICE_BASE_OVERRIDES"
fi

# Include all YAML files from the GLOBAL configuration directory
# NOTE: Files here override base settings and are applied before service-specific ones.
if [[ -d "$GLOBAL_OVERRIDES_DIR" ]]; then
    echo "Including global overrides from directory: $GLOBAL_OVERRIDES_DIR"
    for file in "$GLOBAL_OVERRIDES_DIR"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Global override directory not found: $GLOBAL_OVERRIDES_DIR"
fi

# Include all YAML files from the custom SERVICE configuration directory
# NOTE: Files here have the highest precedence.
if [[ -d "$SERVICE_CUSTOM_OVERRIDES" ]]; then
    echo "Including overrides from service config directory:"
    for file in "$SERVICE_CUSTOM_OVERRIDES"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Service config directory not found: $SERVICE_CUSTOM_OVERRIDES"
fi

echo

# Collect all --set arguments, executing commands and quoting safely
set_args=(
    --set "endpoints.identity.auth.admin.password=$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.zaqar.password=$(kubectl --namespace openstack get secret zaqar-admin -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.identity.auth.test.password=$(kubectl --namespace openstack get secret zaqar-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.admin.password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
    --set "endpoints.oslo_db.auth.zaqar.password=$(kubectl --namespace openstack get secret zaqar-db-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_messaging.auth.admin.password=$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_messaging.auth.zaqar.password=$(kubectl --namespace openstack get secret zaqar-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
    --set "endpoints.oslo_cache.auth.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
    --set "conf.zaqar.keystone_authtoken.memcache_secret_key=$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)"
    --set "conf.zaqar.signed_url.secret_key=$(kubectl --namespace openstack get secret zaqar-signed-url-secret-key -o jsonpath='{.data.zaqar_signed_url_secret_key}' | base64 -d)"
)


helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"