#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/grafana"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/grafana/grafana-helm-overrides.yaml"

# Read grafana version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract grafana version using grep and sed
GRAFANA_VERSION=$(grep 'grafana:' "$VERSION_FILE" | sed 's/.*grafana: *//')

if [ -z "$GRAFANA_VERSION" ]; then
    echo "Error: Could not extract grafana version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install grafana grafana/grafana \
  --version ${GRAFANA_VERSION} \
  --namespace=grafana \
  --create-namespace \
  --timeout 120m \
  --post-renderer /etc/genestack/kustomize/kustomize.sh \
  --post-renderer-args grafana/overlay"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" $@"

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
