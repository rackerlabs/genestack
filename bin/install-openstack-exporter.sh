#!/bin/bash
set -euo pipefail

SERVICE_NAME_DEFAULT="openstack-exporter"
CHART_DIR_NAME="openstack-api-exporter-chart"
SERVICE_NAMESPACE="monitoring"

GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

CHART_DIR="${GENESTACK_BASE_DIR}/base-helm-configs/${CHART_DIR_NAME}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${CHART_DIR_NAME}"
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

source "$(dirname "$0")/monitoring-common.sh"

# Check if chart directory exists
if [ ! -d "${CHART_DIR}" ]; then
    echo "Chart directory ${CHART_DIR} does not exist!"
    exit 1
fi

# Function to find an unused port
find_unused_port() {
    local port=49152
    while :; do
        if ! kubectl get svc --all-namespaces -o jsonpath='{range .items[*]}{.spec.ports[*].port}{"\n"}{end}' | grep -q "${port}$"; then
            echo "$port"
            return 0
        fi
        ((port++))
        if [ $port -gt 65535 ]; then
            echo "No unused port found in range 49152-65535" >&2
            exit 1
        fi
    done
}

monitoring_ensure_namespace "${SERVICE_NAMESPACE}"
monitoring_label_namespace_for_talos "${SERVICE_NAMESPACE}"

# Check if release already exists
if helm list -n "${SERVICE_NAMESPACE}" | grep -q "${SERVICE_NAME_DEFAULT}"; then
    echo "Release ${SERVICE_NAME_DEFAULT} already exists!"
    exit 1
fi

# Find and set dynamic values
DYNAMIC_PORT=$(find_unused_port)
DYNAMIC_TAG="sha-7951e2c"
echo "Using dynamic port: $DYNAMIC_PORT and tag: $DYNAMIC_TAG"

monitoring_apply_secret_from_kubesecrets "keystone-auth-openstack-exporter" "monitoring" "monitoring" || true

overrides_args=()

for base_file in "${CHART_DIR}/values.yaml" "${CHART_DIR}/probe_target.yaml"; do
    if [[ -f "${base_file}" ]]; then
        echo " - ${base_file}"
        overrides_args+=("-f" "${base_file}")
    fi
done

if [[ -d "${GLOBAL_OVERRIDES_DIR}" ]]; then
    echo "Including global overrides from directory: ${GLOBAL_OVERRIDES_DIR}"
    for file in "${GLOBAL_OVERRIDES_DIR}"/*.yaml; do
        if [[ -e "${file}" ]]; then
            echo " - ${file}"
            overrides_args+=("-f" "${file}")
        fi
    done
fi

if [[ -d "${SERVICE_CUSTOM_OVERRIDES}" ]]; then
    echo "Including overrides from service config directory: ${SERVICE_CUSTOM_OVERRIDES}"
    for file in "${SERVICE_CUSTOM_OVERRIDES}"/*.yaml; do
        if [[ -e "${file}" ]]; then
            echo " - ${file}"
            overrides_args+=("-f" "${file}")
        fi
    done
fi

helm_command=(
    helm upgrade --install "${SERVICE_NAME_DEFAULT}" "${CHART_DIR}"
    --namespace "${SERVICE_NAMESPACE}"
    --create-namespace
    --timeout 15m
    "${overrides_args[@]}"
    --set "image.tag=${DYNAMIC_TAG}"
    --set "service.port=${DYNAMIC_PORT}"
    --post-renderer "${GENESTACK_OVERRIDES_DIR}/kustomize/kustomize.sh"
    --post-renderer-args "${CHART_DIR_NAME}/overlay"
    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

"${helm_command[@]}"

# Verify deployment
echo "Verifying deployment..."
kubectl get pods -n "${SERVICE_NAMESPACE}"
kubectl get svc -n "${SERVICE_NAMESPACE}"
kubectl get servicemonitor -n "${SERVICE_NAMESPACE}"

echo "Installation complete with port $DYNAMIC_PORT!"
