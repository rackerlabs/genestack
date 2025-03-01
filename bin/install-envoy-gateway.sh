#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/envoyproxy-gateway"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/envoyproxy-gateway/envoy-gateway-helm-overrides.yaml"
ENVOY_VERSION="v1.3.0"
HELM_CMD="helm upgrade --install envoyproxy-gateway oci://docker.io/envoyproxy/gateway-helm \
                       --version ${ENVOY_VERSION} \
                       --namespace envoyproxy-gateway-system \
                       --create-namespace"

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

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"

# Install egctl
if [ ! -f "/usr/local/bin/egctl" ]; then
    sudo mkdir -p /opt/egctl-install
    pushd /opt/egctl-install || exit 1
        sudo wget "https://github.com/envoyproxy/gateway/releases/download/${ENVOY_VERSION}/egctl_${ENVOY_VERSION}_linux_amd64.tar.gz" -O egctl.tar.gz
        sudo tar -xvf egctl.tar.gz
        sudo install -o root -g root -m 0755 bin/linux/amd64/egctl /usr/local/bin/egctl
        /usr/local/bin/egctl completion bash > /tmp/egctl.bash
        sudo mv /tmp/egctl.bash /etc/bash_completion.d/egctl
    popd || exit 1
fi
