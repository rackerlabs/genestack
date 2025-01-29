#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/memcached"

# Helm command setup
HELM_CMD="helm upgrade --install memcached oci://registry-1.docker.io/bitnamicharts/memcached \
    --namespace=openstack \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args memcached/overlay \
    -f /opt/genestack/base-helm-configs/memcached/memcached-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Add all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+=" ${@}"

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
