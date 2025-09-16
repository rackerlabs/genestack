#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

CONFIG_DIR="/etc/genestack/helm-configs/redis-sentinel"

# Read redis-operator version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract redis-sentinel version using grep and sed
REDIS_SENTINEL_VERSION=$(grep 'redis-sentinel:' "$VERSION_FILE" | sed 's/.*redis-sentinel: *//')

if [ -z "$REDIS_SENTINEL_VERSION" ]; then
    echo "Error: Could not extract redis-sentinel version from $VERSION_FILE"
    exit 1
fi

# Add the redis-operator helm repository
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update

# Helm command setup for Redis Sentinel
HELM_CMD="helm upgrade --install redis-sentinel ot-helm/redis-sentinel --version ${REDIS_SENTINEL_VERSION} \
    --namespace=redis-systems \
    --timeout 120m \
    -f /opt/genestack/base-helm-configs/redis-sentinel/redis-sentinel-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Add all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

HELM_CMD+=" $@"

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
