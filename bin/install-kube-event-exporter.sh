#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/prometheus-kube-event-exporter/values.yaml"

HELM_CMD="helm upgrade --install kube-event-exporter oci://registry-1.docker.io/bitnamicharts/kubernetes-event-exporter \
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
