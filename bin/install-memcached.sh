#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/memcached"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/memcached/memcached-helm-overrides.yaml"

# Read memcached version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract memcached version using grep and sed
MEMCACHED_VERSION=$(grep 'memcached:' "$VERSION_FILE" | sed 's/.*memcached: *//')

if [ -z "$MEMCACHED_VERSION" ]; then
    echo "Error: Could not extract memcached version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install memcached bitnami/memcached \
    --version ${MEMCACHED_VERSION} \
    --namespace=openstack \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args memcached/overlay"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            # Avoid re-adding the base override file if present in the service directory
            if [ "${yaml_file}" != "${BASE_OVERRIDES}" ]; then
                HELM_CMD+=" -f ${yaml_file}"
            fi
        done
    fi
done

HELM_CMD+=" $@"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
