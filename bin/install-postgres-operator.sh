#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/postgres-operator"

# Read postgres-operator version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract postgres-operator version using grep and sed
POSTGRES_OPERATOR_VERSION=$(grep 'postgres-operator:' "$VERSION_FILE" | sed 's/.*postgres-operator: *//')

if [ -z "$POSTGRES_OPERATOR_VERSION" ]; then
    echo "Error: Could not extract postgres-operator version from $VERSION_FILE"
    exit 1
fi

# Base helm command setup
HELM_CMD="helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --version ${POSTGRES_OPERATOR_VERSION} \
  --namespace=postgres-system \
  --create-namespace \
  --timeout 120m"

# Add the base overrides file
HELM_CMD+=" -f /opt/genestack/base-helm-configs/postgres-operator/postgres-operator-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Append all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+=" $@"

helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
