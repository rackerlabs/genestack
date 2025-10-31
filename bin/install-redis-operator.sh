#!/bin/bash
# Description: Fetches the version for SERVICE_NAME from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME="redis-replication"
SERVICE_NAMESPACE="redis-systems"

# Helm
HELM_REPO_NAME="ot-helm"
HELM_REPO_URL="https://ot-container-kit.github.io/helm-charts/"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/redis-operator-replication"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/redis-operator-replication"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"

# Read the desired chart version from VERSION_FILE
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract Redis Operator version
REDIS_OPERATOR_VERSION=$(grep 'redis-operator:' "$VERSION_FILE" | sed 's/.*redis-operator: *//')
if [ -z "$REDIS_OPERATOR_VERSION" ]; then
    echo "Error: Could not extract version for 'redis-operator' from $VERSION_FILE" >&2
    exit 1
fi
echo "Found version for redis-operator: $REDIS_OPERATOR_VERSION"

# Extract Redis Replication (main service) version
SERVICE_VERSION=$(grep 'redis-replication:' "$VERSION_FILE" | sed 's/.*redis-replication: *//')

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME: $SERVICE_VERSION"

# Helm Repository and Operator/CRD Installation
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
helm repo update

echo "Installing Redis Operator (Step 1 of 2)..."
helm upgrade --install \
    --namespace="$SERVICE_NAMESPACE" \
    --create-namespace \
    redis-operator \
    "$HELM_REPO_NAME/redis-operator" \
    --version "${REDIS_OPERATOR_VERSION}"

# Prepare an array to collect --values arguments
values_args=()

# Include all YAML files from the BASE configuration directory
# NOTE: Files in this directory are included first.
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

# Include all YAML files from the custom SERVICE configuration directory
# NOTE: Files here have the highest precedence.
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

# Collect all --set arguments, executing commands and quoting safely
set_args=()


helm_command=(
    helm upgrade --install "$SERVICE_NAME" "$HELM_REPO_NAME/$SERVICE_NAME"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${values_args[@]}"
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
