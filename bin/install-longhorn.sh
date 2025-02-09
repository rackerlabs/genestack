#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/longhorn"

HELM_CMD="helm upgrade --install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace"

HELM_CMD+=" --set persistence.defaultClass=false --version 1.8.0"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" $@"

helm repo add longhorn https://charts.longhorn.io
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
