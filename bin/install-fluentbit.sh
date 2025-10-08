#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/fluentbit"
FLUENTBIT_CHART_VERSION="0.52.0"

# Read fluentbit version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract fluentbit version using grep and sed
FLUENTBIT_VERSION=$(grep 'fluentbit:' "$VERSION_FILE" | sed 's/.*fluentbit: *//')

if [ -z "$FLUENTBIT_VERSION" ]; then
    echo "Error: Could not extract fluentbit version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install \
                       --version $FLUENTBIT_VERSION \
                       --namespace fluentbit \
                       --create-namespace fluentbit fluent/fluent-bit"

HELM_CMD+=" -f /opt/genestack/base-helm-configs/fluentbit/fluentbit-helm-overrides.yaml"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" $@"

helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
