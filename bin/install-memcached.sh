#!/bin/bash

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/memcached"

# Helm repository URL and name
REPO_URL="https://marketplace.azurecr.io/helm/v1/repo"
REPO_NAME="bitnami"

# Check if the Helm repository is already added
if ! helm repo list | grep -q "${REPO_NAME}"; then
    echo "Adding Helm repository: ${REPO_NAME} (${REPO_URL})"
    helm repo add "${REPO_NAME}" "${REPO_URL}" || { echo "Failed to add Helm repository"; exit 1; }
else
    echo "Helm repository ${REPO_NAME} is already added."
fi

# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update || { echo "Failed to update Helm repositories"; exit 1; }

# Base helm upgrade command using the memcached chart from the bitnami repository
HELM_CMD="helm upgrade --install memcached ${REPO_NAME}/memcached \
    --namespace=openstack \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args 'memcached/base $@' \
    -f /opt/genestack/base-helm-configs/memcached/memcached-helm-overrides.yaml"

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

