#!/bin/bash
# Description: Fetches the version for SERVICE_NAME from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME="envoyproxy-gateway"
SERVICE_NAMESPACE="envoyproxy-gateway-system"

# Helm
# NOTE: Using OCI registry format for the chart location.
HELM_REPO_NAME="oci://docker.io/envoyproxy"
HELM_REPO_URL="gateway-helm"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME}"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract version dynamically using the SERVICE_NAME variable
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME}: *//")

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for 'envoy' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME: $SERVICE_VERSION"

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

# --- Helm Repository and Execution ---
# Collect all --set arguments, executing commands and quoting safely
set_args=()


helm_command=(
    helm upgrade --install "$SERVICE_NAME" "$HELM_REPO_NAME/$HELM_REPO_URL"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

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

## Install egctl Binary (Post-Installation)

# Install egctl
if [ ! -f "/usr/local/bin/egctl" ]; then
    echo "Installing egctl CLI..."
    sudo mkdir -p /opt/egctl-install
    pushd /opt/egctl-install || exit 1
        # Use the extracted version for wget
        sudo wget "https://github.com/envoyproxy/gateway/releases/download/${SERVICE_VERSION}/egctl_${SERVICE_VERSION}_linux_amd64.tar.gz" -O egctl.tar.gz
        sudo tar -xvf egctl.tar.gz
        sudo install -o root -g root -m 0755 bin/linux/amd64/egctl /usr/local/bin/egctl
        /usr/local/bin/egctl completion bash > /tmp/egctl.bash
        sudo mv /tmp/egctl.bash /etc/bash_completion.d/egctl
    popd || exit 1
fi
