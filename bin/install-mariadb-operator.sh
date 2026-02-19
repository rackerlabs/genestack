#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT and executes helm upgrade.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="mariadb-operator"
CRDS_NAME_DEFAULT="mariadb-operator-crds"
SERVICE_NAMESPACE="mariadb-system"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="mariadb-operator"
HELM_REPO_URL_DEFAULT="https://helm.mariadb.com/mariadb-operator"

# Directory Paths
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"

# Import Shared Library
LIB_PATH="${GENESTACK_BASE_DIR}/scripts/common-functions.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: Shared library not found at $LIB_PATH" >&2
    exit 1
fi

# Pre-flight Checks
check_dependencies "kubectl" "helm" "yq" "sed" "grep"
check_cluster_connection

# Argument Parsing
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

# Version Extraction
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME_DEFAULT}:" "$VERSION_FILE" | sed "s/.*${SERVICE_NAME_DEFAULT}: *//")
if [ -z "$SERVICE_VERSION" ]; then
    echo "Error: Could not extract version for '$SERVICE_NAME_DEFAULT' from $VERSION_FILE" >&2
    exit 1
fi
echo "Found version for $SERVICE_NAME_DEFAULT: $SERVICE_VERSION"

# MariaDB Specific: Cluster Name Logic
export CLUSTER_NAME=${CLUSTER_NAME:-cluster.local}
if [ "${CLUSTER_NAME}" != "cluster.local" ]; then
    SERVICE_CONFIG_FILE="$SERVICE_CUSTOM_OVERRIDES/mariadb-operator-helm-overrides.yaml"
    mkdir -p "$SERVICE_CUSTOM_OVERRIDES"
    touch "$SERVICE_CONFIG_FILE"
    if [ ! -s "$SERVICE_CONFIG_FILE" ]; then
        echo "clusterName: $CLUSTER_NAME" > "$SERVICE_CONFIG_FILE"
    else
        if grep -q "^clusterName:" "$SERVICE_CONFIG_FILE"; then
            sed -i -e "s/^clusterName: .*/clusterName: ${CLUSTER_NAME}/" "$SERVICE_CONFIG_FILE"
        else
            echo "clusterName: $CLUSTER_NAME" >> "$SERVICE_CONFIG_FILE"
        fi
    fi
fi

# Chart Metadata Extraction
for yaml_file in "${SERVICE_CUSTOM_OVERRIDES}"/*.yaml; do
    if [ -f "$yaml_file" ]; then
        HELM_REPO_URL=$(yq eval '.chart.repo_url // ""' "$yaml_file")
        HELM_REPO_NAME=$(yq eval '.chart.repo_name // ""' "$yaml_file")
        SERVICE_NAME=$(yq eval '.chart.service_name // ""' "$yaml_file")
        CRDS_NAME=$(yq eval '.chart.service_crds // ""' "$yaml_file")
        break
    fi
done

: "${HELM_REPO_URL:=$HELM_REPO_URL_DEFAULT}"
: "${HELM_REPO_NAME:=$HELM_REPO_NAME_DEFAULT}"
: "${SERVICE_NAME:=$SERVICE_NAME_DEFAULT}"
: "${CRDS_NAME:=$CRDS_NAME_DEFAULT}"

# Helm Repository Setup
if [[ "$HELM_REPO_URL" == oci://* ]]; then
    CRDS_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$CRDS_NAME"
    HELM_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$SERVICE_NAME"
else
    update_helm_repo "$HELM_REPO_NAME" "$HELM_REPO_URL"
    CRDS_CHART_PATH="$HELM_REPO_NAME/$CRDS_NAME"
    HELM_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi

# Overrides Collection
overrides_args=()
process_overrides "$SERVICE_BASE_OVERRIDES" overrides_args "base overrides"
process_overrides "$SERVICE_CUSTOM_OVERRIDES" overrides_args "service config overrides"

# Install CRDs First
echo "Installing MariaDB Operator CRDs..."
helm upgrade --install "$CRDS_NAME_DEFAULT" "$CRDS_CHART_PATH" \
    --namespace="$SERVICE_NAMESPACE" \
    --create-namespace \
    --version "${SERVICE_VERSION}" \
    --wait

# Main Operator Installation
helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout "${HELM_TIMEOUT:-$HELM_TIMEOUT_DEFAULT}"
    --atomic
    --cleanup-on-fail
    "${overrides_args[@]}"
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"
)

echo "Executing Helm command:"
printf '%q ' "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"
echo

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "Helm upgrade successful. Waiting for MariaDB Operator..."
    kubectl -n "$SERVICE_NAMESPACE" rollout status deployment/"$SERVICE_NAME_DEFAULT"
    echo "✓ $SERVICE_NAME_DEFAULT is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
