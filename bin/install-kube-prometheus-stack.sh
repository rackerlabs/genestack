#!/bin/bash
# Description: Fetches the version for SERVICE_NAME from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME="kube-prometheus-stack"
SERVICE_NAMESPACE="prometheus"

# Helm
HELM_REPO_NAME="prometheus-community"
HELM_REPO_URL="https://prometheus-community.github.io/helm-charts"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Define service-specific override directories based on the framework
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME}"

# Prometheus Rules directory (specific to this service's needs)
GENESTACK_PROMETHEUS_RULES_DIR="${SERVICE_BASE_OVERRIDES}/rules"

# Read the desired chart version from VERSION_FILE
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

# Extract version dynamically using the SERVICE_NAME variable
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME}: *//")

if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME' from $VERSION_FILE" >&2
    exit 1
fi

echo "Found version for $SERVICE_NAME: $SERVICE_VERSION"

# Prepare an array to collect -f arguments
overrides_args=()

# Include all YAML files from the BASE configuration directory and the rules subdirectory
if [[ -d "$SERVICE_BASE_OVERRIDES" ]]; then
    echo "Including base overrides from directory: $SERVICE_BASE_OVERRIDES"

    # Include YAML files directly in the base directory (e.g., specific overrides)
    for file in "$SERVICE_BASE_OVERRIDES"/*.yaml; do
        # Check that there is at least one match
        if [[ -e "$file" ]]; then
            echo " - $file (Base Config)"
            overrides_args+=("-f" "$file")
        fi
    done

    # Include YAML files from the rules subdirectory (if it exists)
    if [[ -d "$GENESTACK_PROMETHEUS_RULES_DIR" ]]; then
        echo "Including rules files from: $GENESTACK_PROMETHEUS_RULES_DIR"
        for file in "$GENESTACK_PROMETHEUS_RULES_DIR"/*.yaml; do
            if [[ -e "$file" ]]; then
                echo " - $file (Base Rules)"
                overrides_args+=("-f" "$file")
            fi
        done
    else
        echo "Info: Rules directory not found: $GENESTACK_PROMETHEUS_RULES_DIR"
    fi
else
    echo "Warning: Base override directory not found: $SERVICE_BASE_OVERRIDES"
fi

# Include all YAML files from the custom SERVICE configuration directory
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
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
helm repo update

# Collect all --set arguments (none in the original script)
set_args=()


helm_command=(
    helm upgrade --install "$SERVICE_NAME" "$HELM_REPO_NAME/$SERVICE_NAME"
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
