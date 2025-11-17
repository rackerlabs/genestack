#!/bin/bash
set -e  # Exit on error

# Variables
CHART_DIR="/opt/genestack/base-helm-configs/barbican-exporter"
NAMESPACE="openstack"
RELEASE_NAME="barbican-exporter"

# Check if chart directory exists
if [ ! -d "${CHART_DIR}" ]; then
    echo "Chart directory ${CHART_DIR} does not exist!"
    exit 1
fi

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

# Install Helm chart with dynamic values
echo "Installing Helm chart..."
helm install ${RELEASE_NAME} ${CHART_DIR} \
    --namespace ${NAMESPACE} || {
        echo "Helm installation failed!"
        exit 1
    }

# Verify deployment
echo "Verifying deployment..."
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
kubectl get servicemonitor -n ${NAMESPACE}

echo "Installation complete for $RELEASE_NAME!"
