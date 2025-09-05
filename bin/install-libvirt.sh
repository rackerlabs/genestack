#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/libvirt"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/libvirt/libvirt-helm-overrides.yaml"

# Read libvirt version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract libvirt version using grep and sed
LIBVIRT_VERSION=$(grep 'libvirt:' "$VERSION_FILE" | sed 's/.*libvirt: *//')

if [ -z "$LIBVIRT_VERSION" ]; then
    echo "Error: Could not extract libvirt version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install libvirt openstack-helm-infra/libvirt --version ${LIBVIRT_VERSION} \
    --namespace=openstack \
    --timeout 120m"

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

helm repo add openstack-helm-infra https://tarballs.opendev.org/openstack/openstack-helm-infra
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
