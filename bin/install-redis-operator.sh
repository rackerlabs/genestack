#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

CONFIG_DIR="/etc/genestack/helm-configs/redis-operator-replication"

# Read redis-operator version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract redis-operator version using grep and sed
REDIS_OPERATOR_VERSION=$(grep 'redis-operator:' "$VERSION_FILE" | sed 's/.*redis-operator: *//')

if [ -z "$REDIS_OPERATOR_VERSION" ]; then
    echo "Error: Could not extract redis-operator version from $VERSION_FILE"
    exit 1
fi

# Extract redis-replication version using grep and sed
REDIS_REPLICATION_VERSION=$(grep 'redis-replication:' "$VERSION_FILE" | sed 's/.*redis-replication: *//')

if [ -z "$REDIS_REPLICATION_VERSION" ]; then
    echo "Error: Could not extract redis-replication version from $VERSION_FILE"
    exit 1
fi

# Add the redis-operator helm repository
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update

# Install the Operator and CRDs that match the version defined
helm upgrade --install --namespace=redis-systems --create-namespace redis-operator ot-helm/redis-operator --version "${REDIS_OPERATOR_VERSION}"

# Helm command setup for Redis replication cluster
HELM_CMD="helm upgrade --install redis-replication ot-helm/redis-replication --version ${REDIS_REPLICATION_VERSION} \
    --namespace=redis-systems \
    --timeout 120m \
    -f /opt/genestack/base-helm-configs/redis-operator-replication/redis-replication-helm-overrides.yaml"

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
