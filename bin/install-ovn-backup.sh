#!/bin/bash
# Description: Installs the in-tree OVN backup Helm chart with dynamic values
# files and the common Genestack service installer helpers.

# Service
SERVICE_NAME="ovn-backup"
SERVICE_NAMESPACE="kube-system"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT

# This chart is maintained in the Genestack repository rather than a remote
# Helm repository, so charts/ovn-backup/Chart.yaml is its version source.
HELM_CHART_PATH="${GENESTACK_BASE_DIR}/charts/${SERVICE_NAME}"

# Define service-specific override directories based on the framework.
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME}"

# Prepare an array to collect -f arguments. OVN backup does not consume the
# OpenStack global overrides; chart defaults and service overrides are enough.
overrides_args=()

if [[ -d "$SERVICE_BASE_OVERRIDES" ]]; then
    echo "Including base overrides from directory: $SERVICE_BASE_OVERRIDES"
    for file in "$SERVICE_BASE_OVERRIDES"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
fi

if [[ -d "$SERVICE_CUSTOM_OVERRIDES" ]]; then
    echo "Including overrides from config directory:"
    for file in "$SERVICE_CUSTOM_OVERRIDES"/*.yaml; do
        if [[ -e "$file" ]]; then
            echo " - $file"
            overrides_args+=("-f" "$file")
        fi
    done
else
    echo "Warning: Config directory not found: $SERVICE_CUSTOM_OVERRIDES"
fi

echo

# Collect secret-backed --set arguments from bin/services/ovn-backup.yaml.
collect_service_secret_set_args "$SERVICE_NAME"
set_args=("${SECRET_HELM_SET_ARGS[@]}")

helm_command=(
    helm upgrade --install "$SERVICE_NAME" "$HELM_CHART_PATH"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

"${helm_command[@]}"
