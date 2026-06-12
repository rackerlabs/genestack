#!/usr/bin/env bash
# Genestack setup/deploy functions
# Sourced from helpers.sh or orchestrator scripts

# Scripts live in the same directory as this file; we need it for _ssh/_ssh_tty.
_Hyper_DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_Hyper_DEPLOY_DIR}/../helpers.sh"
source "${_Hyper_DEPLOY_DIR}/transport.sh"

# Resolve genestack root relative to this file's location (scripts/lib/hyperconverged -> repo root)
GENESTACK_ROOT="$(cd "${_Hyper_DEPLOY_DIR}/../../.." && pwd)"
GENESTACK_COMPONENTS_YAML="${GENESTACK_COMPONENTS_YAML:-${GENESTACK_ROOT}/openstack-components.yaml}"
GENESTACK_GENESTACK_RC="${GENESTACK_RC_OVERRIDE:-${GENESTACK_ROOT}/scripts/genestack.rc}"

function prepareJumpHostSource() {
    # Prepare the jump host with the Genestack source code
    # Usage: cloneGenestackOnJumpHost

    local DEV_PATH="${GENESTACK_ROOT}"

    if [ "${HYPERCONVERGED_DEV:-false}" = "true" ]; then
        if [ ! -d "${DEV_PATH}" ]; then
            echo "HYPERCONVERGED_DEV is true, but we've failed to determine the base genestack directory"
            exit 1
        fi

        # Sync submodules locally so rsync copies an initialized kubespray checkout
        # rather than relying on remote 'git submodule update' which would clone
        # from GitHub and defeat the purpose of testing local changes.
        echo "Syncing local submodules (kubespray, etc.) before rsync..."
        if [ -f "${DEV_PATH}/.gitmodules" ]; then
            git -C "${DEV_PATH}" submodule sync --recursive
            git -C "${DEV_PATH}" submodule update --init --recursive
        fi

        _ssh "while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do echo 'Waiting for apt locks to be released...'; sleep 5; done && sudo apt-get update && sudo apt install -y rsync git && sudo mkdir -p /opt/genestack && sudo chown ${SSH_USERNAME}:${SSH_USERNAME} /opt/genestack"

        echo "Copying the development source code to the jump host"
        rsync -avz \
            --exclude='.git' \
            -e "ssh ${SSH_OPTS_STR}" \
            ${DEV_PATH} "${SSH_TARGET}:/opt/"
    else
        cloneGenestackOnJumpHost
    fi
}


function cloneGenestackOnJumpHost() {
    # Clone the Genestack repository on the jump host
    # Usage: cloneGenestackOnJumpHost
    _ssh <<'EOC'
    set -e
    if [ ! -d "/opt/genestack" ]; then
        sudo git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
    fi
    echo "Updating Genestack repository on jump host and initializing submodules..."
    sudo git config --global --add safe.directory /opt/genestack
    pushd /opt/genestack
        sudo git submodule update --init --recursive
    popd
EOC
}


function runGenestackSetup() {
    # Run Genestack infrastructure and OpenStack setup locally
    # Usage: runGenestackSetup <gateway_domain> <acme_email>

    local gateway_domain="$1"
    local acme_email="$2"
    local disable_openstack="${3:-false}"

    echo "Installing OpenStack Infrastructure"
    sudo LONGHORN_STORAGE_REPLICAS=1 \
         GATEWAY_DOMAIN="${gateway_domain}" \
         ACME_EMAIL="${acme_email}" \
         HYPERCONVERGED=true \
         /opt/genestack/bin/setup-infrastructure.sh

    if [ ${disable_openstack} = false ]; then
      echo "Installing OpenStack"
      sudo /opt/genestack/bin/setup-openstack.sh
      sudo /opt/genestack/bin/setup-openstack-rc.sh
    fi
}

#############################################################################
# Remote Configuration Functions (for SSH-based setup on jump hosts)
#############################################################################


function configureGenestackRemote() {
    # Configure Genestack on a remote jump host via SSH
    # Usage: configureGenestackRemote <ssh_user> <jump_host_ip> <metal_lb_ip> <gateway_domain>
    #
    # This function SSHes to the jump host and writes all the service helm overrides
    # and endpoints configuration. It's used by both Kubespray and Talos scripts.

    local ssh_user="$1"
    local jump_host="$2"
    local metal_lb_ip="$3"
    local gateway_domain="$4"
     local os_config="$(cat "${GENESTACK_COMPONENTS_YAML}")"

    echo "Configuring Genestack service overrides on jump host..."

    {
        declare -f writeMetalLBConfig
        declare -f writeServiceHelmOverrides
        declare -f writeEndpointsConfig
        declare -f writeOpenstackComponentsConfig
        declare -f detectPlatform
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
export HYPERCONVERGED_CINDER_VOLUME=$HYPERCONVERGED_CINDER_VOLUME
export INCLUDE_LIST=("${INCLUDE_LIST[@]}")
export EXCLUDE_LIST=("${EXCLUDE_LIST[@]}")
set -e
detectPlatform
ensureYq
writeMetalLBConfig '${metal_lb_ip}' '/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml'
writeServiceHelmOverrides '/etc/genestack/helm-configs'
writeEndpointsConfig '${gateway_domain}' '/etc/genestack/helm-configs/global_overrides/endpoints.yaml'
writeOpenstackComponentsConfig '/etc/genestack/openstack-components.yaml' "${os_config}"
echo 'Genestack service configuration complete'
EOF
    } | _ssh bash
}


function runGenestackSetupRemote() {
    # Run Genestack infrastructure and OpenStack setup on a remote jump host
    # Usage: runGenestackSetupRemote <ssh_user> <jump_host_ip> <gateway_domain> <acme_email>

    local ssh_user="$1"
    local jump_host="$2"
    local gateway_domain="$3"
    local acme_email="$4"
    local disable_openstack="${5:-false}"

    echo "Installing OpenStack Infrastructure on jump host..."

    {
        declare -f runGenestackSetup
        declare -f detectPlatform
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
set -e
detectPlatform
ensureYq
runGenestackSetup "${gateway_domain}" "${acme_email}" ${disable_openstack}
EOF
    } | _ssh bash
}


function waitForOpenStackAPIsReady() {
    # Wait for Nova and Neutron APIs to be ready
    # Usage: waitForOpenStackAPIsReady [timeout_seconds]
    #
    # This function waits for the Nova and Neutron API services to become
    # available and responsive before proceeding with post-setup tasks.

    local timeout="${1:-300}"
    local interval=10
    local elapsed=0

    echo "Waiting for OpenStack APIs to be ready (timeout: ${timeout}s)..."

    if openstack --version; then
        echo "OpenStack CLI found"
    else
        echo "Sourcing OpenStack RC file..."
        source /opt/genestack/scripts/genestack.rc
    fi

    echo "Running Generic Genestack post setup..."

    if [ ! -f ~/.config/openstack ]; then
        sudo mkdir -p ~/.config/openstack
        sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack
        sudo chown $(id -u):$(id -g) ~/.config
    fi

    # Wait for Keystone (authentication) to be ready first
    echo "  Checking Keystone authentication..."
    while [[ $elapsed -lt $timeout ]]; do
        if openstack --os-cloud default token issue >/dev/null 2>&1; then
            echo "  Keystone is ready"
            break
        fi
        echo "  Keystone not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Keystone API"
        return 1
    fi

    # Wait for Nova API to be ready
    echo "  Checking Nova API..."
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if openstack --os-cloud default compute service list >/dev/null 2>&1; then
            # Verify at least one compute service is up
            local nova_up=$(openstack --os-cloud default compute service list -f value -c State 2>/dev/null | grep -c "up" || echo "0")
            if [[ $nova_up -gt 0 ]]; then
                echo "  Nova API is ready (${nova_up} service(s) up)"
                break
            fi
        fi
        echo "  Nova API not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Nova API"
        return 1
    fi

    # Wait for Neutron API to be ready
    # NOTE: Do not gate on "network agent alive=true" because OVN-based
    # deployments may not report classic Neutron agents in that format.
    echo "  Checking Neutron API..."
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # Primary readiness signal: Neutron API can answer list queries.
        if openstack --os-cloud default network list -f value -c ID >/dev/null 2>&1; then
            # Optional telemetry: try to print agent count when available.
            local neutron_agents
            neutron_agents=$(openstack --os-cloud default network agent list -f value -c Alive 2>/dev/null | wc -l || echo "0")
            echo "  Neutron API is ready (${neutron_agents} agent row(s) reported)"
            break
        fi
        echo "  Neutron API not ready yet, waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep $interval
        ((elapsed+=interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        echo "ERROR: Timeout waiting for Neutron API"
        return 1
    fi

    echo "OpenStack APIs are ready"
    return 0
}


function waitForOpenStackAPIsReadyRemote() {
    # Wait for Nova and Neutron APIs on a remote jump host
    # Usage: waitForOpenStackAPIsReadyRemote <ssh_user> <jump_host_ip> [timeout_seconds]

    local ssh_user="$1"
    local jump_host="$2"
    local timeout="${3:-300}"

    echo "Waiting for OpenStack APIs on jump host..."

    {
        declare -f waitForOpenStackAPIsReady

        cat <<EOF
set -e
waitForOpenStackAPIsReady "${timeout}"
EOF
    } | _ssh bash
}


function createPostSetupResources() {
    # Create post-setup OpenStack resources (flavor, flat network, subnet)
    # Usage: createPostSetupResources <lab_name_prefix>
    local lab_prefix="$1"

    if openstack --version; then
        echo "OpenStack CLI found"
    else
        echo "Sourcing OpenStack RC file..."
        source /opt/genestack/scripts/genestack.rc
    fi

    echo "Running Generic Genestack post setup..."

    if [ ! -f ~/.config/openstack ]; then
        sudo mkdir -p ~/.config/openstack
        sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack
        sudo chown $(id -u):$(id -g) ~/.config
    fi

    # Create test flavor
    if ! openstack --os-cloud default flavor show ${lab_prefix}-test 2>/dev/null; then
        openstack --os-cloud default flavor create ${lab_prefix}-test \
            --public \
            --ram 2048 \
            --disk 10 \
            --vcpus 2
    fi

    # Create flat provider network
    if ! openstack --os-cloud default network show flat 2>/dev/null; then
        openstack --os-cloud default network create \
            --share \
            --availability-zone-hint az1 \
            --external \
            --provider-network-type flat \
            --provider-physical-network physnet1 \
            flat
    fi

    # Create flat subnet
    if ! openstack --os-cloud default subnet show flat_subnet 2>/dev/null; then
        openstack --os-cloud default subnet create \
            --subnet-range 192.168.102.0/24 \
            --gateway 192.168.102.1 \
            --dns-nameserver 1.1.1.1 \
            --allocation-pool start=192.168.102.100,end=192.168.102.109 \
            --dhcp \
            --network flat \
            flat_subnet
    fi
}


function createPostSetupResourcesRemote() {
    # Run post-setup configuration on a remote jump host
    # Usage: createPostSetupResourcesRemote <ssh_user> <jump_host_ip> <lab_name_prefix>

    local ssh_user="$1"
    local jump_host="$2"
    local lab_prefix="$3"

    echo "Running post-setup configuration on jump host..."

    {
        declare -f createPostSetupResources
        declare -f detectPlatform
        declare -f ensureYq
        declare -f installYq

        cat <<EOF
set -e
detectPlatform
ensureYq
createPostSetupResources "${lab_prefix}"
EOF

    } | _ssh bash
}


function installK9s() {
    # Install k9s locally
    echo "Installing k9s..."
    if [ ! -e "/usr/bin/k9s" ]; then
        sudo wget -q https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb -O /tmp/k9s_linux_amd64.deb
        sudo apt install -y /tmp/k9s_linux_amd64.deb
        sudo rm /tmp/k9s_linux_amd64.deb
    fi

    if [ ! -d ~/.kube ]; then
        mkdir ~/.kube
        sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config 2>/dev/null || true
        sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    fi
}


function installK9sRemote() {
    # Install k9s on a remote jump host
    # Usage: installK9sRemote <ssh_user> <jump_host_ip>

    local ssh_user="$1"
    local jump_host="$2"

    echo "Installing k9s on jump host..."

    {
        declare -f installK9s

        cat <<EOF
set -e
installK9s
EOF
    } | _ssh bash
}


function cinderVolumeSetup() {
    local net_name="${LAB_NAME_PREFIX}-net"

    # capture IPs (not VIP) for each server
    IP_0=$(openstack server show ${LAB_NAME_PREFIX}-0 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    IP_1=$(openstack server show ${LAB_NAME_PREFIX}-1 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    IP_2=$(openstack server show ${LAB_NAME_PREFIX}-2 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][0]')
    JUMP_HOST_IP=$(openstack server show ${LAB_NAME_PREFIX}-0 -f json | jq -r '.addresses' | jq --arg net_name "${net_name}" -r '.[$net_name][1]')

    # VM specific setup
    echo "[VM] Updating ~/.ssh/config"
    cat >> ~/.ssh/config << SSH_CONFIG_EOF
Host *
    User ubuntu
    ForwardAgent yes
    ForwardX11Trusted yes
    AddKeysToAgent yes
    IdentityFile /home/ubuntu/.ssh/${LAB_NAME_PREFIX}-key.pem
    ProxyCommand none
    TCPKeepAlive yes
    ServerAliveInterval 300
    Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc
    MACs hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com
    KexAlgorithms +diffie-hellman-group1-sha1
SSH_CONFIG_EOF

    echo "[VM] Removing ~/.ssh/known_hosts"
    rm -f ~/.ssh/known_hosts

    # Jump Host setup
    PEM_CONTENT=$(cat ~/.ssh/${LAB_NAME_PREFIX}-key.pem)
    PUB_CONTENT=$(cat ~/.ssh/${LAB_NAME_PREFIX}-key.pub)

    {
        cat << JUMP_HOST_EOF
source /opt/genestack/scripts/genestack.rc

echo "[JUMP_HOST] Setup for admin operations"
sudo mkdir -p ~/.config/openstack
sudo cp /root/.config/openstack/clouds.yaml ~/.config/openstack/
sudo chown -R $(id -u):$(id -g) ~/.config

echo "[JUMP_HOST] Updating ~/.ssh/config"
cat >> ~/.ssh/config << SSH_CONFIG_EOF
Host *
    User ubuntu
    ForwardAgent yes
    ForwardX11Trusted yes
    AddKeysToAgent yes
    IdentityFile /home/ubuntu/.ssh/${LAB_NAME_PREFIX}-key.pem
    ProxyCommand none
    TCPKeepAlive yes
    ServerAliveInterval 300
    Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc
    MACs hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com
    KexAlgorithms +diffie-hellman-group1-sha1
SSH_CONFIG_EOF

echo "[JUMP_HOST] Creating ssh key"
echo "${PEM_CONTENT}" >> ~/.ssh/${LAB_NAME_PREFIX}-key.pem
echo "${PUB_CONTENT}" >> ~/.ssh/${LAB_NAME_PREFIX}-key.pub
chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem
chmod 644 ~/.ssh/${LAB_NAME_PREFIX}-key.pub

echo "[JUMP_HOST] Updating /etc/hosts"
sudo sh -c 'cat >> /etc/hosts' << ETC_HOSTS_EOF
${IP_0} ${LAB_NAME_PREFIX}-0.cluster.local ${LAB_NAME_PREFIX}-0
${IP_1} ${LAB_NAME_PREFIX}-1.cluster.local ${LAB_NAME_PREFIX}-1
${IP_2} ${LAB_NAME_PREFIX}-2.cluster.local ${LAB_NAME_PREFIX}-2
ETC_HOSTS_EOF

echo "[JUMP_HOST] Creating PV/VG"
sudo pvcreate /dev/vdd
sudo vgcreate cinder-volumes-1 /dev/vdd
JUMP_HOST_EOF
    } | _ssh bash

    # Secondary Kube node setup
    {
        cat << NODE_1_EOF
echo "[Node 1] Creating PV/VG"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ubuntu@${LAB_NAME_PREFIX}-1 "sudo pvcreate /dev/vdd && sudo vgcreate cinder-volumes-1 /dev/vdd"
NODE_1_EOF
    } | _ssh bash
    {
        cat << NODE_2_EOF
echo "[Node 2] Creating PV/VG"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ubuntu@${LAB_NAME_PREFIX}-2 "sudo pvcreate /dev/vdd && sudo vgcreate cinder-volumes-1 /dev/vdd"
NODE_2_EOF
    } | _ssh bash

    # Ansible playbook time
    {
        cat << ANSIBLE_EOF
source /opt/genestack/scripts/genestack.rc

echo "[JUMP_HOST] Running cinder install script"
sudo /opt/genestack/bin/install.sh --service cinder

#for node in ${LAB_NAME_PREFIX}-0 ${LAB_NAME_PREFIX}-1 ${LAB_NAME_PREFIX}-2; do
#    echo "Waiting for apt locks on \${node}..."
#    ssh -o StrictHostKeyChecking=no \${node} \
#        'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo "  apt lock held, waiting..."; sleep 5; done'
#done

echo "[JUMP_HOST] Running cinder volumes playbook (running twice to get past apt lock issue that previous loop should fix but doesn't)"
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e "storage_network_interface=ansible_enp3s0 storage_network_interface_secondary=ansible_enp3s0 cinder_backend_name=lvmdriver-1 cinder_worker_name=lvm cinder_release_branch='stable/2025.1'" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volume.yaml -f3
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e "storage_network_interface=ansible_enp3s0 storage_network_interface_secondary=ansible_enp3s0 cinder_backend_name=lvmdriver-1 cinder_worker_name=lvm cinder_release_branch='stable/2025.1'" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volume.yaml -f3

echo "[JUMP_HOST] Creating volume type and qos"
openstack volume type create \
    --description 'Standard with LUKS encryption' \
    --encryption-provider luks \
    --encryption-cipher aes-xts-plain64 \
    --encryption-key-size 256 \
    --encryption-control-location front-end \
    --property volume_backend_name=LVM_iSCSI \
    --property provisioning:max_vol_size='199' \
    --property provisioning:min_vol_size='1' \
    Standard
openstack volume qos create \
    --property read_iops_sec_per_gb='20' \
    --property write_iops_sec_per_gb='20' \
    Standard-Block
openstack volume qos associate Standard-Block Standard
openstack volume type set --private __DEFAULT__
ANSIBLE_EOF
    } | _ssh bash
}


function install_preconf_octavia() {
    echo "Installing Octavia preconf"
    _ssh << 'EOC'
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
sudo /opt/genestack/bin/install.sh --service octavia -f $OCTAVIA_HELM_FILE
EOC
}


function setupKubeConfig() {
    if [ ! -d ~/.kube ]; then
        mkdir ~/.kube
        sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config 2>/dev/null || true
        sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    fi
}


function deployTrove() {
    echo "Running trove deployment ..."

    local ssh_user="$1"
    local jump_host="$2"
    local lab_name_prefix="$3"
    local compute_subnet_cidr="$4"
    local mgmt_subnet_cidr="$5"

    # Trove guest VM connectivity — scoped to internal networks only (not public).
    # RabbitMQ (5672) and Keystone (5000) are on the MetalLB shared VIP.
    # Two rules per port: flat network (source) and mgmt network (SNAT).
    if ! openstack security group show ${lab_name_prefix}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 5672; then
        openstack security group rule create ${lab_name_prefix}-http-secgroup \
            --protocol tcp --ingress --dst-port 5672 \
            --remote-ip ${compute_subnet_cidr:-192.168.102.0/24} \
            --description "RabbitMQ for Trove guest VMs (flat network)"
        openstack security group rule create ${lab_name_prefix}-http-secgroup \
            --protocol tcp --ingress --dst-port 5672 \
            --remote-ip ${mgmt_subnet_cidr:-192.168.100.0/24} \
            --description "RabbitMQ for Trove guest VMs (mgmt network / SNAT)"
    fi
    if ! openstack security group show ${lab_name_prefix}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 5000; then
        openstack security group rule create ${lab_name_prefix}-http-secgroup \
            --protocol tcp --ingress --dst-port 5000 \
            --remote-ip ${compute_subnet_cidr:-192.168.102.0/24} \
            --description "Keystone for Trove guest VMs (flat network)"
        openstack security group rule create ${lab_name_prefix}-http-secgroup \
            --protocol tcp --ingress --dst-port 5000 \
            --remote-ip ${mgmt_subnet_cidr:-192.168.100.0/24} \
            --description "Keystone for Trove guest VMs (mgmt network / SNAT)"
    fi

    {
        declare -f setupKubeConfig

        cat << JUMP_HOST_EOF
# check if trove is to be installed, otherwise exit cleanly
if ! grep "trove: true" /etc/genestack/openstack-components.yaml &>/dev/null; then
    echo "Trove not installed, exiting Trove setup function for ${lab_name_prefix}-0"
    exit 0
fi

set -e
# activate environment for openstack commands
source /opt/genestack/scripts/genestack.rc

setupKubeConfig

echo "Running playbook for trove_secrets"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_secrets
echo "Running playbook for trove_mgmt_network"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_mgmt_network
#echo "Running playbook for trove_guest_vm_security_group_rules ${LAB_NAME_PREFIX}"
#ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
#    --tags trove_guest_vm_security_group_rules \
#    -e lab_name_prefix=${LAB_NAME_PREFIX} \
#    -e compute_subnet_cidr=${COMPUTE_SUBNET_CIDR:-192.168.102.0/24} \
#    -e mgmt_subnet_cidr=${MGMT_SUBNET_CIDR:-192.168.100.0/24}
echo "Running playbook for trove_security_groups"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_security_groups
echo "Running playbook for trove_helm_config"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_helm_config
echo "Running playbook for trove_gateway"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_gateway

echo "Installing Trove via Helm chart"
sudo /opt/genestack/bin/install.sh --service trove

echo "Running playbook for trove_image_build"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_image_build
echo "Running playbook for trove_datastore"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_datastore
echo "Running playbook for trove_client"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_client
echo "Running playbook for trove_keypair"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_keypair
echo "Running playbook for trove_ssh_key_distribute"
ansible-playbook /opt/genestack/ansible/playbooks/trove-enablement-techpreview.yaml \
    --tags trove_ssh_key_distribute
JUMP_HOST_EOF
    } | _ssh bash
}
