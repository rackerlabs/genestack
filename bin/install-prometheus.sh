#!/bin/bash

GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"

GENESTACK_PROMETHEUS_DIR=\
"${GENESTACK_PROMETHEUS_DIR:-$GENESTACK_DIR/base-helm-configs/prometheus}"
GENESTACK_PROMETHEUS_CONFIG_DIR=\
"${GENESTACK_PROMETHEUS_CONFIG_DIR:-$GENESTACK_CONFIG_DIR/helm-configs/prometheus}"

VALUES_BASE_FILENAMES=(
    "prometheus-helm-overrides.yaml"
    "alerting_rules.yaml"
    "alertmanager_config.yaml"
)

# Though it probably wouldn't make any difference for all of the
# $GENESTACK_CONFIG_DIR files to come last, this takes care to fully preserve
# the order
echo "Including overrides in order:"
values_args=()
for BASE_FILENAME in "${VALUES_BASE_FILENAMES[@]}"
do
    for DIR in "$GENESTACK_PROMETHEUS_DIR" "$GENESTACK_PROMETHEUS_CONFIG_DIR"
    do
        ABSOLUTE_PATH="$DIR/$BASE_FILENAME"
        if [[ -e "$ABSOLUTE_PATH" ]]
        then
            echo "    $ABSOLUTE_PATH"
            values_args+=("--values" "$ABSOLUTE_PATH")
        fi
    done
done
echo

helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --create-namespace --namespace=prometheus --timeout 10m \
    "${values_args[@]}" \
    --post-renderer "$GENESTACK_CONFIG_DIR/kustomize/kustomize.sh" \
    --post-renderer-args prometheus/overlay "$*"
