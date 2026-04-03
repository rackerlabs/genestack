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

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 22; then
    openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
        --protocol tcp \
        --ingress \
        --remote-ip 0.0.0.0/0 \
        --dst-port 22 \
        --description "ssh"
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules[].protocol' | grep -q icmp; then
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
# Resolve Worker IPs from Management Ports
#############################################################################

WORKER_0_IP=$(openstack port show ${WORKER_0_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
WORKER_1_IP=$(openstack port show ${WORKER_1_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
WORKER_2_IP=$(openstack port show ${WORKER_2_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
export WORKER_0_IP WORKER_1_IP WORKER_2_IP

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
#export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

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
# Copy SSH Keys to Jump Host
#############################################################################

echo "Copying SSH keys to jump host..."
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pem \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pub \
    ${SSH_USERNAME}@${JUMP_HOST_VIP}:/home/${SSH_USERNAME}/.ssh/
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP} \
    "chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem && chmod 644 ~/.ssh/${LAB_NAME_PREFIX}-key.pub"

echo "Writing SSH config on jump host..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP} <<SSHCFG
cat > ~/.ssh/config <<'EOF'
Host *
    User ubuntu
    ForwardAgent yes
    ForwardX11Trusted yes
    AddKeysToAgent yes
    IdentitiesOnly yes
    IdentityFile /home/${SSH_USERNAME}/.ssh/${LAB_NAME_PREFIX}-key.pem
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ProxyCommand none
    TCPKeepAlive yes
    ServerAliveInterval 300
    Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc
    MACs hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com
    KexAlgorithms +diffie-hellman-group1-sha1
EOF
chmod 600 ~/.ssh/config
SSHCFG

echo "Updating /etc/hosts on jump host..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP} <<ETCHOSTS
# Remove any previous block, then write a fresh one (idempotent)
sudo sed -i '/^# BEGIN hyperconverged lab nodes/,/^# END hyperconverged lab nodes/d' /etc/hosts
sudo tee -a /etc/hosts >/dev/null <<'EOF'
# BEGIN hyperconverged lab nodes
${WORKER_0_IP} ${LAB_NAME_PREFIX}-0.cluster.local ${LAB_NAME_PREFIX}-0
${WORKER_1_IP} ${LAB_NAME_PREFIX}-1.cluster.local ${LAB_NAME_PREFIX}-1
${WORKER_2_IP} ${LAB_NAME_PREFIX}-2.cluster.local ${LAB_NAME_PREFIX}-2
# END hyperconverged lab nodes
EOF
ETCHOSTS

#############################################################################
# Create and Attach Lab Volumes
#############################################################################

# Create and attach cinder volumes if cinder is in the include list
INSTALL_CINDER_VOLUMES=false
for _svc in "${INCLUDE_LIST[@]}"; do
    [ "$_svc" = "cinder" ] && INSTALL_CINDER_VOLUMES=true
done

if [ "${INSTALL_CINDER_VOLUMES}" = "true" ]; then
    READY_COUNT=0
    while [ $(openstack server show ${LAB_NAME_PREFIX}-0 -f yaml | yq '.status') != 'ACTIVE' ]; do
      echo "Server instance 0 is not ready, waiting..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "VM: ${LAB_NAME_PREFIX}-0 never built"
        exit 1
      fi
    done

    READY_COUNT=0
    while [ $(openstack server show ${LAB_NAME_PREFIX}-1 -f yaml | yq '.status') != 'ACTIVE' ]; do
      echo "Server instance 1 is not ready, waiting..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "VM: ${LAB_NAME_PREFIX}-1 never built"
        exit 1
      fi
    done

    READY_COUNT=0
    while [ $(openstack server show ${LAB_NAME_PREFIX}-2 -f yaml | yq '.status') != 'ACTIVE' ]; do
      echo "Server instance 2 is not ready, waiting..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "VM: ${LAB_NAME_PREFIX}-2 never built"
        exit 1
      fi
    done

    if ! openstack volume show ${LAB_NAME_PREFIX}-0-cv1 2>/dev/null; then
      openstack volume create \
        --size 200 \
        --type Performance \
        --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-0" \
        ${LAB_NAME_PREFIX}-0-cv1
    fi

    if ! openstack volume show ${LAB_NAME_PREFIX}-1-cv1 2>/dev/null; then
      openstack volume create \
        --size 200 \
        --type Performance \
        --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-1" \
        ${LAB_NAME_PREFIX}-1-cv1
    fi

    if ! openstack volume show ${LAB_NAME_PREFIX}-2-cv1 2>/dev/null; then
      openstack volume create \
        --size 200 \
        --type Performance \
        --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-2" \
        ${LAB_NAME_PREFIX}-2-cv1
    fi

    sleep 2

    READY_COUNT=0
    while [[ ! $(openstack volume show ${LAB_NAME_PREFIX}-0-cv1 -f yaml | yq '.status') =~ ^(available|in-use)$ ]]; do
      sleep 0.2
      echo "Data volume 0 is not ready, Trying again..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "Volume: ${LAB_NAME_PREFIX}-0-cv1 not built"
        exit 1
      fi
    done

    READY_COUNT=0
    while [[ ! $(openstack volume show ${LAB_NAME_PREFIX}-1-cv1 -f yaml | yq '.status') =~ ^(available|in-use)$ ]]; do
      sleep 0.2
      echo "Data volume 1 is not ready, Trying again..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "Volume: ${LAB_NAME_PREFIX}-1-cv1 not built"
        exit 1
      fi
    done

    READY_COUNT=0
    while [[ ! $(openstack volume show ${LAB_NAME_PREFIX}-2-cv1 -f yaml | yq '.status') =~ ^(available|in-use)$ ]]; do
      sleep 0.2
      echo "Data volume 2 is not ready, Trying again..."
      READY_COUNT=$((READY_COUNT + 1))
      if [ $READY_COUNT -gt 200 ]; then
        echo "Volume: ${LAB_NAME_PREFIX}-2-cv1 not built"
        exit 1
      fi
    done

    if [ $(openstack volume show ${LAB_NAME_PREFIX}-0-cv1 -f yaml | yq '.status') == 'available' ]; then
      openstack server add volume \
        --enable-delete-on-termination \
        ${LAB_NAME_PREFIX}-0 \
        ${LAB_NAME_PREFIX}-0-cv1
    else
        echo "Data volume 0 is not available"
    fi

    if [ $(openstack volume show ${LAB_NAME_PREFIX}-1-cv1 -f yaml | yq '.status') == 'available' ]; then
      openstack server add volume \
        --enable-delete-on-termination \
        ${LAB_NAME_PREFIX}-1 \
        ${LAB_NAME_PREFIX}-1-cv1
    else
        echo "Data volume 1 is not available"
    fi

    if [ $(openstack volume show ${LAB_NAME_PREFIX}-2-cv1 -f yaml | yq '.status') == 'available' ]; then
      openstack server add volume \
        --enable-delete-on-termination \
        ${LAB_NAME_PREFIX}-2 \
        ${LAB_NAME_PREFIX}-2-cv1
    else
        echo "Data volume 2 is not available"
    fi

    sleep 2
fi

#############################################################################
# Kubespray-Specific: Bootstrap and deploy codebase on Jump Host
#############################################################################

prepareJumpHostSource

#############################################################################
# Kubespray-Specific: Remote Configuration via SSH
#############################################################################

ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
if [ ! -d "/etc/genestack" ]; then
    sudo /opt/genestack/bootstrap.sh
    sudo chown \${USER}:\${USER} -R /etc/genestack
fi

# Create Kubespray inventory (needed before host-setup; ansible not yet available)
if [ ! -f "/etc/genestack/inventory/inventory.yaml" ]; then
    if [ "${INSTALL_CINDER_VOLUMES}" = "true" ]; then
        cat > /etc/genestack/inventory/inventory.yaml <<EOF
---
all:
  vars:
    cloud_name: "${LAB_NAME_PREFIX}-lab-0"
    ansible_python_interpreter: "/usr/bin/python3"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  hosts:
    ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_0_IP}
    ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_1_IP}
    ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_2_IP}
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
        openstack_control_plane:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        ovn_network_nodes:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        openstack_compute_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        storage_nodes:
          vars:
            enable_iscsi: true
            storage_network_multipath: false
          children:
            cinder_storage_nodes:
              hosts:
                ${LAB_NAME_PREFIX}-0.cluster.local: null
                ${LAB_NAME_PREFIX}-1.cluster.local: null
                ${LAB_NAME_PREFIX}-2.cluster.local: null
          hosts:
            ${LAB_NAME_PREFIX}-0.cluster.local: null
            ${LAB_NAME_PREFIX}-1.cluster.local: null
            ${LAB_NAME_PREFIX}-2.cluster.local: null
        etcd:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
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
    else
        cat > /etc/genestack/inventory/inventory.yaml <<EOF
---
all:
  vars:
    cloud_name: "${LAB_NAME_PREFIX}-lab-0"
    ansible_python_interpreter: "/usr/bin/python3"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  hosts:
    ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_0_IP}
    ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_1_IP}
    ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}:
      ansible_host: ${WORKER_2_IP}
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
        openstack_control_plane:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        ovn_network_nodes:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        openstack_compute_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: false
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
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
        etcd:
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
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
fi

EOC

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
# Configure OpenStack Services via Ansible Role
# (MetalLB, Helm overrides, endpoints, openstack-components)
# Runs after venv/ansible is available, before infrastructure setup.
#############################################################################

INCLUDE_JSON=$(printf '%s\n' "${INCLUDE_LIST[@]}" | jq -R 'select(length > 0)' | jq -s -c .)
EXCLUDE_JSON=$(printf '%s\n' "${EXCLUDE_LIST[@]}" | jq -R 'select(length > 0)' | jq -s -c .)

# Determine which services need deferred install.
# Manila, Octavia, and Trove require pre-configuration that depends on
# Keystone/Neutron/Glance, so they are opt-in only via -i.
# Manila and Trove depend on cinder — if either is included and cinder is
# in the exclude list, override the exclusion so the cinder API is available.
INSTALL_MANILA=false
INSTALL_OCTAVIA=false
INSTALL_TROVE=false
for _svc in "${INCLUDE_LIST[@]}"; do
    [ "$_svc" = "manila" ]  && INSTALL_MANILA=true
    [ "$_svc" = "octavia" ] && INSTALL_OCTAVIA=true
    [ "$_svc" = "trove" ]   && INSTALL_TROVE=true
done

# Cinder dependency: Manila and Trove need the cinder API.
# If either is enabled and cinder was explicitly excluded, remove cinder
# from the exclude list so the lightweight API is still deployed.
# Trove additionally requires full cinder LVM volume infrastructure.
if [ "${INSTALL_MANILA}" = "true" ] || [ "${INSTALL_TROVE}" = "true" ]; then
    _new_exclude=()
    for _svc in "${EXCLUDE_LIST[@]}"; do
        if [ "$_svc" = "cinder" ]; then
            echo "WARNING: Removing cinder from exclude list — required by manila/trove"
        else
            _new_exclude+=("$_svc")
        fi
    done
    EXCLUDE_LIST=("${_new_exclude[@]}")
    EXCLUDE_JSON=$(printf '%s\n' "${EXCLUDE_LIST[@]}" | jq -R 'select(length > 0)' | jq -s -c .)
fi

# Manila and Trove may need full cinder LVM for volume-backed operations.
# The cinder API is always available (lightweight mode), but PV/VG creation,
# cinder-volume services, and volume types require '-i cinder'.
if { [ "${INSTALL_MANILA}" = "true" ] || [ "${INSTALL_TROVE}" = "true" ]; } && [ "${INSTALL_CINDER_VOLUMES}" = "false" ]; then
    echo "NOTE: manila/trove included without '-i cinder'. Cinder API is available but"
    echo "      full LVM volume infrastructure is not. Add '-i cinder' if volume-backed"
    echo "      operations are needed."
fi

echo "Deferred install — Manila: ${INSTALL_MANILA}, Octavia: ${INSTALL_OCTAVIA}, Trove: ${INSTALL_TROVE}"
echo "Cinder volume mode: ${INSTALL_CINDER_VOLUMES}"

echo "Running service configuration role on jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
cat > /tmp/_hclab_svc_lists.json <<SJEOF
{"include_services": ${INCLUDE_JSON}, "exclude_services": ${EXCLUDE_JSON}}
SJEOF
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags metallb,helm_overrides,endpoints,openstack_components \
    -e metal_lb_ip=${METAL_LB_IP} \
    -e gateway_domain=${GATEWAY_DOMAIN} \
    -e hyperconverged_cinder_volume=${INSTALL_CINDER_VOLUMES} \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e run_manila_preconf=${INSTALL_MANILA} \
    -e run_octavia_preconf=${INSTALL_OCTAVIA} \
    -e run_trove_preconf=${INSTALL_TROVE} \
    -e @/tmp/_hclab_svc_lists.json
rm -f /tmp/_hclab_svc_lists.json
EOC

#############################################################################
# Run Genestack Infrastructure Setup (K8s infra, MariaDB, RabbitMQ, etc.)
#############################################################################

echo "Installing OpenStack Infrastructure on jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc

# Reset gateway listeners to the base pair before setup-infrastructure runs.
# setup-envoy-gateway.sh uses JSON-patch "add" (append) to add service listeners,
# so on reruns duplicate listeners cause a validation error. This trims back to
# just the two base listeners (cluster-http, cluster-tls) so appends are safe.
if kubectl -n envoy-gateway get gateway flex-gateway &>/dev/null; then
  echo "Resetting flex-gateway listeners to base pair for idempotent rerun"
  kubectl -n envoy-gateway get gateway flex-gateway -o json | \
    jq '.spec.listeners = [.spec.listeners[] | select(.name == "cluster-http" or .name == "cluster-tls")]' | \
    kubectl apply -f -
fi

echo "Installing OpenStack Infrastructure"
sudo LONGHORN_STORAGE_REPLICAS=1 \
     GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" \
     ACME_EMAIL="${ACME_EMAIL}" \
     HYPERCONVERGED=true \
     /opt/genestack/bin/setup-infrastructure.sh
EOC

#############################################################################
# Re-derive deferred install flags (same logic as above, after infra setup).
# Manila, Octavia, and Trove are opt-in via -i.
#############################################################################

INSTALL_MANILA=false
INSTALL_OCTAVIA=false
INSTALL_TROVE=false
for _svc in "${INCLUDE_LIST[@]}"; do
    [ "$_svc" = "manila" ]  && INSTALL_MANILA=true
    [ "$_svc" = "octavia" ] && INSTALL_OCTAVIA=true
    [ "$_svc" = "trove" ]   && INSTALL_TROVE=true
done

#############################################################################
# Manila K8s Secrets (pre-deploy)
# Only creates K8s secrets — no OpenStack access needed, just kubectl.
# Must run before setup-openstack.sh so the secrets exist when the Manila
# Helm chart is installed.
#############################################################################

if [ "${DISABLE_OPENSTACK}" = "false" ] && [ "${INSTALL_MANILA}" = "true" ]; then
    echo "Creating Manila K8s secrets on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_preconf_secrets \
    -e run_manila_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

#############################################################################
# Install OpenStack Services
# Manila and Octavia are forced to false in openstack-components.yaml by
# the Ansible role (they need preconf after Keystone). All other services
# deploy in parallel via setup-openstack.sh.
#############################################################################

if [ "${DISABLE_OPENSTACK}" = "false" ]; then
    echo "Installing OpenStack services on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
echo "Installing OpenStack services"
# setup-openstack.sh may exit non-zero if its last component check
# (e.g. skyline) is disabled; this is benign so we catch it here.
sudo /opt/genestack/bin/setup-openstack.sh || {
    echo "Warning: setup-openstack.sh exited with code \$?, continuing..."
}
sudo /opt/genestack/bin/setup-openstack-rc.sh
EOC
fi

#############################################################################
# Octavia Pre-Configuration (amphora provider setup)
# Now that Keystone is deployed, we can query endpoints and generate the
# Octavia helm overrides. Writes to the helm-configs directory so
# install-octavia.sh picks them up automatically.
#############################################################################

if [ "${DISABLE_OPENSTACK}" = "false" ] && [ "${INSTALL_OCTAVIA}" = "true" ]; then
    echo "Running Octavia pre-configuration on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<'EOC'
set -e
source /opt/genestack/scripts/genestack.rc

OCTAVIA_HELM_FILE=/etc/genestack/helm-configs/octavia/octavia-preconf-overrides.yaml

ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
    -e octavia_os_password=$(kubectl get secrets keystone-admin -n openstack -o jsonpath='{.data.password}' | base64 -d) \
    -e octavia_os_region_name=$(sudo ~/.venvs/genestack/bin/openstack --os-cloud=default endpoint list --service keystone --interface internal -c Region -f value) \
    -e octavia_os_auth_url=$(sudo ~/.venvs/genestack/bin/openstack --os-cloud=default endpoint list --service keystone --interface internal -c URL -f value) \
    -e octavia_os_endpoint_type=internal \
    -e octavia_helm_file=$OCTAVIA_HELM_FILE \
    -e interface=internal \
    -e endpoint_type=internal
EOC
fi

#############################################################################
# Manila Pre-Configuration (service image, keypair, helm config merge)
# Now that Keystone and Glance are deployed, we can create the OpenStack
# keypair, build and upload the service image, and merge the driver config
# into the Manila helm overrides.
#############################################################################

if [ "${DISABLE_OPENSTACK}" = "false" ] && [ "${INSTALL_MANILA}" = "true" ]; then
    echo "Running Manila pre-configuration on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_preconf \
    -e run_manila_preconf=true \
    -e run_octavia_preconf=${INSTALL_OCTAVIA} \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

#############################################################################
# Install deferred services (Manila and/or Octavia)
# Both services now have their preconf overrides in place.
#############################################################################

if [ "${DISABLE_OPENSTACK}" = "false" ]; then
    DEFERRED_PIDS=()
    DEFERRED_NAMES=()

    if [ "${INSTALL_OCTAVIA}" = "true" ]; then
        echo "Installing Octavia on jump host..."
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
            "source /opt/genestack/scripts/genestack.rc && sudo /opt/genestack/bin/install-octavia.sh" &
        DEFERRED_PIDS+=($!)
        DEFERRED_NAMES+=("octavia")
    fi

    if [ "${INSTALL_MANILA}" = "true" ]; then
        echo "Installing Manila on jump host..."
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
            "source /opt/genestack/scripts/genestack.rc && sudo /opt/genestack/bin/install-manila.sh" &
        DEFERRED_PIDS+=($!)
        DEFERRED_NAMES+=("manila")
    fi

    for i in "${!DEFERRED_PIDS[@]}"; do
        wait "${DEFERRED_PIDS[$i]}" || {
            echo "ERROR: ${DEFERRED_NAMES[$i]} install failed (exit code $?)"
            exit 1
        }
        echo "${DEFERRED_NAMES[$i]} install complete"
    done
fi

#############################################################################
# Cinder Volume Setup via Ansible Role + Install Scripts
#############################################################################
if [ "${INSTALL_CINDER_VOLUMES}" = "true" ] && [ "${DISABLE_OPENSTACK}" = "false" ]; then
    # Run the ansible role for SSH config, /etc/hosts, and PV/VG on all nodes
    # (jump host SSH config is handled by the role's cinder/ssh_config.yml task)
    echo "Running cinder volume setup role on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags cinder \
    -e hyperconverged_cinder_volume=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e worker_0_ip=${WORKER_0_IP} \
    -e worker_1_ip=${WORKER_1_IP} \
    -e worker_2_ip=${WORKER_2_IP}
EOC

    # Run cinder volumes playbook and create volume type/QoS
    # NOTE: install-cinder.sh already ran inside setup-openstack.sh (parallel batch)
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc

echo "[JUMP_HOST] Running cinder volumes playbook (-f1 to avoid apt lock on delegated tasks)"
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e "cinder_storage_network_interface=ansible_enp3s0 cinder_storage_network_interface_secondary=ansible_enp3s0" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volumes-reference.yaml -f1

echo "[JUMP_HOST] Creating volume type and qos"
sudo ~/.venvs/genestack/bin/openstack --os-cloud=default volume type create \
    --description 'Standard with LUKS encryption' \
    --encryption-provider luks \
    --encryption-cipher aes-xts-plain64 \
    --encryption-key-size 256 \
    --encryption-control-location front-end \
    --property volume_backend_name=LVM_iSCSI \
    --property provisioning:max_vol_size='199' \
    --property provisioning:min_vol_size='1' \
    Standard
sudo ~/.venvs/genestack/bin/openstack --os-cloud=default volume qos create \
    --property read_iops_sec_per_gb='20' \
    --property write_iops_sec_per_gb='20' \
    Standard-Block
sudo ~/.venvs/genestack/bin/openstack --os-cloud=default volume qos associate Standard-Block Standard
sudo ~/.venvs/genestack/bin/openstack --os-cloud=default volume type set --private __DEFAULT__
EOC
fi

# NOTE: Manila, Octavia, and Trove are opt-in only (-i manila,octavia,trove).
# When included, they are deferred from setup-openstack.sh so their preconf
# can run after Keystone/Neutron are up. Manila and Trove depend on cinder
# (lightweight API at minimum). Trove requires the flat network (post_setup).

#############################################################################
# Extra Operations
#############################################################################

if [[ "$RUN_EXTRAS" -eq 1 ]]; then
    echo "Running extra operations..."
    installK9sRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
fi

#############################################################################
# Post-Setup and Tests
#############################################################################

if [ "${TEST_LEVEL}" = "off" ]; then
    # Wait for Nova and Neutron APIs to be ready before proceeding
    waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"

    # Create post-setup resources (flavor, flat network, subnet) and Manila share type
    echo "Running post-setup resources and Manila post-deploy on jump host..."
    ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags post_setup,manila_post_deploy \
    -e create_post_setup_resources=true \
    -e run_manila_preconf=${INSTALL_MANILA} \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC

    # Trove pre-configuration, install, and SSH key distribution
    # Must run after the flat network has been created (post_setup)
    if [ "${INSTALL_TROVE}" = "true" ]; then
        echo "Running Trove pre-configuration on jump host..."
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_preconf \
    -e run_trove_preconf=true \
    -e run_manila_preconf=${INSTALL_MANILA} \
    -e run_octavia_preconf=${INSTALL_OCTAVIA} \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC

        echo "Installing Trove on jump host..."
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
            "source /opt/genestack/scripts/genestack.rc && sudo /opt/genestack/bin/install-trove.sh"

        echo "Distributing Trove SSH key to nodes..."
        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_post_deploy \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
    fi

else
    # Wait for Nova and Neutron APIs to be ready before proceeding
    if [ ${DISABLE_OPENSTACK} = "false" ]; then
        waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"

        echo "Running tests at level: ${TEST_LEVEL}"

        ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} \
            "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"

        mkdir -p test-results
        scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.xml ./test-results/ 2>/dev/null || echo "No test result XML files found"
        scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.txt ./test-results/ 2>/dev/null || echo "No test result text files found"
    fi
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
