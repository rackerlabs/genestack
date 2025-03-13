#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
set -e

set -o pipefail

if [ -z "${ACME_EMAIL}" ]; then
  read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
  export ACME_EMAIL="${ACME_EMAIL:-}"
fi

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
  read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
  export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cluster.local}"
fi

if [ "${HYPERCONVERGED:-false}" = "true" ]; then
  kubectl label node --all openstack-control-plane=enabled \
                           openstack-compute-node=enabled \
                           openstack-network-node=enabled \
                           openstack-storage-node=enabled \
                           node-role.kubernetes.io/worker=worker
else
  LABEL_FAIL=0
  for label in openstack-control-plane=enabled \
               openstack-compute-node=enabled \
               openstack-network-node=enabled \
               openstack-storage-node=enabled \
               node-role.kubernetes.io/worker=worker; do
    if [ -z "$(kubectl get nodes -l "${label}" -o name)" ]; then
      echo "[FAILURE] No nodes with the label ${label} found, please label the nodes you want to use for the OpenStack deployment"
      LABEL_FAIL=1
    fi
  done
  if [ "${LABEL_FAIL}" -eq 1 ]; then
    exit 1
  fi
fi

kubectl label node -l beta.kubernetes.io/os=linux kubernetes.io/os=linux
kubectl label node -l node-role.kubernetes.io/control-plane kube-ovn/role=master
kubectl label node -l ovn.kubernetes.io/ovs_dp_type!=userspace ovn.kubernetes.io/ovs_dp_type=kernel
kubectl label node -l node-role.kubernetes.io/control-plane longhorn.io/storage-node=enabled

if ! kubectl taint nodes -l node-role.kubernetes.io/control-plane node-role.kubernetes.io/control-plane:NoSchedule-; then
  echo "Taint already removed"
fi

if [ -z "${CONTAINER_INTERFACE}" ]; then
  export CONTAINER_INTERFACE=$(ip -details -json link show | \
    jq -r '[.[] | if .linkinfo.info_kind // .link_type == "loopback" or
           (.ifname | test("idrac+")) then empty else .ifname end ] | .[0]')
  echo "[WARNING] The interface for the OVN network is required."
  echo "          The script will use the default route interface ${CONTAINER_INTERFACE}"
fi

if [ -z "${CONTAINER_VLAN_INTERFACE}" ]; then
  echo "[WARNING] The vlan interface for the OVN network is required."
  echo "          The script will use the default route interface ${CONTAINER_INTERFACE}"
  export CONTAINER_VLAN_INTERFACE="${CONTAINER_INTERFACE}"
fi

if [ -z "${COMPUTE_INTERFACE}" ]; then
  export COMPUTE_INTERFACE=$(ip -details -json link show | \
    jq -r '[.[] | if .linkinfo.info_kind // .link_type == "loopback" or
           (.ifname | test("idrac+")) then empty else .ifname end ] | .[-1]')
  echo "[WARNING] The interface for the compute network is required."
  echo "          The script will use the last interface found ${COMPUTE_INTERFACE}"
fi

if [ "${COMPUTE_INTERFACE}" = "${CONTAINER_INTERFACE}" ]; then
  echo "[ERROR] The compute interface cannot be the same as the container interface"
  exit 1
fi

kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/int_bridge='br-int'
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/bridges='br-ex'
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/ports="br-ex:${COMPUTE_INTERFACE}"
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/mappings='physnet1:br-ex'
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/availability_zones='az1'
kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/gateway='enabled'

# Deploy kube-ovn
if [ ! -f /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml ]; then
cat > /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml <<EOF
---
networking:
  IFACE: "${CONTAINER_INTERFACE}"
  vlan:
    VLAN_INTERFACE_NAME: "${CONTAINER_VLAN_INTERFACE}"
EOF
fi
/opt/genestack/bin/install-kube-ovn.sh
echo "Waiting for the kube-ovn-controller to be available"
kubectl -n kube-system wait --timeout=5m deployments.app/kube-ovn-controller --for=condition=available

# Setup shared pod storage
kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-namespace.yaml
/opt/genestack/bin/install-longhorn.sh
sed -i 's/numberOfReplicas.*/numberOfReplicas: "'"${LONGHORN_STORAGE_REPLICAS:-2}"'"/g' \
       /etc/genestack/manifests/longhorn/longhorn-general-storageclass.yaml
kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-general-storageclass.yaml

# Deploy prometheus
/opt/genestack/bin/install-prometheus.sh

# Deploy metallb
kubectl apply -f /etc/genestack/manifests/metallb/metallb-namespace.yaml
/opt/genestack/bin/install-metallb.sh
echo "Waiting for the metallb-controller to be available"
kubectl -n metallb-system wait --timeout=5m deployments.apps/metallb-controller --for=condition=available
kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml

# Deploy openstack
kubectl apply -k /etc/genestack/kustomize/openstack

# Deploy envoy
/opt/genestack/bin/install-envoy-gateway.sh
echo "Waiting for the envoy-gateway to be available"
kubectl -n envoyproxy-gateway-system wait --timeout=5m deployments.apps/envoy-gateway --for=condition=available
GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" ACME_EMAIL="${ACME_EMAIL}" /opt/genestack/bin/setup-envoy-gateway.sh

# Run a rollout for cert-manager
echo "Waiting for the cert-manager to be available"
kubectl -n cert-manager wait --timeout=5m deployments.apps cert-manager --for=condition=available

# Deploy the Genestack secrets
/opt/genestack/bin/create-secrets.sh
if ! kubectl create -f /etc/genestack/kubesecrets.yaml; then
  echo "Secrets already created"
fi

# Deploy mariadb
/opt/genestack/bin/install-mariadb-operator.sh
if ! kubectl -n mariadb-system wait --timeout=1m deployments.apps mariadb-operator-webhook --for=condition=available; then
  echo "Recycling the mariadb-operator pods because sometimes they're stupid"
  kubectl -n mariadb-system get pods -o name | xargs kubectl -n mariadb-system delete
  kubectl -n mariadb-system wait --timeout=5m deployments.apps mariadb-operator-webhook --for=condition=available
fi

echo "Waiting for the mariadb-operator-webhook to be available"
kubectl -n openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay

# Deploy rabbitmq
kubectl apply -k /etc/genestack/kustomize/rabbitmq-operator
kubectl apply -k /etc/genestack/kustomize/rabbitmq-topology-operator
echo "Waiting for the rabbitmq-cluster-operator to be available"
kubectl -n rabbitmq-system wait --timeout=5m deployments.apps rabbitmq-cluster-operator --for=condition=available
kubectl apply -k /etc/genestack/kustomize/rabbitmq-cluster/overlay

# Deploy ovn
kubectl apply -k /etc/genestack/kustomize/ovn

# Deploy memcached
/opt/genestack/bin/install-memcached.sh

# Deploy libvirt
/opt/genestack/bin/install-libvirt.sh
