#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/fluentbit"

HELM_CMD="helm upgrade --install --namespace fluentbit --create-namespace fluentbit fluent/fluent-bit"

HELM_CMD+=" -f /opt/genestack/base-helm-configs/fluentbit/fluentbit-helm-overrides.yaml"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" $*"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
