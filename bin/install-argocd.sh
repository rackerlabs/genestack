#!/bin/bash

# Default parameter value
TARGET=${1:-base}

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/argocd"

# Read argocd version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract argocd version using grep and sed
ARGOCD_VERSION=$(grep 'argocd:' "$VERSION_FILE" | sed 's/.*argocd: *//')

if [ -z "$ARGOCD_VERSION" ]; then
    echo "Error: Could not extract argocd version from $VERSION_FILE"
    exit 1
fi

# Helm command setup
HELM_CMD="helm upgrade --install argocd bitnami/argo-cd \
    --version ${ARGOCD_VERSION} \
    --namespace=argocd \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args argocd/${TARGET} \
    -f /opt/genestack/base-helm-configs/argocd/helm-argocd-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Add all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
