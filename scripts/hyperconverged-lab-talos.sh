#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Script for Talos Linux
#
# This script deploys a fully automated Talos Linux-based Kubernetes cluster
# for running Genestack (OpenStack on Kubernetes) in a hyperconverged configuration.
#
# Platform: Talos Linux
# Kubernetes Setup: talosctl (Talos native)
# Architecture:
#   - Jump host for running talosctl, kubectl, and genestack setup
#   - 3 Talos Linux nodes for the Kubernetes cluster
# Key differences from Kubespray:
#   - Uses Talos Linux instead of Ubuntu for K8s nodes
#   - Automatically downloads Talos image with required extensions from Talos Factory
#   - Uses talosctl for cluster management instead of kubespray/SSH
#   - Includes Talos-specific configurations for Longhorn, Kube-OVN, and Ceph Rook
#   - Requires manual cert-manager installation (not included in Talos like kubespray)
#

set -o pipefail
set -e
SECONDS=0

# Source common library
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/lib/hyperconverged-common.sh"

#############################################################################
# Talos-Specific Configuration
#############################################################################

export TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
export TALOS_ARCH="${TALOS_ARCH:-amd64}"
# Talos Factory schematic ID with iscsi-tools and util-linux-tools extensions for Longhorn
# This schematic includes: siderolabs/iscsi-tools, siderolabs/util-linux-tools siderolabs/qemu-guest-agent
export TALOS_SCHEMATIC_ID="${TALOS_SCHEMATIC_ID:-88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b}"
export TALOS_IMAGE_NAME="${TALOS_IMAGE_NAME:-talos-${TALOS_VERSION}-genestack}"
export TALOS_CLUSTER_NAME="${TALOS_CLUSTER_NAME:-genestack-talos}"

# Jump host configuration (Ubuntu-based small instance)
export JUMP_HOST_IMAGE="${JUMP_HOST_IMAGE:-Ubuntu 24.04}"

#############################################################################
# Talos-Specific Functions
#############################################################################

function installTalosctl() {
    echo "Installing talosctl..."
    curl -sL https://talos.dev/install | sh
}

function selectJumpHostFlavor() {
    # Select a small flavor for the jump host (~2 cores, ~2GB RAM, minimal disk)
    # This is a lightweight VM just for running talosctl, kubectl, and genestack scripts
    if [ -z "${JUMP_HOST_FLAVOR}" ]; then
        # List small flavors: 1-4GB RAM, any disk size, sorted by RAM ascending
        SMALL_FLAVORS=$(openstack flavor list --sort-column RAM -c Name -c RAM -c Disk -c VCPUs -f json 2>/dev/null || echo "[]")

        # Try to find a flavor with ~2GB RAM (1536-4096 MB range) and 1-2 vCPUs
        DEFAULT_JUMP_FLAVOR=$(echo "${SMALL_FLAVORS}" | jq -r '
            [.[] | select(.RAM >= 1536 and .RAM <= 4096 and .VCPUs <= 2 and .Disk >= 10)] |
            sort_by(.RAM) |
            .[0].Name // empty
        ')

        # If no ideal flavor found, try broader search (up to 8GB RAM, up to 4 vCPUs)
        if [ -z "${DEFAULT_JUMP_FLAVOR}" ] || [ "${DEFAULT_JUMP_FLAVOR}" = "null" ]; then
            DEFAULT_JUMP_FLAVOR=$(echo "${SMALL_FLAVORS}" | jq -r '
                [.[] | select(.RAM >= 1024 and .RAM <= 8192 and .VCPUs <= 4 and .Disk >= 10)] |
                sort_by(.RAM) |
                .[0].Name // empty
            ')
        fi

        # If still nothing, just pick the smallest available
        if [ -z "${DEFAULT_JUMP_FLAVOR}" ] || [ "${DEFAULT_JUMP_FLAVOR}" = "null" ]; then
            DEFAULT_JUMP_FLAVOR=$(echo "${SMALL_FLAVORS}" | jq -r '
                [.[] | select(.Disk >= 10)] |
                sort_by(.RAM) |
                .[0].Name // empty
            ')
        fi

        if [ -z "${DEFAULT_JUMP_FLAVOR}" ] || [ "${DEFAULT_JUMP_FLAVOR}" = "null" ]; then
            echo "ERROR: Could not find a suitable flavor for the jump host"
            echo "Please set JUMP_HOST_FLAVOR environment variable manually"
            exit 1
        fi

        echo ""
        echo "Jump host flavor selection (small instance for management):"
        echo "${SMALL_FLAVORS}" | jq -r '
            [.[] | select(.RAM <= 8192)] |
            sort_by(.RAM) |
            .[:10] |
            ["Name", "RAM", "Disk", "VCPUs"], (.[] | [.Name, .RAM, .Disk, .VCPUs]) |
            @tsv
        ' | column -t
        echo ""
        read -rp "Enter flavor for jump host [${DEFAULT_JUMP_FLAVOR}]: " JUMP_HOST_FLAVOR
        export JUMP_HOST_FLAVOR="${JUMP_HOST_FLAVOR:-${DEFAULT_JUMP_FLAVOR}}"
    fi
}

function detectJumpHostSSHUsername() {
    # Detect SSH username for the jump host image
    if [ -z "${SSH_USERNAME}" ]; then
        if ! IMAGE_DEFAULT_PROPERTY=$(openstack image show "${JUMP_HOST_IMAGE}" -f json -c properties 2>/dev/null); then
            read -rp "Jump host image '${JUMP_HOST_IMAGE}' not found. Enter the image name: " JUMP_HOST_IMAGE
            IMAGE_DEFAULT_PROPERTY=$(openstack image show "${JUMP_HOST_IMAGE}" -f json -c properties)
        fi
        if [ "${IMAGE_DEFAULT_PROPERTY}" ]; then
            if SSH_USERNAME=$(echo "${IMAGE_DEFAULT_PROPERTY}" | jq -r '.properties.default_user // empty'); then
                if [ -n "${SSH_USERNAME}" ] && [ "${SSH_USERNAME}" != "null" ]; then
                    echo "Discovered the default username for the jump host image as ${SSH_USERNAME}"
                fi
            fi
        fi
        if [ -z "${SSH_USERNAME}" ] || [ "${SSH_USERNAME}" = "null" ]; then
            echo "The image ${JUMP_HOST_IMAGE} does not have a default user property"
            read -rp "Enter the default username for the jump host image [ubuntu]: " SSH_USERNAME
            SSH_USERNAME="${SSH_USERNAME:-ubuntu}"
        fi
    fi
    export SSH_USERNAME
}

function ensureTalosctl() {
    if ! talosctl version --client 2> /dev/null; then
        echo "talosctl is not installed. Attempting to install talosctl"
        installTalosctl
    fi
}

function downloadTalosImage() {
    local image_url="https://factory.talos.dev/image/${TALOS_SCHEMATIC_ID}/${TALOS_VERSION}/openstack-${TALOS_ARCH}.raw.xz"
    local image_file="/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw.xz"
    local raw_file="/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw"

    echo "Downloading Talos image from Talos Factory..."
    echo "URL: ${image_url}"
    echo "This image includes extensions: iscsi-tools, util-linux-tools (required for Longhorn)"

    if [ ! -f "${raw_file}" ]; then
        if [ ! -f "${image_file}" ]; then
            curl -L -o "${image_file}" "${image_url}"
        fi
        echo "Decompressing Talos image..."
        xz -d -k "${image_file}"
    else
        echo "Talos image already downloaded and decompressed"
    fi
}

function uploadTalosImage() {
    local raw_file="$1"

    echo "Uploading Talos image to Glance as '${TALOS_IMAGE_NAME}'..."
    openstack image create "${TALOS_IMAGE_NAME}" \
        --disk-format raw \
        --container-format bare \
        --file "${raw_file}" \
        --property os_type=linux \
        --property os_distro=talos \
        --property os_version="${TALOS_VERSION}" \
        --property hw_vif_multiqueue_enabled=true \
        --property hw_qemu_guest_agent=yes \
        --property hypervisor_type=kvm \
        --property img_config_drive=optional \
        --property hw_machine_type=q35 \
        --property hw_firmware_type=uefi \
        --property os_require_quiesce=yes \
        --property os_type=linux \
        --property os_admin_user=talos \
        --property os_distro=talos \
        --property os_version=18.2 \
        --tag "siderolabs/iscsi-tools" \
        --tag "siderolabs/util-linux-tools" \
        --tag "siderolabs/qemu-guest-agent" \
        --progress

    echo "Talos image uploaded successfully"
}

function createTalosSecurityGroup() {
    # Create Talos-specific security group (API + K8s API + ICMP)
    if ! openstack security group show ${LAB_NAME_PREFIX}-talos-secgroup 2>/dev/null; then
        openstack security group create ${LAB_NAME_PREFIX}-talos-secgroup
    fi

    # Talos API port (50000)
    if ! openstack security group show ${LAB_NAME_PREFIX}-talos-secgroup -f json 2>/dev/null | jq -r '.rules.[].port_range_max' | grep -q 50000; then
        openstack security group rule create ${LAB_NAME_PREFIX}-talos-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 50000 \
            --description "talos-api"
    fi

    # Kubernetes API port (6443)
    if ! openstack security group show ${LAB_NAME_PREFIX}-talos-secgroup -f json 2>/dev/null | jq -r '.rules.[].port_range_max' | grep -q 6443; then
        openstack security group rule create ${LAB_NAME_PREFIX}-talos-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 6443 \
            --description "kubernetes-api"
    fi

    if ! openstack security group show ${LAB_NAME_PREFIX}-talos-secgroup -f json 2>/dev/null | jq -r '.rules.[].protocol' | grep -q icmp; then
        openstack security group rule create ${LAB_NAME_PREFIX}-talos-secgroup \
            --protocol icmp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --description "ping"
    fi
}

function writeKubeOvnTalosConfig() {
    # Configure Kube-OVN for Talos
    # Talos requires specific settings: OPENVSWITCH_DIR, OVN_DIR, DISABLE_MODULES_MANAGEMENT
    local config_path="${1:-/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml}"

    cat > "${config_path}" <<EOF
---
global:
  registry:
    address: docker.io/kubeovn
    imagePullSecrets: []
networking:
  IFACE: "ens3"
  vlan:
    VLAN_INTERFACE_NAME: "ens3"
OPENVSWITCH_DIR: /var/lib/openvswitch
OVN_DIR: /var/lib/ovn
DISABLE_MODULES_MANAGEMENT: true
EOF
}

function writeRookCephTalosNamespace() {
    # Configure Rook-Ceph namespace with Talos privileged permissions
    local overlay_dir="${1:-/etc/genestack/kustomize/rook-operator/overlay}"

    mkdir -p "${overlay_dir}"

    cat > "${overlay_dir}/namespace-talos.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: rook-ceph
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/warn-version: latest
  name: rook-ceph
EOF

    cat > "${overlay_dir}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  - namespace-talos.yaml
EOF
}

#############################################################################
# Initialize
#############################################################################

ensureYq
parseCommonArgs "$@"
promptForCommonInputs

# Select jump host flavor and detect SSH username
selectJumpHostFlavor
detectJumpHostSSHUsername

#############################################################################
# Talos Image Management
#############################################################################

if ! openstack image show "${TALOS_IMAGE_NAME}" 2>/dev/null; then
    echo "Talos image '${TALOS_IMAGE_NAME}' not found in Glance"
    downloadTalosImage
    uploadTalosImage "/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw"
else
    echo "Talos image '${TALOS_IMAGE_NAME}' already exists in Glance"
fi

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-talos-hyperconverged}"

#############################################################################
# Create OpenStack Infrastructure (Common)
#############################################################################

createRouter
createNetworks
createCommonSecurityGroups
createTalosSecurityGroup

#############################################################################
# Jump Host Security Group (SSH access)
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

createMetalLBPort

#############################################################################
# Jump Host SSH Key Management
#############################################################################

if [ ! -d ~/.ssh ]; then
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
# Jump Host Port and Instance
#############################################################################

if ! JUMP_HOST_PORT=$(openstack port show ${LAB_NAME_PREFIX}-jump-mgmt-port -f value -c id 2>/dev/null); then
    export JUMP_HOST_PORT=$(
        openstack port create \
            --security-group ${LAB_NAME_PREFIX}-secgroup \
            --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
            --network ${LAB_NAME_PREFIX}-net \
            -f value \
            -c id \
            ${LAB_NAME_PREFIX}-jump-mgmt-port
    )
fi
export JUMP_HOST_PORT

# Floating IP for jump host
if ! JUMP_HOST_VIP=$(openstack floating ip list --port ${JUMP_HOST_PORT} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${JUMP_HOST_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${JUMP_HOST_VIP}" ]; then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${JUMP_HOST_PORT} -f json | jq -r '.floating_ip_address')
fi
export JUMP_HOST_VIP

# Create jump host instance
if ! openstack server show ${LAB_NAME_PREFIX}-jump 2>/dev/null; then
    echo "Creating jump host instance..."
    openstack server create ${LAB_NAME_PREFIX}-jump \
        --port ${JUMP_HOST_PORT} \
        --image "${JUMP_HOST_IMAGE}" \
        --key-name ${LAB_NAME_PREFIX}-key \
        --flavor ${JUMP_HOST_FLAVOR}
fi

#############################################################################
# Talos-Specific: Create Management Ports with Talos Security Group
#############################################################################

if ! WORKER_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id 2>/dev/null); then
    export WORKER_0_PORT=$(
        openstack port create --allowed-address ip-address=${METAL_LB_IP} \
            --security-group ${LAB_NAME_PREFIX}-secgroup \
            --security-group ${LAB_NAME_PREFIX}-talos-secgroup \
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

# Get the IPs for nodes
WORKER_0_IP=$(openstack port show ${WORKER_0_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
WORKER_1_IP=$(openstack port show ${WORKER_1_PORT} -f json | jq -r '.fixed_ips[0].ip_address')
WORKER_2_IP=$(openstack port show ${WORKER_2_PORT} -f json | jq -r '.fixed_ips[0].ip_address')

# Floating IP for first node (control plane access)
if ! CONTROL_PLANE_VIP=$(openstack floating ip list --port ${WORKER_0_PORT} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
    CONTROL_PLANE_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${CONTROL_PLANE_VIP}" ]; then
    CONTROL_PLANE_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
fi
export CONTROL_PLANE_VIP

createComputePorts

#############################################################################
# Create Talos Instances (No SSH key needed - Talos uses API)
#############################################################################

if ! openstack server show ${LAB_NAME_PREFIX}-0 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-0 \
        --port ${WORKER_0_PORT} \
        --port ${COMPUTE_0_PORT} \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-1 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-1 \
        --port ${WORKER_1_PORT} \
        --port ${COMPUTE_1_PORT} \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor ${OS_FLAVOR}
fi

if ! openstack server show ${LAB_NAME_PREFIX}-2 2>/dev/null; then
    openstack server create ${LAB_NAME_PREFIX}-2 \
        --port ${WORKER_2_PORT} \
        --port ${COMPUTE_2_PORT} \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor ${OS_FLAVOR}
fi

#############################################################################
# Wait for Jump Host SSH Access
#############################################################################

echo "Waiting for the jump host to be ready..."
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

echo "Jump host is reachable at ${JUMP_HOST_VIP}"

#############################################################################
# Install Prerequisites on Jump Host
#############################################################################

echo "Installing prerequisites on jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<'EOFPREREQ'
set -e
# Wait for apt locks to be released
while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
    echo 'Waiting for apt locks to be released...'
    sleep 5
done

# Install required packages
sudo apt-get update
sudo apt-get install -y curl wget git jq netcat-openbsd xz-utils

# Install yq
if ! yq --version 2>/dev/null; then
    echo "Installing yq..."
    export VERSION=v4.2.0
    export BINARY=yq_linux_amd64
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -q -O - | tar xz
    sudo mv ${BINARY} /usr/local/bin/yq
fi

# Install talosctl
if ! talosctl version --client 2>/dev/null; then
    echo "Installing talosctl..."
    curl -sL https://talos.dev/install | sh
fi

# Install kubectl
if ! kubectl version --client 2>/dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi
EOFPREREQ

#############################################################################
# Wait for Talos API (from jump host perspective using internal IPs)
#############################################################################

echo "Waiting for Talos nodes to boot and become reachable..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOFWAIT
set -e
COUNT=0
while ! nc -z -w 2 ${WORKER_0_IP} 50000 2>/dev/null; do
    sleep 5
    echo "Waiting for Talos API on ${WORKER_0_IP}:50000..."
    COUNT=\$((COUNT + 1))
    if [ \$COUNT -gt 60 ]; then
        echo "Failed to reach Talos API on control plane node"
        exit 1
    fi
done
echo "Talos API is reachable on ${WORKER_0_IP}"
EOFWAIT

#############################################################################
# Generate and Apply Talos Configuration (on jump host)
#############################################################################

echo "Generating and applying Talos configuration from jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOFTALOS
set -e

TALOS_CONFIG_DIR="/home/${SSH_USERNAME}/talos-config"
mkdir -p "\${TALOS_CONFIG_DIR}"

if [ ! -f "\${TALOS_CONFIG_DIR}/controlplane.yaml" ]; then
    echo "Generating Talos cluster configuration..."

    # Generate base configuration
    talosctl gen config "${TALOS_CLUSTER_NAME}" "https://${WORKER_0_IP}:6443" \\
        --output-dir "\${TALOS_CONFIG_DIR}" \\
        --with-docs=false \\
        --with-examples=false

    # Create Talos configuration patches for Genestack requirements
    cat > "\${TALOS_CONFIG_DIR}/genestack-patch.yaml" <<'EOFPATCH'
machine:
  kubelet:
    extraMounts:
      # Required for Longhorn storage
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
  # Allow privileged workloads (required for OpenStack)
  sysctls:
    net.core.somaxconn: "65535"
    net.ipv4.ip_forward: "1"
    vm.max_map_count: "262144"
  # Install disk configuration
  install:
    disk: /dev/sda
    wipe: false
cluster:
  # Allow scheduling on control plane nodes (hyperconverged)
  allowSchedulingOnControlPlanes: true
  network:
    cni:
      name: none  # We'll install kube-ovn separately
  proxy:
    disabled: false
  # Inline manifests for cert-manager (required since kubespray is not used)
  inlineManifests: []
EOFPATCH

    # Patch the controlplane.yaml with our Genestack requirements
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \\
        "\${TALOS_CONFIG_DIR}/controlplane.yaml" \\
        "\${TALOS_CONFIG_DIR}/genestack-patch.yaml" > "\${TALOS_CONFIG_DIR}/controlplane-patched.yaml"

    mv "\${TALOS_CONFIG_DIR}/controlplane-patched.yaml" "\${TALOS_CONFIG_DIR}/controlplane.yaml"

    # For worker nodes, apply same patches
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \\
        "\${TALOS_CONFIG_DIR}/worker.yaml" \\
        "\${TALOS_CONFIG_DIR}/genestack-patch.yaml" > "\${TALOS_CONFIG_DIR}/worker-patched.yaml"

    mv "\${TALOS_CONFIG_DIR}/worker-patched.yaml" "\${TALOS_CONFIG_DIR}/worker.yaml"
fi

# Set talosctl configuration
export TALOSCONFIG="\${TALOS_CONFIG_DIR}/talosconfig"
talosctl config endpoint ${WORKER_0_IP}
talosctl config node ${WORKER_0_IP}

echo "Applying Talos configuration to control plane nodes..."
talosctl apply-config --insecure --nodes ${WORKER_0_IP} --file "\${TALOS_CONFIG_DIR}/controlplane.yaml"

sleep 10

talosctl apply-config --insecure --nodes ${WORKER_1_IP} --file "\${TALOS_CONFIG_DIR}/controlplane.yaml"
talosctl apply-config --insecure --nodes ${WORKER_2_IP} --file "\${TALOS_CONFIG_DIR}/controlplane.yaml"

echo "Waiting for nodes to apply configuration..."
sleep 30

echo "Bootstrapping Talos Kubernetes cluster..."
if ! talosctl bootstrap --nodes ${WORKER_0_IP} 2>/dev/null; then
    echo "Cluster may already be bootstrapped or still initializing, checking status..."
fi

echo "Waiting for Kubernetes cluster to be ready..."
COUNT=0
while talosctl services | awk '{print \$4}' | grep -i wait; do
    sleep 10
    echo "Cluster not yet healthy, waiting..."
    COUNT=\$((COUNT + 1))
    if [ \$COUNT -gt 30 ]; then
        echo "Cluster health check timed out, continuing anyway..."
        break
    fi
done

echo "Retrieving kubeconfig..."
mkdir -p ~/.kube
talosctl kubeconfig --nodes ${WORKER_0_IP} --force ~/.kube/config
EOFTALOS

#############################################################################
# Talos-Specific: Development Mode Source Copy
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
# Install cert-manager and Clone Genestack (on jump host)
#############################################################################

echo "Installing cert-manager and setting up Genestack on jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOFCERT
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

echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
EOFCERT

#############################################################################
# Configure Genestack for Talos (on jump host) - Talos-specific settings
#############################################################################

echo "Configuring Talos-specific Genestack settings on jump host..."
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t ${SSH_USERNAME}@${JUMP_HOST_VIP} <<EOFCONFIG
set -e

echo "Configuring Genestack for Talos Linux..."

# Configure Kube-OVN for Talos (Talos-specific: DISABLE_MODULES_MANAGEMENT)
cat > /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml <<EOF
---
global:
  registry:
    address: docker.io/kubeovn
    imagePullSecrets: []
networking:
  IFACE: "\$(ip -o r g 1 | awk '{print \$5}')"
  vlan:
    VLAN_INTERFACE_NAME: "\$(ip -o r g 1 | awk '{print \$5}')"
OPENVSWITCH_DIR: /var/lib/openvswitch
OVN_DIR: /var/lib/ovn
DISABLE_MODULES_MANAGEMENT: true
EOF

# Configure Rook-Ceph namespace with Talos privileged permissions
mkdir -p /etc/genestack/kustomize/rook-operator/overlay

cat > /etc/genestack/kustomize/rook-operator/overlay/namespace-talos.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: rook-ceph
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/warn-version: latest
  name: rook-ceph
EOF

cat > /etc/genestack/kustomize/rook-operator/overlay/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  - namespace-talos.yaml
EOF
EOFCONFIG

#############################################################################
# Write Service Helm Overrides and Endpoints (common function)
#############################################################################

configureGenestackRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${METAL_LB_IP}" "${GATEWAY_DOMAIN}"

#############################################################################
# Run Genestack Infrastructure Setup (common function)
#############################################################################

runGenestackSetupRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${GATEWAY_DOMAIN}" "${ACME_EMAIL}"

#############################################################################
# Extra Operations (on jump host)
#############################################################################

if [[ "$RUN_EXTRAS" -eq 1 ]]; then
    installK9sRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
fi

#############################################################################
# Post-Setup Configuration (common function)
#############################################################################

# Wait for Nova and Neutron APIs to be ready before proceeding
waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"

if [[ "${TEST_LEVEL}" == "off" ]]; then
    createPostSetupResourcesRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}"
fi

#############################################################################
# Output Summary
#############################################################################

{ cat | tee /tmp/output.txt; } <<EOF
================================================================================
Talos Linux Hyperconverged Lab Deployment Complete!
================================================================================

Deployment took ${SECONDS} seconds to complete.

Cluster Information:
  - Jump Host Address: ${JUMP_HOST_VIP}
  - MetalLB Internal IP: ${METAL_LB_IP}
  - MetalLB Public VIP: ${METAL_LB_VIP}

Talos Node IPs (internal):
  - Node 0: ${WORKER_0_IP}
  - Node 1: ${WORKER_1_IP}
  - Node 2: ${WORKER_2_IP}

SSH Access to Jump Host:
  ssh ${SSH_USERNAME}@${JUMP_HOST_VIP}

Talos Access (from jump host):
  export TALOSCONFIG=/home/${SSH_USERNAME}/talos-config/talosconfig
  talosctl --nodes ${WORKER_0_IP} health

Kubernetes Access (from jump host):
  kubectl get nodes

Important Notes:
  - This is a Talos Linux deployment (not Ubuntu/Kubespray)
  - Jump host is used for talosctl, kubectl, and genestack management
  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem
  - Kube-OVN is configured with DISABLE_MODULES_MANAGEMENT=true
  - Longhorn has the required extraMounts configured
  - cert-manager was installed separately (not via kubespray)
  - Rook-Ceph namespace has privileged pod security labels

Write these addresses down for future reference!
================================================================================
EOF
