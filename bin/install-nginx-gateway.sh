#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/nginx-gateway-fabric"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/nginx-gateway-fabric/helm-overrides.yaml"
NGINX_VERSION="1.4.0"
HELM_CMD="helm upgrade --install nginx-gateway-fabric oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
                       --create-namespace \
                       --namespace=nginx-gateway \
                       --post-renderer /etc/genestack/kustomize/kustomize.sh \
                       --post-renderer-args gateway/overlay \
                       --version ${NGINX_VERSION}"

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

kubectl kustomize "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${NGINX_VERSION}" | kubectl apply -f -

kubectl apply -f /opt/genestack/manifests/nginx-gateway/nginx-gateway-namespace.yaml

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
