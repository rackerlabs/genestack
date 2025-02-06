#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/memcached"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/memcached/memcached-helm-overrides.yaml"

HELM_CMD="helm upgrade --install memcached oci://registry-1.docker.io/bitnamicharts/memcached \
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

HELM_CMD+=" $*"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
