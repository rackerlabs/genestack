#!/bin/bash

# Default parameter value
TARGET=${1:-base}

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/sealed-secrets"

# Read sealed-secrets version from helm-chart-versions.yaml
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract sealed-secrets version using grep and sed
SEALED_SECRETS_VERSION=$(grep 'sealed-secrets:' "$VERSION_FILE" | sed 's/.*sealed-secrets: *//')

if [ -z "$SEALED_SECRETS_VERSION" ]; then
    echo "Error: Could not extract sealed-secrets version from $VERSION_FILE"
    exit 1
fi

# Helm command setup
HELM_CMD="helm upgrade --install sealed-secrets bitnami/sealed-secrets \
    --version ${SEALED_SECRETS_VERSION} \
    --namespace=sealed-secrets \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args sealed-secrets/${TARGET} \
    -f /opt/genestack/base-helm-configs/sealed-secrets/helm-sealed-secrets-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Add all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+=" $@"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
