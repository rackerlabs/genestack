#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/kube-ovn"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml"
KUBE_OVN_VERSION="${KUBE_OVN_VERSION:-v1.12.31}"
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
values_files=("$BASE_OVERRIDES")

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            # Avoid re-adding the base override file if present in the service directory
            if [ "${yaml_file}" != "${BASE_OVERRIDES}" ]; then
                HELM_CMD+=" -f ${yaml_file}"
                values_files+=("${yaml_file}")
            fi
        done
    fi
done

override_image=$(python3 - <<EOF "${values_files[@]}"
import sys
import yaml
image=""
for file in sys.argv[1:]:
    try:
        with open(file, "r") as overrides_file:
            override_yaml = yaml.safe_load(overrides_file)
            try:
                image = override_yaml["global"]["images"]["kubeovn"]["tag"]
            except Exception as e:
                pass
    except Exception as e:
        raise
print(image)
EOF
)

if [[ "$override_image" != "" && ( "$override_image" != "$KUBE_OVN_VERSION" ) ]]
then
   echo "ERROR Install script specifies KUBE_OVN_VERSION $KUBE_OVN_VERSION but overrides .global.images.kubeovn.tag has final value $override_image"
   exit 1
fi

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args kube-ovn/overlay"

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
