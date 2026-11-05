#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
CHART_PATH="${GENESTACK_BASE_DIR}/charts/ovn-backup"
CONFIG_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/ovn-backup"

helm_args=()
for config_file in "${CONFIG_DIR}"/*.yaml; do
    if [ -f "${config_file}" ]; then
        helm_args+=(--values "${config_file}")
    fi
done

helm upgrade --install ovn-backup "${CHART_PATH}" \
    --namespace kube-system \
    --timeout 120m \
    "${helm_args[@]}" \
    "$@"
