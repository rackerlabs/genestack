#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155

set -o pipefail
set -e

if [ -z "${ACME_EMAIL}" ]; then
  read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
  export ACME_EMAIL="${ACME_EMAIL:-}"
fi

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
  read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
  export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cluster.local}"
fi

if [ -z "${OS_CLOUD}" ]; then
  read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD
  export OS_CLOUD="${OS_CLOUD:-default}"
fi

if [ -z "${OS_FLAVOR}" ]; then
  read -rp "Enter name of the flavor to use for the instances [gp.5.8.16]: " OS_FLAVOR
  export OS_FLAVOR=${OS_FLAVOR:-gp.5.8.16}
fi

if ! openstack router show hyperconverged-router; then
  openstack router create hyperconverged-router --external-gateway PUBLICNET
fi

if ! openstack network show hyperconverged-net; then
  openstack network create hyperconverged-net
fi

if ! TENANT_SUB_NETWORK_ID=$(openstack subnet show hyperconverged-subnet -f json | jq -r '.id'); then
  TENANT_SUB_NETWORK_ID=$(
    openstack subnet create hyperconverged-subnet \
              --network hyperconverged-net \
              --subnet-range 192.168.100.0/24 \
              --dns-nameserver 1.1.1.1 \
              --dns-nameserver 1.0.0.1 \
              -f json | jq -r '.id'
  )
fi

if ! openstack router show hyperconverged-router -f json | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_SUB_NETWORK_ID}; then
  openstack router add subnet hyperconverged-router hyperconverged-subnet
fi

if ! openstack network show hyperconverged-compute-net; then
  openstack network create hyperconverged-compute-net \
            --disable-port-security
fi

if ! TENANT_COMPUTE_SUB_NETWORK_ID=$(openstack subnet show hyperconverged-compute-subnet -f json | jq -r '.id'); then
  TENANT_COMPUTE_SUB_NETWORK_ID=$(
    openstack subnet create hyperconverged-compute-subnet \
              --network hyperconverged-compute-net \
              --subnet-range 192.168.102.0/24 \
              --no-dhcp -f json | jq -r '.id'
  )
fi

if ! openstack router show hyperconverged-router -f json | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_COMPUTE_SUB_NETWORK_ID}; then
  openstack router add subnet hyperconverged-router hyperconverged-compute-subnet
fi

if ! openstack security group show hyperconverged-http-secgroup; then
  openstack security group create hyperconverged-http-secgroup
fi

if ! openstack security group show hyperconverged-http-secgroup -f json | jq -r '.rules.[].port_range_max' | grep -q 443; then
  openstack security group rule create hyperconverged-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 443 \
            --description "https"
fi
if ! openstack security group show hyperconverged-http-secgroup -f json | jq -r '.rules.[].port_range_max' | grep -q 80; then
  openstack security group rule create hyperconverged-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 80 \
            --description "http"
fi

if ! openstack security group show hyperconverged-secgroup; then
  openstack security group create hyperconverged-secgroup
fi

if ! openstack security group show hyperconverged-secgroup -f json | jq -r '.rules.[].description' | grep -q "all internal traffic"; then
  openstack security group rule create hyperconverged-secgroup \
            --protocol any \
            --ingress \
            --remote-ip 192.168.100.0/24 \
            --description "all internal traffic"
fi

if ! openstack security group show hyperconverged-jump-secgroup; then
  openstack security group create hyperconverged-jump-secgroup
fi

if ! openstack security group show hyperconverged-jump-secgroup -f json | jq -r '.rules.[].port_range_max' | grep -q 22; then
  openstack security group rule create hyperconverged-jump-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 22 \
            --description "ssh"
fi
if ! openstack security group show hyperconverged-jump-secgroup -f json | jq -r '.rules.[].protocol' | grep -q icmp; then
  openstack security group rule create hyperconverged-jump-secgroup \
            --protocol icmp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --description "ping"
fi

if ! METAL_LB_IP=$(openstack port show metallb-vip-0-port -f json | jq -r '.fixed_ips[0].ip_address'); then
  METAL_LB_IP=$(openstack port create --security-group hyperconverged-http-secgroup --network hyperconverged-net metallb-vip-0-port -f json | jq -r '.fixed_ips[0].ip_address')
fi

METAL_LB_PORT_ID=$(openstack port show metallb-vip-0-port -f value -c ID)

if ! METAL_LB_VIP=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f json | jq -r '.[]."Floating IP Address"'); then
  METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
elif [ -z "${METAL_LB_VIP}" ]; then
  METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
fi

if ! WORKER_0_PORT=$(openstack port show hyperconverged-0-mgmt-port -f value -c ID); then
  export WORKER_0_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group hyperconverged-secgroup \
                          --security-group hyperconverged-jump-secgroup \
                          --security-group hyperconverged-http-secgroup \
                          --network hyperconverged-net \
                          -f value \
                          -c id \
                          hyperconverged-0-mgmt-port
  )
fi

if ! WORKER_1_PORT=$(openstack port show hyperconverged-1-mgmt-port -f value -c ID); then
  export WORKER_1_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group hyperconverged-secgroup \
                          --security-group hyperconverged-http-secgroup \
                          --network hyperconverged-net \
                          -f value \
                          -c id \
                          hyperconverged-1-mgmt-port
  )
fi

if ! WORKER_2_PORT=$(openstack port show hyperconverged-2-mgmt-port -f value -c ID); then
  export WORKER_2_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group hyperconverged-secgroup \
                          --security-group hyperconverged-http-secgroup \
                          --network hyperconverged-net \
                          -f value \
                          -c id \
                          hyperconverged-2-mgmt-port
  )
fi

if ! JUMP_HOST_VIP=$(openstack floating ip list --port ${WORKER_0_PORT} -f json | jq -r '.[]."Floating IP Address"'); then
  JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${JUMP_HOST_VIP}" ]; then
  JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
fi

if ! COMPUTE_0_PORT=$(openstack port show hyperconverged-0-compute-port -f value -c ID) 2> /dev/null; then
  export COMPUTE_0_PORT=$(
    openstack port create --network hyperconverged-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          hyperconverged-0-compute-port
  )
fi

if ! COMPUTE_1_PORT=$(openstack port show hyperconverged-1-compute-port -f value -c ID) 2> /dev/null; then
  export COMPUTE_1_PORT=$(
    openstack port create --network hyperconverged-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          hyperconverged-1-compute-port
  )
fi

if ! COMPUTE_2_PORT=$(openstack port show hyperconverged-2-compute-port -f value -c ID) 2> /dev/null; then
  export COMPUTE_2_PORT=$(
    openstack port create --network hyperconverged-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          hyperconverged-2-compute-port
  )
fi

if ! openstack keypair show hyperconverged-key; then
    if [ ! -f ~/.ssh/hyperconverged-key.pem ]; then
      openstack keypair create hyperconverged-key > ~/.ssh/hyperconverged-key.pem
      chmod 600 ~/.ssh/hyperconverged-key.pem
      openstack keypair show hyperconverged-key --public-key > ~/.ssh/hyperconverged-key.pub
    else
      if [ -f ~/.ssh/hyperconverged-key.pub ]; then
        openstack keypair create hyperconverged-key --public-key ~/.ssh/hyperconverged-key.pub
      fi
    fi
fi

ssh-add ~/.ssh/hyperconverged-key.pem

# Create the three lab instances
if ! openstack server show hyperconverged-0; then
  openstack server create hyperconverged-0 \
            --port ${WORKER_0_PORT} \
            --port ${COMPUTE_0_PORT} \
            --image "Ubuntu 24.04" \
            --key-name hyperconverged-key \
            --flavor ${OS_FLAVOR}
fi

if ! openstack server show hyperconverged-1; then
  openstack server create hyperconverged-1 \
            --port ${WORKER_1_PORT} \
            --port ${COMPUTE_1_PORT} \
            --image "Ubuntu 24.04" \
            --key-name hyperconverged-key \
            --flavor ${OS_FLAVOR}
fi

if ! openstack server show hyperconverged-2; then
  openstack server create hyperconverged-2 \
            --port ${WORKER_2_PORT} \
            --port ${COMPUTE_2_PORT} \
            --image "Ubuntu 24.04" \
            --key-name hyperconverged-key \
            --flavor ${OS_FLAVOR}
fi

COUNT=0
while ! ssh -o UserKnownHostsFile=/dev/null -q ubuntu@${JUMP_HOST_VIP} exit; do
   sleep 2
   echo "SSH is not ready, Trying again..."
   COUNT=$((COUNT+1))
   if [ $COUNT -gt 30 ]; then
     echo "Failed to ssh into the jump host"
     exit 1
   fi
done

# Run bootstrap
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
if [ -f ~/.venvs/genestack/bin/pip ]; then
  exit 0
fi
# SSH into the floating ip address of the hyperconverged-0 server
sudo git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
sudo /opt/genestack/bootstrap.sh
sudo chown \${USER}:\${USER} -R /etc/genestack

cat > /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml <<EOF
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-external
  namespace: metallb-system
spec:
  addresses:
    - ${METAL_LB_IP}/32  # This is assumed to be the public LB vip address
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: openstack-external-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-external
EOF

cat > /etc/genestack/inventory/inventory.yaml <<EOF
---
all:
  vars:
    cloud_name: "hyperconverged-lab-0"
    ansible_python_interpreter: "/usr/bin/python3"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  hosts:
    hyperconverged-0.${GATEWAY_DOMAIN}:
      ansible_host: $(openstack port show ${WORKER_0_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
    hyperconverged-1.${GATEWAY_DOMAIN}:
      ansible_host: $(openstack port show ${WORKER_1_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
    hyperconverged-2.${GATEWAY_DOMAIN}:
      ansible_host: $(openstack port show ${WORKER_2_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
  children:
    k8s_cluster:
      vars:
        cluster_name: cluster.local
        kube_ovn_central_hosts: '{{ groups["ovn_network_nodes"] }}'
        kube_ovn_default_interface_name: br-mgmt
        kube_ovn_iface: br-mgmt
      children:
        broken_etcd:
          children: null
        broken_kube_control_plane:
          children: null
        # OpenStack Controllers
        openstack_control_plane:
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        # Edge Nodes
        ovn_network_nodes:
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        # Tenant Prod Nodes
        openstack_compute_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        # Block Nodes
        storage_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          children:
            cinder_storage_nodes:
              hosts: {}
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        # ETCD Nodes
        etcd:
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        # Kubernetes Nodes
        kube_control_plane:
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
        kube_node:
          hosts:
            hyperconverged-0.${GATEWAY_DOMAIN}: null
            hyperconverged-1.${GATEWAY_DOMAIN}: null
            hyperconverged-2.${GATEWAY_DOMAIN}: null
EOF

if [ ! -f "/etc/genestack/helm-configs/barbican/barbican-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/barbican/barbican-helm-overrides.yaml <<EOF
---
conf:
  barbican_api_uwsgi:
    uwsgi:
      processes: 1
  barbican:
    oslo_messaging_notifications:
      driver: noop
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/cinder/cinder-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/cinder/cinder-helm-overrides.yaml <<EOF
---
conf:
  cinder:
    DEFAULT:
      osapi_volume_workers: 1
    oslo_messaging_notifications:
      driver: noop
  cinder_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/glance/glance-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/glance/glance-helm-overrides.yaml <<EOF
conf:
  glance:
    oslo_messaging_notifications:
      driver: noop
  glance_api_uwsgi:
    uwsgi:
      processes: 1
volume:
  class_name: general
  size: 20Gi
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/gnocchi/gnocchi-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/gnocchi/gnocchi-helm-overrides.yaml <<EOF
---
conf:
  gnocchi:
    metricd:
      workers: 1
  gnocchi_api_wsgi:
    wsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/heat/heat-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/heat/heat-helm-overrides.yaml <<EOF
---
conf:
  heat:
    DEFAULT:
      num_engine_workers: 1
    heat_api:
      workers: 1
    heat_api_cloudwatch:
      workers: 1
    heat_api_cfn:
      workers: 1
    oslo_messaging_notifications:
      driver: noop
  heat_api_cfn_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
  heat_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/keystone/keystone-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/keystone/keystone-helm-overrides.yaml <<EOF
---
conf:
  keystone_api_wsgi:
    wsgi:
      processes: 1
      threads: 1
  keystone:
    oslo_messaging_notifications:
      driver: noop
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/magnum/magnum-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/neutron/neutron-helm-overrides.yaml <<EOF
conf:
  neutron:
    DEFAULT:
      api_workers: 1
      rpc_workers: 1
      rpc_state_report_workers: 1
    oslo_messaging_notifications:
      driver: noop
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/magnum/magnum-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/magnum/magnum-helm-overrides.yaml <<EOF
conf:
  magnum_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/nova/nova-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml <<EOF
---
conf:
  nova:
    DEFAULT:
      osapi_compute_workers: 1
      metadata_workers: 1
    conductor:
      workers: 1
    schedule:
      workers: 1
    oslo_messaging_notifications:
      driver: noop
  nova_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
  nova_metadata_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/octavia/octavia-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/octavia/octavia-helm-overrides.yaml <<EOF
---
conf:
  octavia:
    DEFAULT:
      debug: true
    oslo_messaging_notifications:
      driver: noop
    controller_worker:
      loadbalancer_topology: SINGLE
      workers: 1
  octavia_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

if [ ! -f "/etc/genestack/helm-configs/placement/placement-helm-overrides.yaml" ]; then
cat > /etc/genestack/helm-configs/placement/placement-helm-overrides.yaml <<EOF
---
conf:
  placement:
    oslo_messaging_notifications:
      driver: noop
  placement_api_uwsgi:
    uwsgi:
      processes: 1
      threads: 1
EOF
fi

# Create the OVN interface
export CONTAINER_INTERFACE=\$(ip -details -json link show | jq -r '[.[] |
        if .linkinfo.info_kind // .link_type == "loopback" or (.ifname | test("idrac+")) then
            empty
        else
            .ifname
        end
    ] | .[0]')

cat > /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml <<EOF
networking:
  IFACE: "\${CONTAINER_INTERFACE}"
  vlan:
    VLAN_INTERFACE_NAME: "\${CONTAINER_INTERFACE}"
EOF
EOC

# Run host setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
python3 -m venv ~/.venvs/genestack
~/.venvs/genestack/bin/pip install -r /opt/genestack/requirements.txt
source /opt/genestack/scripts/genestack.rc
ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml --become
EOC

# Run K8S setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
if [ -d "/var/lib/kubelet" ]; then
  exit 0
fi
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/submodules/kubespray
ANSIBLE_SSH_PIPELINING=0 ansible-playbook cluster.yml --become
EOC

# Run K8S post setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
if [ ! -f "/usr/local/bin/kubectl" ]; then
  curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi
if [ ! -f "/usr/local/bin/kubectl-convert" ]; then
  curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
  sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
fi
if [ ! -f "/usr/local/bin/kubectl-ko" ]; then
  curl -LO https://raw.githubusercontent.com/kubeovn/kube-ovn/release-1.12/dist/images/kubectl-ko
  sudo install -o root -g root -m 0755 kubectl-ko /usr/local/bin/kubectl-ko
fi
EOC

# Run K8s Label setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
sudo kubectl label node --all openstack-control-plane=enabled \
                              openstack-compute-node=enabled \
                              openstack-network-node=enabled \
                              openstack-storage-node=enabled \
                              node-role.kubernetes.io/worker=worker

sudo kubectl label node -l beta.kubernetes.io/os=linux kubernetes.io/os=linux
sudo kubectl label node -l node-role.kubernetes.io/control-plane kube-ovn/role=master
sudo kubectl label node -l ovn.kubernetes.io/ovs_dp_type!=userspace ovn.kubernetes.io/ovs_dp_type=kernel
sudo kubectl label node -l node-role.kubernetes.io/control-plane longhorn.io/storage-node=enabled

if ! sudo kubectl taint nodes -l node-role.kubernetes.io/control-plane node-role.kubernetes.io/control-plane:NoSchedule-; then
  echo "Taint already removed"
fi

export COMPUTE_INTERFACE=\$(ip -details -json link show | jq -r '[.[] |
        if .linkinfo.info_kind // .link_type == "loopback" or (.ifname | test("idrac+")) then
            empty
        else
            .ifname
        end
    ] | .[-1]')
sudo kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/int_bridge='br-int'
sudo kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/bridges='br-ex'
sudo kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/ports="br-ex:\${COMPUTE_INTERFACE}"
sudo kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/mappings='physnet1:br-ex'
sudo kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/availability_zones='az1'
sudo kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/gateway='enabled'
EOC

# Run Core K8S Components setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
sudo /opt/genestack/bin/install-kube-ovn.sh
sudo kubectl -n kube-system wait --timeout=5m deployments.app/kube-ovn-controller --for=condition=available
sudo kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-namespace.yaml
sudo /opt/genestack/bin/install-longhorn.sh
sudo sed -i 's/numberOfReplicas.*/numberOfReplicas: "1"/g' /etc/genestack/manifests/longhorn/longhorn-general-storageclass.yaml
sudo kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-general-storageclass.yaml
EOC

# Run Genestack Infrastucture setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
sudo /opt/genestack/bin/install-prometheus.sh
sudo kubectl apply -f /etc/genestack/manifests/metallb/metallb-namespace.yaml
sudo /opt/genestack/bin/install-metallb.sh
echo "Waiting for the metallb-controller to be available"
sudo kubectl -n metallb-system wait --timeout=5m deployments.apps/metallb-controller --for=condition=available
sudo kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
sudo kubectl apply -k /etc/genestack/kustomize/openstack
sudo /opt/genestack/bin/install-envoy-gateway.sh
echo "Waiting for the envoy-gateway to be available"
sudo kubectl -n envoyproxy-gateway-system wait --timeout=5m deployments.apps/envoy-gateway --for=condition=available
sudo GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" ACME_EMAIL="${ACME_EMAIL}" /opt/genestack/bin/setup-envoy-gateway.sh
echo "Waiting for the cert-manager to be available"
sudo kubectl -n cert-manager wait --timeout=5m deployments.apps cert-manager --for=condition=available
sudo /opt/genestack/bin/create-secrets.sh
if ! sudo kubectl create -f /etc/genestack/kubesecrets.yaml; then
  echo "Secrets already created"
fi
sudo /opt/genestack/bin/install-mariadb-operator.sh
sudo kubectl apply -k /etc/genestack/kustomize/rabbitmq-operator
sudo kubectl apply -k /etc/genestack/kustomize/rabbitmq-topology-operator
echo "Waiting for the mariadb-operator-webhook to be available"
if ! sudo kubectl -n mariadb-system wait --timeout=1m deployments.apps mariadb-operator-webhook --for=condition=available; then
  echo "Recycling the mariadb-operator pods because sometimes they're stupid"
  sudo kubectl -n mariadb-system get pods -o name | xargs sudo kubectl -n mariadb-system delete
  sudo kubectl -n mariadb-system wait --timeout=5m deployments.apps mariadb-operator-webhook --for=condition=available
fi
sudo kubectl -n openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
echo "Waiting for the rabbitmq-cluster-operator to be available"
sudo kubectl -n rabbitmq-system wait --timeout=5m deployments.apps rabbitmq-cluster-operator --for=condition=available
sudo kubectl apply -k /etc/genestack/kustomize/rabbitmq-cluster/overlay
sudo kubectl apply -k /etc/genestack/kustomize/ovn
sudo /opt/genestack/bin/install-memcached.sh
sudo /opt/genestack/bin/install-libvirt.sh
EOC

# Run Genestack OpenStack Setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
sudo /opt/genestack/bin/install-keystone.sh
pids=()
sudo /opt/genestack/bin/install-glance.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-heat.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-barbican.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-cinder.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-placement.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-nova.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-neutron.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-magnum.sh &
pids+=(\$!)
sudo /opt/genestack/bin/install-octavia.sh &
pids+=(\$!)
for pid in \${pids[*]}; do
    wait \${pid}
done
sudo /opt/genestack/bin/install-skyline.sh
EOC

# Run Genestack post setup
ssh -o UserKnownHostsFile=/dev/null -t ubuntu@${JUMP_HOST_VIP} <<EOC
set -e
mkdir -p ~/.config/openstack
cat >  ~/.config/openstack/clouds.yaml <<EOF
cache:
  auth: true
  expiration_time: 3600
clouds:
  default:
    auth:
      auth_url: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)
      project_name: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_NAME}' | base64 -d)
      tenant_name: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
      project_domain_name: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_DOMAIN_NAME}' | base64 -d)
      username: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USERNAME}' | base64 -d)
      password: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)
      user_domain_name: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
    region_name: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_REGION_NAME}' | base64 -d)
    interface: \$(sudo kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_INTERFACE}' | base64 -d)
    identity_api_version: "3"
EOF
source /opt/genestack/scripts/genestack.rc
openstack --os-cloud default flavor create hyperconverged-test \
          --public \
          --ram 2048 \
          --disk 10 \
          --vcpus 2
openstack --os-cloud default network create \
          --share \
          --availability-zone-hint az1 \
          --external \
          --provider-network-type flat \
          --provider-physical-network physnet1 \
          flat
openstack --os-cloud default subnet create \
          --subnet-range 192.168.102.0/24 \
          --gateway 192.168.102.1 \
          --dns-nameserver 1.1.1.1 \
          --allocation-pool start=192.168.102.100,end=192.168.102.200 \
          --dhcp \
          --network flat \
          flat_subnet
EOC

echo "This is the jump host address ${JUMP_HOST_VIP}, write this down."
echo "This is the VIP address internally ${METAL_LB_IP} with public address ${METAL_LB_VIP} within MetalLB, write this down."
