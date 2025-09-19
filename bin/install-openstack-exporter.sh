#!/bin/bash
set -e  # Exit on error

# Variables
CHART_DIR="/opt/genestack/base-helm-configs/openstack-api-exporter-chart"
NAMESPACE="prometheus"
RELEASE_NAME="openstack-exporter"

# Check if chart directory exists
if [ ! -d "${CHART_DIR}" ]; then
    echo "Chart directory ${CHART_DIR} does not exist!"
    exit 1
fi

# Function to find an unused port
find_unused_port() {
    local port=49152
    while :; do
        if ! kubectl get svc --all-namespaces -o jsonpath='{range .items[*]}{.spec.ports[*].port}{"\n"}{end}' | grep -q "^${port}$"; then
            echo "$port"
            return 0
        fi
        ((port++))
        if [ $port -gt 65535 ]; then
            echo "No unused port found in range 49152-65535" >&2
            exit 1
        fi
    done
}

# Ensure namespace exists
if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    echo "Namespace ${NAMESPACE} does not exist. Creating..."
    kubectl create namespace ${NAMESPACE}
fi

# Check if release already exists
if helm list -n ${NAMESPACE} | grep -q ${RELEASE_NAME}; then
    echo "Release ${RELEASE_NAME} already exists!"
    exit 1
fi

# Find and set dynamic values
DYNAMIC_PORT=$(find_unused_port)
DYNAMIC_TAG="sha-7951e2c"
echo "Using dynamic port: $DYNAMIC_PORT and tag: $DYNAMIC_TAG"

# Install Helm chart with dynamic values
echo "Installing Helm chart..."
helm install ${RELEASE_NAME} ${CHART_DIR} \
    --namespace ${NAMESPACE} \
    --set image.tag=${DYNAMIC_TAG} \
    --set service.port=${DYNAMIC_PORT} || {
        echo "Helm installation failed!"
        exit 1
    }

# Verify deployment
echo "Verifying deployment..."
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
kubectl get servicemonitor -n ${NAMESPACE}

echo "Installation complete with port $DYNAMIC_PORT!"
