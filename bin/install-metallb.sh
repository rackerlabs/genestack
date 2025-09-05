#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/metallb"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/metallb/metallb-helm-overrides.yaml"

# Read metallb version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract metallb version using grep and sed
METALLB_VERSION=$(grep 'metallb:' "$VERSION_FILE" | sed 's/.*metallb: *//')

if [ -z "$METALLB_VERSION" ]; then
    echo "Error: Could not extract metallb version from $VERSION_FILE"
    exit 1
fi

helm repo add metallb https://metallb.github.io/metallb
helm repo update

HELM_CMD="helm upgrade --install --namespace metallb-system metallb metallb/metallb --version ${METALLB_VERSION}"

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
