#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/grafana"

# Base helm command setup
HELM_CMD="helm upgrade --install grafana grafana/grafana \
  --namespace=grafana \
  --create-namespace \
  --timeout 120m \
  --post-renderer /etc/genestack/kustomize/kustomize.sh \
  --post-renderer-args grafana/overlay"

# Add the base overrides file
HELM_CMD+=" -f /opt/genestack/base-helm-configs/grafana/grafana-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Append all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+="${@}"

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"