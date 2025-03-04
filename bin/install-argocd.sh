#!/bin/bash

# Default parameter value
TARGET=${1:-base}

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/argocd"

# Helm command setup
HELM_CMD="helm upgrade --install argocd oci://registry-1.docker.io/bitnamicharts/argo-cd \
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

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
