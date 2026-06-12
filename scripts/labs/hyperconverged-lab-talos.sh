#!/usr/bin/env bash
# Hyperconverged Lab — Talos Orchestrator
# Sourced via hyperconverged-lab.sh

# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
set -o pipefail
SECONDS=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

###############################################################################
# Source helpers and modules (in dependency order)
###############################################################################
source "${SCRIPT_DIR}/../lib/helpers.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/net.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/security.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/ssh-keys.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/deploy.sh"
source "${SCRIPT_DIR}/../lib/talos/cluster.sh"
source "${SCRIPT_DIR}/../lib/talos/image.sh"
source "${SCRIPT_DIR}/../lib/talos/network.sh"

###############################################################################
# Talos-specific defaults (override common defaults)
###############################################################################
export TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
export TALOS_ARCH="${TALOS_ARCH:-amd64}"
export TALOS_BINARY="talosctl-linux-${TALOS_ARCH}"
export TALOS_SCHEMATIC_ID="${TALOS_SCHEMATIC_ID:-88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b}"
export TALOS_IMAGE_NAME="${TALOS_IMAGE_NAME:-talos-${TALOS_VERSION}-genestack}"
export TALOS_CLUSTER_NAME="${TALOS_CLUSTER_NAME:-genestack-talos}"
export LAB_NETWORK_MTU="${LAB_NETWORK_MTU:-1500}"
export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-talos-hyperconverged}"
export JUMP_HOST_IMAGE="${JUMP_HOST_IMAGE:-Ubuntu 24.04}"
export DISABLE_OPENSTACK="${DISABLE_OPENSTACK:-false}"
export TEST_LEVEL="${TEST_LEVEL:-full}"

SSH_TARGET="${SSH_USERNAME:-ubuntu}@${JUMP_HOST_VIP:-}"
SSH_OPTS_STR="-o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

###############################################################################
# Phase 1: Initialize
###############################################################################
_log STEP "Phase 1: Initialize"
ensureYq
ensureTalosctl
parseCommonArgs "$@"
promptForCommonInputs
selectJumpHostFlavor
detectJumpHostSSHUsername

###############################################################################
# Phase 2: Talos image management
###############################################################################
_log STEP "Phase 2: Talos image management"
if ! openstack image show "${TALOS_IMAGE_NAME}" 2>/dev/null; then
    _log INFO "Talos image not found, downloading and uploading"
    downloadTalosImage
    uploadTalosImage "/tmp/talos-${TALOS_VERSION}-openstack-${TALOS_ARCH}.raw"
else
    _log INFO "Talos image already exists in Glance"
fi

###############################################################################
# Phase 3: OpenStack networking infrastructure
###############################################################################
_log STEP "Phase 3: OpenStack networking infrastructure"

createRouter
createNetworks
createCommonSecurityGroups
createTalosSecurityGroup

if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f value -c name >/dev/null 2>&1; then
    _log INFO "Creating jump host security group"
    openstack security group create ${LAB_NAME_PREFIX}-jump-secgroup >/dev/null 2>&1 || { _log ERROR "Jump security group creation failed"; return 1; }
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -qx 22; then
    _log INFO "Adding SSH rule to ${LAB_NAME_PREFIX}-jump-secgroup"
    openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
        --protocol tcp --ingress --remote-ip 0.0.0.0/0 --dst-port 22 --description "ssh" >/dev/null 2>&1 || { _log ERROR "SSH rule creation failed"; return 1; }
fi
if ! openstack security group show ${LAB_NAME_PREFIX}-jump-secgroup -f json 2>/dev/null | jq -r '.rules[].protocol' | grep -qx icmp; then
    _log INFO "Adding ICMP rule to ${LAB_NAME_PREFIX}-jump-secgroup"
    openstack security group rule create ${LAB_NAME_PREFIX}-jump-secgroup \
        --protocol icmp --ingress --remote-ip 0.0.0.0/0 --description "ping" >/dev/null 2>&1 || { _log ERROR "ICMP rule creation failed"; return 1; }
fi

createMetalLBPort

###############################################################################
# Phase 4: SSH key management
###############################################################################
_log STEP "Phase 4: SSH key management"
createOrUpdateKeypair

###############################################################################
# Phase 5: Provision instances (jump host + Talos nodes)
###############################################################################
_log STEP "Phase 5: Provision instances"

# Jump host port
_jump_port=""
if ! JUMP_HOST_PORT=$(openstack port show ${LAB_NAME_PREFIX}-jump-mgmt-port -f value -c id 2>/dev/null); then
    _log INFO "Creating jump host management port"
    JUMP_HOST_PORT=$(openstack port create --security-group ${LAB_NAME_PREFIX}-secgroup \
        --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
        --network ${LAB_NAME_PREFIX}-net \
        -f value -c id ${LAB_NAME_PREFIX}-jump-mgmt-port 2>/dev/null)
    export JUMP_HOST_PORT
fi

# Floating IP for jump host
if ! JUMP_HOST_VIP=$(openstack floating ip list --port "${JUMP_HOST_PORT}" -f value -c "Floating IP Address" 2>/dev/null); then
    _log INFO "Creating jump host floating IP"
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port "${JUMP_HOST_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
elif [ -z "${JUMP_HOST_VIP}" ]; then
    _log INFO "Creating jump host floating IP"
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port "${JUMP_HOST_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
fi
export JUMP_HOST_VIP

# Create jump host server
if ! openstack server show ${LAB_NAME_PREFIX}-jump -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating jump host server"
    openstack server create ${LAB_NAME_PREFIX}-jump \
        --port "${JUMP_HOST_PORT}" \
        --image "${JUMP_HOST_IMAGE}" \
        --flavor "${JUMP_HOST_FLAVOR}" \
        --key-name ${LAB_NAME_PREFIX}-key >/dev/null 2>&1
fi

# Worker mgmt ports — parallel with jump host port check
_worker_mgmt_pids=()
for _i in 0 1 2; do
    (
        if ! openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f value -c id >/dev/null 2>&1; then
            if [ "$_i" -eq 0 ]; then
                openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                    --security-group ${LAB_NAME_PREFIX}-secgroup \
                    --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
                    --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                    --security-group ${LAB_NAME_PREFIX}-talos-secgroup \
                    --network ${LAB_NAME_PREFIX}-net \
                    -f value -c id ${LAB_NAME_PREFIX}-0-mgmt-port > /tmp/hyperconverged-port-0.id 2>/dev/null
            else
                openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                    --security-group ${LAB_NAME_PREFIX}-secgroup \
                    --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                    --network ${LAB_NAME_PREFIX}-net \
                    -f value -c id ${LAB_NAME_PREFIX}-${_i}-mgmt-port > /tmp/hyperconverged-port-${_i}.id 2>/dev/null
            fi
        else
            openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f value -c id > /tmp/hyperconverged-port-${_i}.id 2>/dev/null
        fi
    ) &
    _worker_mgmt_pids+=($!)
done

# Collect and export
for _idx in 0 1 2; do
    wait "${_worker_mgmt_pids[$_idx]}" 2>/dev/null || true
done

WORKER_0_PORT=$(cat "/tmp/hyperconverged-port-0.id" 2>/dev/null || openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id 2>/dev/null)
WORKER_1_PORT=$(cat "/tmp/hyperconverged-port-1.id" 2>/dev/null || openstack port show ${LAB_NAME_PREFIX}-1-mgmt-port -f value -c id 2>/dev/null)
WORKER_2_PORT=$(cat "/tmp/hyperconverged-port-2.id" 2>/dev/null || openstack port show ${LAB_NAME_PREFIX}-2-mgmt-port -f value -c id 2>/dev/null)
export WORKER_0_PORT WORKER_1_PORT WORKER_2_PORT

# Control plane floating IP
if ! CONTROL_PLANE_VIP=$(openstack floating ip list --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null); then
    _log INFO "Creating control plane floating IP"
    CONTROL_PLANE_VIP=$(openstack floating ip create PUBLICNET --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
elif [ -z "${CONTROL_PLANE_VIP}" ]; then
    _log INFO "Creating control plane floating IP"
    CONTROL_PLANE_VIP=$(openstack floating ip create PUBLICNET --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
fi
export CONTROL_PLANE_VIP

# Compute ports — parallel
_compute_pids=()
for _i in {100..109}; do
    if ! openstack port show ${LAB_NAME_PREFIX}-0-compute-float-${_i}-port 2>/dev/null; then
        openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
            --disable-port-security \
            --fixed-ip ip-address="192.168.102.${_i}" \
            ${LAB_NAME_PREFIX}-0-compute-float-${_i}-port &
        _compute_pids+=($!)
    fi
done
for _pid in "${_compute_pids[@]}"; do wait "$_pid" || true; done
_compute_pids=()

for _i in 0 1 2; do
    if ! openstack port show ${LAB_NAME_PREFIX}-${_i}-compute-port 2>/dev/null; then
        openstack port create --network ${LAB_NAME_PREFIX}-compute-net --disable-port-security \
            ${LAB_NAME_PREFIX}-${_i}-compute-port &
        _compute_pids+=($!)
    fi
done
for _pid in "${_compute_pids[@]}"; do wait "$_pid" || true; done

# Export compute ports
for _i in 0 1 2; do
    eval "COMPUTE_${_i}_PORT=\$(openstack port show ${LAB_NAME_PREFIX}-${_i}-compute-port -f value -c id 2>/dev/null || echo '')"
    export COMPUTE_${_i}_PORT
done

# Create Talos nodes — parallel
_server_pids=()
if ! openstack server show ${LAB_NAME_PREFIX}-0 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating Talos node ${LAB_NAME_PREFIX}-0"
    openstack server create ${LAB_NAME_PREFIX}-0 \
        --port "${WORKER_0_PORT}" \
        --port "${COMPUTE_0_PORT}" \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor "${OS_FLAVOR}" >/dev/null 2>&1 &
    _server_pids+=($!)
fi
if ! openstack server show ${LAB_NAME_PREFIX}-1 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating Talos node ${LAB_NAME_PREFIX}-1"
    openstack server create ${LAB_NAME_PREFIX}-1 \
        --port "${WORKER_1_PORT}" \
        --port "${COMPUTE_1_PORT}" \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor "${OS_FLAVOR}" >/dev/null 2>&1 &
    _server_pids+=($!)
fi
if ! openstack server show ${LAB_NAME_PREFIX}-2 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating Talos node ${LAB_NAME_PREFIX}-2"
    openstack server create ${LAB_NAME_PREFIX}-2 \
        --port "${WORKER_2_PORT}" \
        --port "${COMPUTE_2_PORT}" \
        --image "${TALOS_IMAGE_NAME}" \
        --flavor "${OS_FLAVOR}" >/dev/null 2>&1 &
    _server_pids+=($!)
fi
for _pid in "${_server_pids[@]}"; do wait "$_pid" || true; done

###############################################################################
# Phase 6: Wait ACTIVE
###############################################################################
_log STEP "Phase 6: Wait for nodes to reach ACTIVE"
_jump_pids=()

# Wait for jump host server (if new)
if openstack server show ${LAB_NAME_PREFIX}-jump 2>/dev/null; then
    (
        local _waited=0
        while true; do
            _status=$(openstack server show ${LAB_NAME_PREFIX}-jump -f value -c status 2>/dev/null || echo "UNKNOWN")
            if [ "$_status" = "ACTIVE" ]; then exit 0; fi
            if [ "$_status" = "ERROR" ]; then openstack server show ${LAB_NAME_PREFIX}-jump >&2; exit 1; fi
            sleep 5; _waited=$((_waited + 5))
            if [ $((_waited % 30)) -eq 0 ]; then _log "  ...jump host: ${_status} (${_waited}s)"; fi
            if [ $_waited -ge 600 ]; then echo "ERROR" > "/tmp/hyperconverged-jump.done"; exit 1; fi
        done
    ) &
    _jump_pids+=($!)
fi

# Wait for Talos nodes
_parallel_wait_servers_active "${LAB_NAME_PREFIX:-genestack}" 3 600 5

for _pid in "${_jump_pids[@]}"; do wait "$_pid" || true; done
_log INFO "Nodes are ACTIVE"

###############################################################################
# Phase 7: Wait for SSH
###############################################################################
_log STEP "Phase 7: Wait for SSH access"
_wait_ssh_reachable "${SSH_USERNAME}@${JUMP_HOST_VIP}" "Jump host SSH" 960 4

###############################################################################
# Phase 8: Install prerequisites on jump host
###############################################################################
_log STEP "Phase 8: Install prerequisites on jump host"
_ssh_tty <<'EOFPREREQ'
while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
    echo "Waiting for apt locks..."
    sleep 5
done
sudo apt-get update
sudo apt-get install -y curl wget git jq netcat-openbsd xz-utils yq
if ! command -v talosctl &>/dev/null; then
    wget "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/${TALOS_BINARY}" -O talosctl
    sudo install -o root -g root -m 0755 talosctl /usr/local/bin/talosctl
fi
if ! command -v kubectl &>/dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi
EOFPREREQ

###############################################################################
# Phase 9: Wait for Talos API
###############################################################################
_log STEP "Phase 9: Wait for Talos API"

# Resolve worker IPs first
_wait_ip_pids=()
for _i in 0 1 2; do
    (
        openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f json 2>/dev/null | jq -r '.fixed_ips[0].ip_address'
    ) &
    _wait_ip_pids+=($!)
done
for _i in 0 1 2; do
    eval "WORKER_${_i}_IP=\$(wait ${_wait_ip_pids[$_i]})"
    export WORKER_${_i}_IP
done
_log INFO "Worker IPs: ${WORKER_0_IP}, ${WORKER_1_IP}, ${WORKER_2_IP}"

_ssh_tty <<EOFWAIT
COUNT=0
while ! nc -z -w 2 ${WORKER_0_IP} 50000 2>/dev/null; do
    sleep 5
    COUNT=$((COUNT + 1))
    if [ \$COUNT -ge 60 ]; then
        echo "ERROR: Talos API not reachable after 300s" >&2; exit 1
    fi
done
echo "Talos API is reachable on ${WORKER_0_IP}"
EOFWAIT

###############################################################################
# Phase 10: Generate and apply Talos configuration
###############################################################################
_log STEP "Phase 10: Generate and apply Talos configuration"

_ssh_tty <<EOFTALOS
export TALOSCONFIG=/home/${SSH_USERNAME}/talos-config/talosconfig
TALOS_CONFIG_DIR=/home/${SSH_USERNAME}/talos-config

mkdir -p ${TALOS_CONFIG_DIR}
cd ${TALOS_CONFIG_DIR}

# Generate cluster config
talosctl gen config ${TALOS_CLUSTER_NAME} https://${WORKER_0_IP}:6443 --output .

# Write patch
cat > genestack-patch.yaml <<PATCH
machine:
  install:
    disk: /dev/sda
    wipe: false
  features:
    hostDNS:
      enabled: true
    kubeprism:
      enabled: true
      port: 7445
    containerImageFS: true
  kernel:
    modules:
      - name: rbd
      - name: nfs
      - name: overlay
  sysctls:
    net.core.somaxconn: "65535"
    net.ipv4.ip_forward: "1"
    vm.max_map_count: "262144"
kubeAPIServer:
  extraArgs:
    authorization-mode: "RBAC"
  extraVolumes:
    - name: longhorn-xfs
      hostPath: /var/lib/longhorn
      mountPath: /var/lib/longhorn
      readOnly: false
      propagation: Bidirectional
  extraMounts:
    - name: longhorn-xfs
      hostPath: /var/lib/longhorn
      mountPath: /var/lib/longhorn
      readOnly: false
      propagation: Bidirectional
network:
  cni:
    name: none
  dnsDomain: cluster.local
PATCH

# Apply patch to controlplane and worker configs
for cfg in controlplane.yaml worker.yaml; do
    if [ -f "$cfg" ]; then
        yq -i '.machine |= load("genestack-patch.yaml")' "$cfg"
    fi
done

# Apply configs to all nodes
talosctl apply-config --nodes ${WORKER_0_IP} --insecure --file controlplane.yaml
sleep 10
talosctl apply-config --nodes ${WORKER_1_IP} --insecure --file controlplane.yaml
talosctl apply-config --nodes ${WORKER_2_IP} --insecure --file controlplane.yaml

# Bootstrap the cluster
talosctl bootstrap --nodes ${WORKER_0_IP} --insecure --wait

# Download kubeconfig
talosctl kubeconfig . --nodes ${WORKER_0_IP} --insecure
mv kubeconfig /home/${SSH_USERNAME}/.kube/config
chown ${SSH_USERNAME}:${SSH_USERNAME} /home/${SSH_USERNAME}/.kube/config

# Verify cluster readiness
COUNT=0
while true; do
    if talosctl services --nodes ${WORKER_0_IP} --insecure 2>/dev/null | grep -i "wait" | grep -q -v "wait"; then
        break
    fi
    sleep 10; COUNT=$((COUNT + 1))
    if [ \$COUNT -ge 30 ]; then
        echo "ERROR: Cluster did not become ready after 300s" >&2; exit 1
    fi
done
echo "Talos cluster is ready"
EOFTALOS

###############################################################################
# Phase 11: Prepare Genestack source on jump host
###############################################################################
_log STEP "Phase 11: Prepare jump host source"
prepareJumpHostSource

###############################################################################
# Phase 12: Bootstrap and install cert-manager
###############################################################################
_log STEP "Phase 12: Bootstrap and install cert-manager"
_ssh_tty <<EOFCERT
sudo /opt/genestack/bootstrap.sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml
EOFCERT

###############################################################################
# Phase 13: Configure Genestack for Talos
###############################################################################
_log STEP "Phase 13: Configure Genestack for Talos"

# Write Talos-specific Kube-OVN config
_write_kube_ovn_talos() {
    sudo mkdir -p /etc/genestack/helm-configs/kube-ovn
    cat > /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml <<EOF
---
global:
  registry:
    address: docker.io/kubeovn
    imagePullSecrets: []
networking:
  IFACE: "$(ip -o r g 1 | awk '{print $5}')"
  vlan:
    VLAN_INTERFACE_NAME: "$(ip -o r g 1 | awk '{print $5}')"
OPENVSWITCH_DIR: /var/lib/openvswitch
OVN_DIR: /var/lib/ovn
DISABLE_MODULES_MANAGEMENT: true
EOF
}

# Write Rook-Ceph namespace overlay
_write_rook_ceph_talos() {
    sudo mkdir -p /etc/genestack/kustomize/rook-operator/overlay
    cat > /etc/genestack/kustomize/rook-operator/overlay/namespace-talos.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: rook-ceph
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
  name: rook-ceph
EOF
    cat > /etc/genestack/kustomize/rook-operator/overlay/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  - namespace-talos.yaml
EOF
}

_ssh_tty '
writeKubeOvnTalosConfig '/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml'
writeRookCephTalosNamespace '/etc/genestack/kustomize/rook-operator/overlay'
'

###############################################################################
# Phase 14: Write Genestack configurations
###############################################################################
_log STEP "Phase 14: Write Genestack configurations"
configureGenestackRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${METAL_LB_IP}" "${GATEWAY_DOMAIN}"

###############################################################################
# Phase 15: Deploy Genestack infrastructure
###############################################################################
_log STEP "Phase 15: Deploy Genestack infrastructure"

runGenestackSetupRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${GATEWAY_DOMAIN}" "${ACME_EMAIL}" "${DISABLE_OPENSTACK}"

###############################################################################
# Phase 16: Post-setup & testing
###############################################################################
_log STEP "Phase 16: Post-setup"

if [ "${RUN_EXTRAS}" -eq 1 ]; then
    installK9sRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
fi

if [ "${TEST_LEVEL}" = "off" ]; then
    waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
    createPostSetupResourcesRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}"
else
    if [ ${DISABLE_OPENSTACK} = "false" ]; then
        waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
        _log INFO "Running tests at level: ${TEST_LEVEL}"
        _ssh "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"
        mkdir -p test-results 2>/dev/null || true
        scp ${SSH_OPTS_STR} "${SSH_TARGET}:/tmp/test-results/*.xml" ./test-results/ 2>/dev/null || _log "No test result XML"
        scp ${SSH_OPTS_STR} "${SSH_TARGET}:/tmp/test-results/*.txt" ./test-results/ 2>/dev/null || _log "No test result TXT"
    fi
fi

###############################################################################
# Summary
###############################################################################
_log STEP "Deployment complete (${SECONDS}s)"

{ cat | tee /tmp/output.txt; } <<EOF
================================================================================
Talos Hyperconverged Lab Deployment Complete!
================================================================================

Deployment took ${SECONDS} seconds to complete.

Cluster Information:
  - Jump Host Address: ${JUMP_HOST_VIP}
  - Control Plane VIP: ${CONTROL_PLANE_VIP}
  - MetalLB Internal IP: ${METAL_LB_IP}
  - MetalLB Public VIP: ${METAL_LB_VIP}
  - Worker IPs: ${WORKER_0_IP}, ${WORKER_1_IP}, ${WORKER_2_IP}

SSH Access:
  ssh ${SSH_USERNAME}@${JUMP_HOST_VIP}

Talos/K8s Access (from jump host):
  talosctl --nodes ${WORKER_0_IP} version --insecure
  kubectl get nodes

Important Notes:
  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem
  - All cluster operations should be performed from the jump host
  - Talos config managed via talosctl — not kubectl directly
================================================================================
EOF
