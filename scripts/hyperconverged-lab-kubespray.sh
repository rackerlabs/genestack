#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Script for Kubespray
#
# This script deploys a fully automated Ubuntu-based Kubernetes cluster
# using Kubespray for running Genestack (OpenStack on Kubernetes) in a
# hyperconverged configuration.
#
# Platform: Ubuntu with Kubespray
# Kubernetes Setup: Kubespray via Ansible
# SSH Access: Required for remote node configuration
#

set -o pipefail
set -e
SECONDS=0

# Source common library
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/lib/hyperconverged-common.sh"

#############################################################################
# Initialize
#############################################################################

ensureYq
parseCommonArgs "$@"
promptForCommonInputs

#############################################################################
# Ubuntu/Kubespray-Specific: Image and SSH Configuration
#############################################################################

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

#############################################################################
# Create OpenStack Infrastructure (Common)
#############################################################################

createRouter
createNetworks
createCommonSecurityGroups

#############################################################################
# Kubespray-Specific: Jump Host Security Group
#############################################################################

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup 2>/dev/null; then
    openstack security group create ${LAB_NAME_PREFIX}-jump-secgroup
fi

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules.[].port_range_max' | grep -q 22; then
    openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
        --protocol tcp \
        --ingress \
        --remote-ip 0.0.0.0/0 \
        --dst-port 22 \
        --description "ssh"
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules.[].protocol' | grep -q icmp; then
    openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
        --protocol icmp \
        --ingress \
        --remote-ip 0.0.0.0/0 \
        --description "ping"
fi

#############################################################################
# Create Ports and Floating IPs
#############################################################################

createMetalLBPort

# Create management ports with jump host security group on first node
if ! WORKER_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id 2>/dev/null); then
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
export WORKER_0_PORT

if ! WORKER_1_PORT=$(openstack port show ${LAB_NAME_PREFIX}-1-mgmt-port -f value -c id 2>/dev/null); then
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
export WORKER_1_PORT

if ! WORKER_2_PORT=$(openstack port show ${LAB_NAME_PREFIX}-2-mgmt-port -f value -c id 2>/dev/null); then
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
export WORKER_2_PORT

# Create floating IP for jump host (first node)
if ! JUMP_HOST_VIP=$(openstack floating ip list --port ${WORKER_0_PORT} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${JUMP_HOST_VIP}" ]; then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
fi
export JUMP_HOST_VIP

createComputePorts

#############################################################################
# Kubespray-Specific: SSH Key Management
#############################################################################

if [ ! -d "~/.ssh" ]; then
    echo "Creating the SSH directory"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
fi
if ! openstack keypair show ${LAB_NAME_PREFIX}-key 2>/dev/null; then
    if [ ! -f ~/.ssh/${LAB_NAME_PREFIX}-key.pem ]; then
        openstack keypair create ${LAB_NAME_PREFIX}-key >~/.ssh/${LAB_NAME_PREFIX}-key.pem
        chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem
        openstack keypair show ${LAB_NAME_PREFIX}-key --public-key >~/.ssh/${LAB_NAME_PREFIX}-key.pub
    else
        if [ -f ~/.ssh/${LAB_NAME_PREFIX}-key.pub ]; then
            openstack keypair create ${LAB_NAME_PREFIX}-key --public-key ~/.ssh/${LAB_NAME_PREFIX}-key.pub
        fi
    fi
fi

ssh-add ~/.ssh/${LAB_NAME_PREFIX}-key.pem

#############################################################################
# Create Lab Instances
#############################################################################

if ! openstack server show ${LAB_NAME_PREFIX}-0 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-0 \
        --port ${WORKER_0_PORT} \
        --port ${COMPUTE_0_PORT} \
        --image "${OS_IMAGE}" \
        --key-name ${LAB_NAME_PREFIX}-key \
        --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-1 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-1 \
        --port ${WORKER_1_PORT} \
        --port ${COMPUTE_1_PORT} \
        --image "${OS_IMAGE}" \
        --key-name ${LAB_NAME_PREFIX}-key \
        --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-2 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-2 \
        --port ${WORKER_2_PORT} \
        --port ${COMPUTE_2_PORT} \
        --image "${OS_IMAGE}" \
        --key-name ${LAB_NAME_PREFIX}-key \
        --flavor ${OS_FLAVOR}
fi

#############################################################################
# Wait for Jump Host SSH Access
#############################################################################

echo "Waiting for the jump host to be ready"
COUNT=0
while ! ssh -o ConnectTimeout=2 -o ConnectionAttempts=3 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q ${SSH_USERNAME}@${JUMP_HOST_VIP} exit; do
    sleep 2
    echo "SSH is not ready, Trying again..."
    COUNT=$((COUNT + 1))
    if [ $COUNT -gt 60 ]; then
        echo "Failed to ssh into the jump host"
        exit 1
    fi
done

#############################################################################
# Kubespray-Specific: Development Mode Source Copy
#############################################################################

if [ "${HYPERCONVERGED_DEV:-false}" = "true" ]; then
    if [ ! -d "${SCRIPT_DIR}" ]; then
        echo "HYPERCONVERGED_DEV is true, but we've failed to determine the base genestack directory"
        exit 1
    fi
    # NOTE: we are assuming an Ubuntu (apt) based instance here
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
        "while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do echo 'Waiting for apt locks to be released...'; sleep 5; done && sudo apt-get update && sudo apt install -y rsync git"
    echo "Copying the development source code to the jump host"
    rsync -az \
        -e "ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
        --rsync-path="sudo rsync" \
        $(readlink -fn ${SCRIPT_DIR}/../) ${SSH_USERNAME}@${JUMP_HOST_VIP}:/opt/
fi

#############################################################################
# Kubespray-Specific: Remote Configuration via SSH
#############################################################################

ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
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

# Configure MetalLB
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

# Create Kubespray inventory
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
            storage_network_multipath: false
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

EOC

#############################################################################
# Write Service Helm Overrides and Endpoints (common function)
#############################################################################

configureGenestackRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${METAL_LB_IP}" "${GATEWAY_DOMAIN}"

#############################################################################
# Kubespray-Specific: Run Host Setup and Kubespray
#############################################################################

ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
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
        curl -LO https://raw.githubusercontent.com/kubeovn/kube-ovn/refs/heads/release-1.12/dist/images/kubectl-ko
        sudo install -o root -g root -m 0755 kubectl-ko /usr/local/bin/kubectl-ko
    fi
popd
EOC

#############################################################################
# Run Genestack Infrastructure Setup (common function)
#############################################################################

runGenestackSetupRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${GATEWAY_DOMAIN}" "${ACME_EMAIL}"

#############################################################################
# Extra Operations
#############################################################################

install_preconf_octavia() {
    echo "Installing Octavia preconf"
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} << 'EOC'
set -e

if [ ! -f ~/.config/openstack ]; then
    sudo mkdir -p ~/.config/openstack
    sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack
    sudo chown $(id -u):$(id -g) ~/.config
fi

source ~/.venvs/genestack/bin/activate

OCTAVIA_HELM_FILE=/tmp/octavia_helm_overrides.yaml

ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
    -e octavia_os_password=$(/usr/local/bin/kubectl get secrets keystone-admin -n openstack -o jsonpath='{.data.password}' | base64 -d) \
    -e octavia_os_region_name=$(sudo ~/.venvs/genestack/bin/openstack --os-cloud=default endpoint list --service keystone --interface internal -c Region -f value) \
    -e octavia_os_auth_url=$(sudo ~/.venvs/genestack/bin/openstack --os-cloud=default endpoint list --service keystone --interface internal -c URL -f value) \
    -e octavia_os_endpoint_type=internal \
    -e octavia_helm_file=$OCTAVIA_HELM_FILE \
    -e interface=internal \
    -e endpoint_type=internal

echo "Installing Octavia"
sudo /opt/genestack/bin/install-octavia.sh -f $OCTAVIA_HELM_FILE
EOC
}

if [[ "$RUN_EXTRAS" -eq 1 ]]; then
    echo "Running extra operations..."
    installK9sRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
    install_preconf_octavia
fi

#############################################################################
# Post-Setup and Tests
#############################################################################

# Wait for Nova and Neutron APIs to be ready before proceeding
waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"

if [[ "${TEST_LEVEL}" == "off" ]]; then
    createPostSetupResourcesRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}"
else
    echo "Running tests at level: ${TEST_LEVEL}"

    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
        "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"

    mkdir -p test-results
    scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.xml ./test-results/ 2>/dev/null || echo "No test result XML files found"
    scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.txt ./test-results/ 2>/dev/null || echo "No test result text files found"
fi

#############################################################################
# Output Summary
#############################################################################

{ cat | tee /tmp/output.txt; } <<EOF
================================================================================
Kubespray Hyperconverged Lab Deployment Complete!
================================================================================

Deployment took ${SECONDS} seconds to complete.

Cluster Information:
  - Jump Host Address: ${JUMP_HOST_VIP}
  - MetalLB Internal IP: ${METAL_LB_IP}
  - MetalLB Public VIP: ${METAL_LB_VIP}

SSH Access:
  ssh ${SSH_USERNAME}@${JUMP_HOST_VIP}

Kubernetes Access (from jump host):
  kubectl get nodes

Important Notes:
  - This is a Kubespray deployment
  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem
  - All cluster operations should be performed from the jump host

Write these addresses down for future reference!
================================================================================
EOF
