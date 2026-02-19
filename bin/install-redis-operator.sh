#!/bin/bash
# Description: Installs Redis Operator followed by the Redis Replication configuration.
# shellcheck disable=SC2124,SC2145,SC2294

# Service Configuration
SERVICE_NAME_DEFAULT="redis-replication"
OPERATOR_NAME_DEFAULT="redis-operator"
SERVICE_NAMESPACE="redis-systems"

# Helm Defaults
HELM_REPO_NAME_DEFAULT="ot-helm"
HELM_REPO_URL_DEFAULT="https://ot-container-kit.github.io/helm-charts"

# Directory Paths
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${SERVICE_NAME_DEFAULT}"
SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${SERVICE_NAME_DEFAULT}"
GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

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
ROTATE_SECRETS=false
HELM_PASS_THROUGH=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rotate-secret) ROTATE_SECRETS=true; shift ;;
        *) HELM_PASS_THROUGH+=("$1"); shift ;;
    esac
done

# Version Extraction
VERSION_FILE="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE" >&2
    exit 1
fi

REDIS_OPERATOR_VERSION=$(grep 'redis-operator:' "$VERSION_FILE" | sed 's/.*redis-operator: *//')
SERVICE_VERSION=$(grep 'redis-replication:' "$VERSION_FILE" | sed 's/.*redis-replication: *//')

if [[ -z "$REDIS_OPERATOR_VERSION" || -z "$SERVICE_VERSION" ]]; then
    echo "Error: Could not extract versions from $VERSION_FILE" >&2
    exit 1
fi

# Chart Metadata Extraction
for yaml_file in "${SERVICE_CUSTOM_OVERRIDES}"/*.yaml; do
    if [ -f "$yaml_file" ]; then
        HELM_REPO_URL=$(yq eval '.chart.repo_url // ""' "$yaml_file")
        HELM_REPO_NAME=$(yq eval '.chart.repo_name // ""' "$yaml_file")
        OPERATOR_NAME=$(yq eval '.chart.operator_name // ""' "$yaml_file")
        SERVICE_NAME=$(yq eval '.chart.service_name // ""' "$yaml_file")
        break
    fi
done

: "${HELM_REPO_URL:=$HELM_REPO_URL_DEFAULT}"
: "${HELM_REPO_NAME:=$HELM_REPO_NAME_DEFAULT}"
: "${OPERATOR_NAME:=$OPERATOR_NAME_DEFAULT}"
: "${SERVICE_NAME:=$SERVICE_NAME_DEFAULT}"

# Helm Repository Setup
if [[ "$HELM_REPO_URL" == oci://* ]]; then
    OPERATOR_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$OPERATOR_NAME"
    REPLICATION_CHART_PATH="$HELM_REPO_URL/$HELM_REPO_NAME/$SERVICE_NAME"
else
    update_helm_repo "$HELM_REPO_NAME" "$HELM_REPO_URL"
    OPERATOR_CHART_PATH="$HELM_REPO_NAME/$OPERATOR_NAME"
    REPLICATION_CHART_PATH="$HELM_REPO_NAME/$SERVICE_NAME"
fi

# --- Step 1: Install Redis Operator ---
echo "Installing Redis Operator..."
helm upgrade --install "$OPERATOR_NAME_DEFAULT" "$OPERATOR_CHART_PATH" \
    --namespace "$SERVICE_NAMESPACE" \
    --version "${REDIS_OPERATOR_VERSION}" \
    --create-namespace \
    --wait

kubectl -n "$SERVICE_NAMESPACE" rollout status deployment/"$OPERATOR_NAME_DEFAULT"

# --- Step 2: Install Redis Replication ---
echo "Installing Redis Replication configuration..."

# Overrides Collection
overrides_args=()
process_overrides "$SERVICE_BASE_OVERRIDES" overrides_args "base overrides"
process_overrides "$GLOBAL_OVERRIDES_DIR" overrides_args "global overrides"
process_overrides "$SERVICE_CUSTOM_OVERRIDES" overrides_args "service config overrides"

# Secret Handling (e.g., for Redis AUTH)
echo "Validating secrets for $SERVICE_NAME_DEFAULT..."
S_REDIS_PASSWORD=$(get_or_create_secret "$SERVICE_NAMESPACE" "redis-password" "password" 32 "$ROTATE_SECRETS")

set_args=(
    --set "redisPassword=$S_REDIS_PASSWORD"
)

helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$REPLICATION_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout "${HELM_TIMEOUT:-$HELM_TIMEOUT_DEFAULT}"
    --atomic
    --cleanup-on-fail
    "${overrides_args[@]}"
    "${set_args[@]}"
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"
)

echo "Executing Helm command:"
printf '%q ' "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"
echo

if "${helm_command[@]}" "${HELM_PASS_THROUGH[@]}"; then
    echo "✓ $SERVICE_NAME_DEFAULT (and Operator) is ready."
else
    echo "Error: Helm upgrade failed." >&2
    exit 1
fi
