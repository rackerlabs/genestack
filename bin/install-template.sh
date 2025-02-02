#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

# Directory to check for YAML files
ALL_DIR="/etc/genestack/helm-configs/all"
CONFIG_DIR="/etc/genestack/helm-configs/libvirt"

pushd /opt/genestack/submodules/openstack-helm || exit

# Base helm upgrade command
HELM_CMD="helm upgrade --install libvirt ./libvirt \
    --namespace=openstack \
    --timeout 120m"

# Add the base overrides file
HELM_CMD+=" -f /opt/genestack/base-helm-configs/libvirt/libvirt-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${ALL_DIR}/*.yaml" > /dev/null; then
    # Append all YAML files from the directory to the helm command
    for yaml_file in "${ALL_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Append all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+=" $*"

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"

popd || exit
