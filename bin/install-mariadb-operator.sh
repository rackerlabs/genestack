#!/bin/bash

# Default parameter value
CLUSTER_NAME=${1:-cluster.local}

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/mariadb-operator"

# 'cluster.local' is the default value in base helm values file
if [ "${CLUSTER_NAME}" != "cluster.local" ]; then
    CONFIG_FILE="$CONFIG_DIR/mariadb-operator-helm-overrides.yaml"

    mkdir -p $CONFIG_DIR
    touch "$CONFIG_FILE"

    # Check if the file is empty and add/modify content accordingly
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "clusterName: $CLUSTER_NAME" > "$CONFIG_FILE"
    else
        # If the clusterName line exists, modify it, otherwise add it at the end
        if grep -q "^clusterName:" "$CONFIG_FILE"; then
            sed -i -e "s/^clusterName: .*/clusterName: ${CLUSTER_NAME}/" "$CONFIG_FILE"
        else
            echo "clusterName: $CLUSTER_NAME" >> "$CONFIG_FILE"
        fi
    fi
fi

# Helm command setup
HELM_CMD="helm upgrade --install mariadb-operator https://mariadb-operator.github.io/mariadb-operator \
    --namespace=mariadb-system \
    --create-namespace \
    --timeout 120m \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args mariadb-operator/overlay \
    -f /opt/genestack/base-helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Add all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

# Run the helm command
echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
