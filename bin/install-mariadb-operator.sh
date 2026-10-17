#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME_DEFAULT="mariadb-operator"
CRDS_NAME_DEFAULT="mariadb-operator-crds"
SERVICE_NAMESPACE="mariadb-system"

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Missing secrets are generated in Kubernetes and
# existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT

# Custom values directory is used for generated clusterName overrides.
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

# Load the service configuration once for this installer.
service_config=$(load_service_config "$SERVICE_NAME_DEFAULT" --log-sources) || exit 1

# Resolve the chart version from the service config or chart versions file.
SERVICE_VERSION=$(resolve_chart_version "$SERVICE_NAME_DEFAULT" "$service_config") || exit 1

if [[ -z "$SERVICE_VERSION" ]]; then
    log_error "No chart version found for '$SERVICE_NAME_DEFAULT'."
    exit 1
fi

# Default parameter value
export CLUSTER_NAME=${CLUSTER_NAME:-cluster.local}

# 'cluster.local' is the default value in base helm values file
if [ "${CLUSTER_NAME}" != "cluster.local" ]; then
    SERVICE_CONFIG_FILE="$SERVICE_CUSTOM_OVERRIDES/mariadb-operator-helm-overrides.yaml"
    touch "$SERVICE_CONFIG_FILE"
    # Check if the file is empty and add/modify content accordingly
    if [ ! -s "$SERVICE_CONFIG_FILE" ]; then
        echo "clusterName: $CLUSTER_NAME" > "$SERVICE_CONFIG_FILE"
    else
        # If the clusterName line exists, modify it, otherwise add it at the end
        if grep -q "^clusterName:" "$SERVICE_CONFIG_FILE"; then
            sed -i -e "s/^clusterName: .*/clusterName: ${CLUSTER_NAME}/" "$SERVICE_CONFIG_FILE"
        else
            echo "clusterName: $CLUSTER_NAME" >> "$SERVICE_CONFIG_FILE"
        fi
    fi
fi

# The CRD chart is a sibling of the operator chart in the same repository.
CRDS_NAME=$(yq e '.chart.service_crds // .crd_chart // ""' - <<< "$service_config") || exit 1
if [[ -z "$CRDS_NAME" ]]; then
    echo "Error: Missing CRD chart name for $SERVICE_NAME_DEFAULT" >&2
    exit 1
fi

# Resolve the chart location from the service configuration.
resolve_service_chart "$SERVICE_NAME_DEFAULT" "$service_config" || exit 1

# Point at the CRD chart next to the operator chart by replacing the last
# path segment, e.g. mariadb-operator/mariadb-operator -> mariadb-operator/mariadb-operator-crds.
CRDS_CHART_PATH="${HELM_CHART_PATH%/*}/${CRDS_NAME}"

# A path starting with "/" means a local chart on disk; fail early if it is
# missing. Repo and OCI charts are not folders, so Helm checks those itself.
if [[ "$CRDS_CHART_PATH" == /* && ! -d "$CRDS_CHART_PATH" ]]; then
    echo "Error: Local CRD chart not found at $CRDS_CHART_PATH" >&2
    exit 1
fi

# Collect Helm values files in override order.
build_helm_args "$SERVICE_NAME_DEFAULT" || exit 1

# Collect all --set arguments, executing commands and quoting safely
# Collect secret-backed --set arguments from bin/services/${SERVICE_NAME_DEFAULT}.yaml.
collect_service_secret_set_args "$SERVICE_NAME_DEFAULT"
set_args=("${SECRET_HELM_SET_ARGS[@]}")

# Install the CRDs that match the version defined
helm upgrade --install --namespace="$SERVICE_NAMESPACE" --create-namespace "$CRDS_NAME_DEFAULT" "$CRDS_CHART_PATH" --version "${SERVICE_VERSION}"

helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m

    "${overrides_args[@]}"
    "${set_args[@]}"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"
