#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/kube-ovn"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml"
KUBE_OVN_VERSION="v1.12.31"
MASTER_NODES=$(kubectl get nodes -l kube-ovn/role=master -o json | jq -r '[.items[].status.addresses[] | select(.type == "InternalIP") | .address] | join(",")' | sed 's/,/\\,/g')
MASTER_NODE_COUNT=$(kubectl get nodes -l kube-ovn/role=master -o json | jq -r '.items[].status.addresses[] | select(.type=="InternalIP") | .address' | wc -l)

if [ "${MASTER_NODE_COUNT}" -eq 0 ]; then
    echo "No master nodes found"
    echo "Be sure to label your master nodes with kube-ovn/role=master before running this script"
    echo "Exiting"
    exit 1
fi

helm repo add kubeovn https://kubeovn.github.io/kube-ovn
helm repo update

HELM_CMD="helm upgrade --install kube-ovn kubeovn/kube-ovn \
                       --version ${KUBE_OVN_VERSION} \
                       --namespace=kube-system \
                       --set MASTER_NODES=\"${MASTER_NODES}\" \
                       --set replicaCount=${MASTER_NODE_COUNT}"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            # Avoid re-adding the base override file if present in the service directory
            if [ "${yaml_file}" != "${BASE_OVERRIDES}" ]; then
                HELM_CMD+=" -f ${yaml_file}"
            fi
        done
    fi
done

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
