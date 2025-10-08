#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/prometheus-kube-event-exporter/values.yaml"

# Read kube-event-exporter version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract kube-event-exporter version using grep and sed
KUBE_EVENT_EXPORTER_VERSION=$(grep 'kube-event-exporter:' "$VERSION_FILE" | sed 's/.*kube-event-exporter: *//')

if [ -z "$KUBE_EVENT_EXPORTER_VERSION" ]; then
    echo "Error: Could not extract kube-event-exporter version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install kube-event-exporter oci://registry-1.docker.io/bitnamicharts/kubernetes-event-exporter \
    --version ${KUBE_EVENT_EXPORTER_VERSION} \
    --namespace=openstack \
    --timeout 120m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR"; do
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

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
