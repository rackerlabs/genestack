#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

# Set default directories
GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"

GENESTACK_PROMETHEUS_DIR="${GENESTACK_PROMETHEUS_DIR:-$GENESTACK_DIR/base-helm-configs/prometheus}"
GENESTACK_PROMETHEUS_RULES_DIR="${GENESTACK_PROMETHEUS_RULES_DIR:-$GENESTACK_DIR/base-helm-configs/prometheus/rules}"
GENESTACK_PROMETHEUS_CONFIG_DIR="${GENESTACK_PROMETHEUS_CONFIG_DIR:-$GENESTACK_CONFIG_DIR/helm-configs/prometheus}"

# Prepare an array to collect --values arguments
values_args=()

# Include only the base override file from the base directory
base_override="$GENESTACK_PROMETHEUS_DIR/prometheus-helm-overrides.yaml"
if [[ -e "$base_override" ]]; then
  echo "Including base override: $base_override"
  values_args+=("--values" "$base_override")
else
  echo "Warning: Base override file not found: $base_override"
fi

# Include all rules YAML files from base
if [[ -d "$GENESTACK_PROMETHEUS_RULES_DIR" ]]; then
  echo "Including rules files from base directory:"
  for file in "$GENESTACK_PROMETHEUS_RULES_DIR"/*.yaml; do
    # Check that there is at least one match
    if [[ -e "$file" ]]; then
      echo "    $file"
      values_args+=("--values" "$file")
    fi
  done
else
  echo "Info: Rules directory not found: $GENESTACK_PROMETHEUS_RULES_DIR"
fi

# Include all YAML files from the configuration directory
if [[ -d "$GENESTACK_PROMETHEUS_CONFIG_DIR" ]]; then
  echo "Including overrides from config directory:"
  for file in "$GENESTACK_PROMETHEUS_CONFIG_DIR"/*.yaml; do
    # Check that there is at least one match
    if [[ -e "$file" ]]; then
      echo "    $file"
      values_args+=("--values" "$file")
    fi
  done
else
  echo "Warning: Config directory not found: $GENESTACK_PROMETHEUS_CONFIG_DIR"
fi

echo

# Add the Helm repository and update it
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Run the Helm upgrade/install command using the collected --values arguments
HELM_CMD="helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --create-namespace --namespace=prometheus --timeout 10m --version 70.4.2"
HELM_CMD+=" ${values_args[@]}"
HELM_CMD+=" --post-renderer $GENESTACK_CONFIG_DIR/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args prometheus/overlay"
HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
