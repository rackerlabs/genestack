#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155

set -o pipefail
set -e
SECONDS=0
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
  # List compatible flavors
  FLAVORS=$(openstack flavor list --min-ram 16000 --min-disk 100 --sort-column Name -c Name -c RAM -c Disk -c VCPUs -f json)
  DEFAULT_OS_FLAVOR=$(echo "${FLAVORS}" | jq -r '[.[] | select( all(.RAM; . < 24576) )] | .[0].Name')
  echo "The following flavors are available for use with this build"
  echo "${FLAVORS}" | jq -r '["Name", "RAM", "Disk", "VCPUs"], (.[] | [.Name, .RAM, .Disk, .VCPUs]) | @tsv' | column -t
  read -rp "Enter name of the flavor to use for the instances [${DEFAULT_OS_FLAVOR}]: " OS_FLAVOR
  export OS_FLAVOR=${OS_FLAVOR:-${DEFAULT_OS_FLAVOR}}
fi

# Set the default image and ssh username
export OS_IMAGE="${OS_IMAGE:-Ubuntu 24.04}"
if [ -z "${SSH_USERNAME}" ]; then
  if ! IMAGE_DEFAULT_PROPERTY=$(openstack image show "${OS_IMAGE}" -f json -c properties); then
    read -rp "Image not found. Enter the image name: " OS_IMAGE
    IMAGE_DEFAULT_PROPERTY=$(openstack image show "${OS_IMAGE}" -f json -c properties)
  fi
  if [ "${IMAGE_DEFAULT_PROPERTY}" ]; then
    if SSH_USERNAME=$(echo "${IMAGE_DEFAULT_PROPERTY}" | jq -r '.properties.default_user'); then
      echo "Discovered the default username for the image ${OS_IMAGE} as ${SSH_USERNAME}"
    fi
  fi
  if [ -z "${SSH_USERNAME}" ] || [ "${SSH_USERNAME}" = "null" ]; then
    echo "The image ${OS_IMAGE} does not have a default user property, please enter the default username"
    read -rp "Enter the default username for the image: " SSH_USERNAME
  fi
fi

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"

if ! openstack router show ${LAB_NAME_PREFIX}-router 2> /dev/null; then
  openstack router create ${LAB_NAME_PREFIX}-router --external-gateway PUBLICNET
fi

if ! openstack network show ${LAB_NAME_PREFIX}-net 2> /dev/null; then
  openstack network create ${LAB_NAME_PREFIX}-net
fi

if ! TENANT_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-subnet -f json  2> /dev/null | jq -r '.id'); then
  echo "Creating the ${LAB_NAME_PREFIX}-subnet"
  TENANT_SUB_NETWORK_ID=$(
    openstack subnet create ${LAB_NAME_PREFIX}-subnet \
              --network ${LAB_NAME_PREFIX}-net \
              --subnet-range 192.168.100.0/24 \
              --dns-nameserver 1.1.1.1 \
              --dns-nameserver 1.0.0.1 \
              -f json | jq -r '.id'
  )
fi

if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2> /dev/null | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_SUB_NETWORK_ID}; then
  openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet
fi

if ! openstack network show ${LAB_NAME_PREFIX}-compute-net 2> /dev/null; then
  openstack network create ${LAB_NAME_PREFIX}-compute-net \
            --disable-port-security
fi

if ! TENANT_COMPUTE_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f json 2> /dev/null | jq -r '.id'); then
  echo "Creating the ${LAB_NAME_PREFIX}-compute-subnet"
  TENANT_COMPUTE_SUB_NETWORK_ID=$(
    openstack subnet create ${LAB_NAME_PREFIX}-compute-subnet \
              --network ${LAB_NAME_PREFIX}-compute-net \
              --subnet-range 192.168.102.0/24 \
              --no-dhcp -f json | jq -r '.id'
  )
fi

if ! openstack router show ${LAB_NAME_PREFIX}-router -f json | jq -r '.interfaces_info.[].subnet_id' | grep -q ${TENANT_COMPUTE_SUB_NETWORK_ID} 2> /dev/null; then
  openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup 2> /dev/null; then
  openstack security group create ${LAB_NAME_PREFIX}-http-secgroup
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2> /dev/null | jq -r '.rules.[].port_range_max' | grep -q 443; then
  openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 443 \
            --description "https"
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2> /dev/null | jq -r '.rules.[].port_range_max' | grep -q 80; then
  openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 80 \
            --description "http"
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup 2> /dev/null; then
  openstack security group create ${LAB_NAME_PREFIX}-secgroup
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup -f json 2> /dev/null | jq -r '.rules.[].description' | grep -q "all internal traffic"; then
  openstack security group rule create ${LAB_NAME_PREFIX}-secgroup \
            --protocol any \
            --ingress \
            --remote-ip 192.168.100.0/24 \
            --description "all internal traffic"
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup 2> /dev/null; then
  openstack security group create ${LAB_NAME_PREFIX}-jump-secgroup
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2> /dev/null | jq -r '.rules.[].port_range_max' | grep -q 22; then
  openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 22 \
            --description "ssh"
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2> /dev/null | jq -r '.rules.[].protocol' | grep -q icmp; then
  openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
            --protocol icmp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --description "ping"
fi

if ! METAL_LB_IP=$(openstack port show metallb-vip-0-port -f json 2> /dev/null | jq -r '.fixed_ips[0].ip_address'); then
  echo "Creating the MetalLB VIP port"
  METAL_LB_IP=$(openstack port create --security-group ${LAB_NAME_PREFIX}-http-secgroup --network ${LAB_NAME_PREFIX}-net metallb-vip-0-port -f json | jq -r '.fixed_ips[0].ip_address')
fi

METAL_LB_PORT_ID=$(openstack port show metallb-vip-0-port -f value -c id)

if ! METAL_LB_VIP=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f json  2> /dev/null | jq -r '.[]."Floating IP Address"'); then
  echo "Creating the MetalLB VIP floating IP"
  METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
elif [ -z "${METAL_LB_VIP}" ]; then
  METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
fi

if ! WORKER_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id 2> /dev/null); then
  export WORKER_0_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group ${LAB_NAME_PREFIX}-secgroup \
                          --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
                          --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                          --network ${LAB_NAME_PREFIX}-net \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-0-mgmt-port
  )
fi

if ! WORKER_1_PORT=$(openstack port show ${LAB_NAME_PREFIX}-1-mgmt-port -f value -c id 2> /dev/null); then
  export WORKER_1_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group ${LAB_NAME_PREFIX}-secgroup \
                          --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                          --network ${LAB_NAME_PREFIX}-net \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-1-mgmt-port
  )
fi

if ! WORKER_2_PORT=$(openstack port show ${LAB_NAME_PREFIX}-2-mgmt-port -f value -c id 2> /dev/null); then
  export WORKER_2_PORT=$(
    openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                          --security-group ${LAB_NAME_PREFIX}-secgroup \
                          --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                          --network ${LAB_NAME_PREFIX}-net \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-2-mgmt-port
  )
fi

if ! JUMP_HOST_VIP=$(openstack floating ip list --port ${WORKER_0_PORT} -f json 2> /dev/null | jq -r '.[]."Floating IP Address"'); then
  JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${JUMP_HOST_VIP}" ]; then
  JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
fi

echo "Creating pre-defined compute ports for the flat test network"
for i in {100..109}; do
  if ! openstack port show ${LAB_NAME_PREFIX}-0-compute-float-${i}-port 2> /dev/null; then
    openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                          --disable-port-security \
                          --fixed-ip ip-address="192.168.102.${i}" \
                          ${LAB_NAME_PREFIX}-0-compute-float-${i}-port
  fi
done

if ! COMPUTE_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-compute-port -f value -c id 2> /dev/null); then
  export COMPUTE_0_PORT=$(
    openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-0-compute-port
  )
fi

if ! COMPUTE_1_PORT=$(openstack port show ${LAB_NAME_PREFIX}-1-compute-port -f value -c id 2> /dev/null); then
  export COMPUTE_1_PORT=$(
    openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-1-compute-port
  )
fi

if ! COMPUTE_2_PORT=$(openstack port show ${LAB_NAME_PREFIX}-2-compute-port -f value -c id 2> /dev/null); then
  export COMPUTE_2_PORT=$(
    openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                          --no-fixed-ip \
                          --disable-port-security \
                          -f value \
                          -c id \
                          ${LAB_NAME_PREFIX}-2-compute-port
  )
fi

if ! openstack keypair show ${LAB_NAME_PREFIX}-key 2> /dev/null; then
    if [ ! -f ~/.ssh/${LAB_NAME_PREFIX}-key.pem ]; then
      openstack keypair create ${LAB_NAME_PREFIX}-key > ~/.ssh/${LAB_NAME_PREFIX}-key.pem
      chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem
      openstack keypair show ${LAB_NAME_PREFIX}-key --public-key > ~/.ssh/${LAB_NAME_PREFIX}-key.pub
    else
      if [ -f ~/.ssh/${LAB_NAME_PREFIX}-key.pub ]; then
        openstack keypair create ${LAB_NAME_PREFIX}-key --public-key ~/.ssh/${LAB_NAME_PREFIX}-key.pub
      fi
    fi
fi

ssh-add ~/.ssh/${LAB_NAME_PREFIX}-key.pem

# Create the three lab instances
if ! openstack server show ${LAB_NAME_PREFIX}-0 2> /dev/null; then
  openstack server create ${LAB_NAME_PREFIX}-0 \
            --port ${WORKER_0_PORT} \
            --port ${COMPUTE_0_PORT} \
            --image "${OS_IMAGE}" \
            --key-name ${LAB_NAME_PREFIX}-key \
            --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-1 2> /dev/null; then
  openstack server create ${LAB_NAME_PREFIX}-1 \
            --port ${WORKER_1_PORT} \
            --port ${COMPUTE_1_PORT} \
            --image "${OS_IMAGE}" \
            --key-name ${LAB_NAME_PREFIX}-key \
            --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-2 2> /dev/null; then
  openstack server create ${LAB_NAME_PREFIX}-2 \
            --port ${WORKER_2_PORT} \
            --port ${COMPUTE_2_PORT} \
            --image "${OS_IMAGE}" \
            --key-name ${LAB_NAME_PREFIX}-key \
            --flavor ${OS_FLAVOR}
fi

echo "Waiting for the jump host to be ready"
COUNT=0
while ! ssh -o ConnectTimeout=2 -o ConnectionAttempts=3 -o UserKnownHostsFile=/dev/null -q ${SSH_USERNAME}@${JUMP_HOST_VIP} exit; do
   sleep 2
   echo "SSH is not ready, Trying again..."
   COUNT=$((COUNT+1))
   if [ $COUNT -gt 30 ]; then
     echo "Failed to ssh into the jump host"
     exit 1
   fi
done

# Run bootstrap
if [ "${HYPERCONVERGED_DEV:-false}" = "true" ]; then
  export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "HYPERCONVERGED_DEV is true, but we've failed to determine the base genestack directory"
    exit 1
  fi
  ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
    "timeout 1m bash -c 'while ! sudo apt update; do sleep 2; done' && sudo apt install -y rsync git"
  echo "Copying the development source code to the jump host"
  rsync -az \
        -e "ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null" \
        --rsync-path="sudo rsync" \
        $(readlink -fn ${SCRIPT_DIR}/../) ${SSH_USERNAME}@${JUMP_HOST_VIP}:/opt/
fi

ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
if [ ! -d "/opt/genestack" ]; then
  sudo git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
else
  sudo git config --global --add safe.directory /opt/genestack
  pushd /opt/genestack
    sudo git submodule update --init --recursive
  popd
fi

if [ ! -d "/etc/genestack" ]; then
  sudo /opt/genestack/bootstrap.sh
  sudo chown \${USER}:\${USER} -R /etc/genestack
fi

if [ ! -f "/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml" ]; then
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
fi

if [ ! -f "/etc/genestack/inventory/inventory.yaml" ]; then
cat > /etc/genestack/inventory/inventory.yaml <<EOF
---
all:
  vars:
    cloud_name: "${LAB_NAME_PREFIX}-lab-0"
    ansible_python_interpreter: "/usr/bin/python3"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  hosts:
    ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}:
      ansible_host: $(openstack port show ${WORKER_0_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
    ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}:
      ansible_host: $(openstack port show ${WORKER_1_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
    ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}:
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
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Edge Nodes
        ovn_network_nodes:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Tenant Prod Nodes
        openstack_compute_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Block Nodes
        storage_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          children:
            cinder_storage_nodes:
              hosts: {}
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # ETCD Nodes
        etcd:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Kubernetes Nodes
        kube_control_plane:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        kube_node:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
EOF
fi

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
EOC

# Run host and K8S setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
if [ ! -f "/usr/local/bin/queue_max.sh" ]; then
  python3 -m venv ~/.venvs/genestack
  ~/.venvs/genestack/bin/pip install -r /opt/genestack/requirements.txt
  source /opt/genestack/scripts/genestack.rc
  ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml --become -e host_required_kernel=\$(uname -r)
fi
if [ ! -d "/var/lib/kubelet" ]; then
  source /opt/genestack/scripts/genestack.rc
  cd /opt/genestack/submodules/kubespray
  ANSIBLE_SSH_PIPELINING=0 ansible-playbook cluster.yml --become
fi
sudo mkdir -p /opt/kube-plugins
sudo chown \${USER}:\${USER} /opt/kube-plugins
pushd /opt/kube-plugins
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
popd
EOC

# Run Genestack Infrastucture/OpenStack Setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
echo "Installing OpenStack Infrastructure"
sudo LONGHORN_STORAGE_REPLICAS=1 \
     GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" \
     ACME_EMAIL="${ACME_EMAIL}" \
     HYPERCONVERGED=true \
     /opt/genestack/bin/setup-infrastructure.sh
echo "Installing OpenStack"
sudo /opt/genestack/bin/setup-openstack.sh
EOC

# Run Genestack post setup
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
sudo bash <<HERE
sudo /opt/genestack/bin/setup-openstack-rc.sh
source /opt/genestack/scripts/genestack.rc
if ! openstack --os-cloud default flavor show ${LAB_NAME_PREFIX}-test; then
  openstack --os-cloud default flavor create ${LAB_NAME_PREFIX}-test \
            --public \
            --ram 2048 \
            --disk 10 \
            --vcpus 2
fi
if ! openstack --os-cloud default network show flat; then
  openstack --os-cloud default network create \
            --share \
            --availability-zone-hint az1 \
            --external \
            --provider-network-type flat \
            --provider-physical-network physnet1 \
            flat
fi
if ! openstack --os-cloud default subnet show flat_subnet; then
  openstack --os-cloud default subnet create \
            --subnet-range 192.168.102.0/24 \
            --gateway 192.168.102.1 \
            --dns-nameserver 1.1.1.1 \
            --allocation-pool start=192.168.102.100,end=192.168.102.109 \
            --dhcp \
            --network flat \
            flat_subnet
fi
HERE
EOC

echo "The lab is now ready for use and took ${SECONDS} seconds to complete."
echo "This is the jump host address ${JUMP_HOST_VIP}, write this down."
echo "This is the VIP address internally ${METAL_LB_IP} with public address ${METAL_LB_VIP} within MetalLB, write this down."
