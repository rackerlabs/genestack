#!/usr/bin/env bash
# Hyperconverged Lab — Kubespray Orchestrator
# Sourced via hyperconverged-lab.sh

# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
set -o pipefail
SECONDS=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Source helpers and modules (in dependency order)
source "${SCRIPT_DIR}/../lib/helpers.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/net.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/security.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/ssh-keys.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/transport.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/genestack-config.sh"
source "${SCRIPT_DIR}/../lib/hyperconverged/deploy.sh"

###############################################################################
# Global defaults
###############################################################################
export LAB_NETWORK_MTU="${LAB_NETWORK_MTU:-1500}"
export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"
export JUMP_HOST_IMAGE="${JUMP_HOST_IMAGE:-Ubuntu 24.04}"
export DISABLE_OPENSTACK="${DISABLE_OPENSTACK:-false}"
export TEST_LEVEL="${TEST_LEVEL:-full}"

# SSH defaults (overwritten by configure_ssh_transport if bastion)
SSH_TARGET="${SSH_USERNAME:-ubuntu}@${JUMP_HOST_VIP:-}"
SSH_OPTS_STR="-o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# Global defaults (overrides env vars — ensures script-level precedence)
export ACME_EMAIL="${ACME_EMAIL:-chris@breu.org}"
export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cloud.local}"
export OS_CLOUD="${OS_CLOUD:-dfw-dev-me}"
export OS_FLAVOR="${OS_FLAVOR:-gp.8.8.16}"
export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"

###############################################################################
# Phase 1: Initialize
###############################################################################
_log STEP "Phase 1: Initialize"###############################################################################
# Phase 1: Initialize
###############################################################################
_log STEP "Phase 1: Initialize"
export OS_IMAGE="${OS_IMAGE:-Ubuntu 24.04}"

###############################################################################
# Phase 2: OpenStack networking infrastructure
###############################################################################
_log STEP "Phase 2: OpenStack networking infrastructure"

# Router must go first (dependency for router add subnet)
createRouter

# Network + subnets (depend on router)
createNetworks || _log ERROR "Network creation failed"

# Security groups (independent of networking)
createCommonSecurityGroups

# Jump host specific secgroup (independent)
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

# MetalLB VIP port + floating IP
createMetalLBPort

# Compute ports (uses _parallel_compute_ports from helpers.sh)
# Then export COMPUTE_*_PORT
_parallel_compute_ports "${LAB_NAME_PREFIX}"

# Export compute port IDs
_log INFO "Exporting compute port IDs"
for _i in 0 1 2; do
    eval "COMPUTE_${_i}_PORT=\$(openstack port show ${LAB_NAME_PREFIX}-${_i}-compute-port -f value -c id 2>/dev/null)"
    eval "export COMPUTE_${_i}_PORT"
done
_log INFO "Compute ports ready: ${COMPUTE_0_PORT}, ${COMPUTE_1_PORT}, ${COMPUTE_2_PORT}"

###############################################################################
# Phase 3: SSH transport and key management
###############################################################################
_log STEP "Phase 3: SSH transport and key management"

# Create worker management ports — sequential to avoid TOCTOU races
_log INFO "Creating worker mgmt ports"
for _i in 0 1 2; do
    if ! openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f value -c id >/dev/null 2>&1; then
        if [ "${_i}" -eq 0 ]; then
            eval "WORKER_${_i}_PORT=\$(openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                --security-group ${LAB_NAME_PREFIX}-secgroup \
                --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
                --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                --network ${LAB_NAME_PREFIX}-net \
                -f value -c id ${LAB_NAME_PREFIX}-${_i}-mgmt-port 2>/dev/null)"
        else
            eval "WORKER_${_i}_PORT=\$(openstack port create --allowed-address ip-address=${METAL_LB_IP} \
                --security-group ${LAB_NAME_PREFIX}-secgroup \
                --security-group ${LAB_NAME_PREFIX}-http-secgroup \
                --network ${LAB_NAME_PREFIX}-net \
                -f value -c id ${LAB_NAME_PREFIX}-${_i}-mgmt-port 2>/dev/null)"
        fi
        eval "export WORKER_${_i}_PORT"
    else
        eval "WORKER_${_i}_PORT=\$(openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f value -c id 2>/dev/null)"
        eval "export WORKER_${_i}_PORT"
    fi
    eval "_worker_port_value=\${WORKER_${_i}_PORT}"
    if [ -z "${_worker_port_value}" ]; then
        _log ERROR "Failed to determine ${LAB_NAME_PREFIX}-${_i}-mgmt-port"
        exit 1
    fi
done
_log INFO "Worker ports: 0=${WORKER_0_PORT} 1=${WORKER_1_PORT} 2=${WORKER_2_PORT}"

# Floating IP for jump host (worker 0)
if ! JUMP_HOST_VIP=$(openstack floating ip list --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null); then
    _log INFO "Creating jump host floating IP"
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
elif [ -z "${JUMP_HOST_VIP}" ]; then
    _log INFO "Creating jump host floating IP"
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port "${WORKER_0_PORT}" -f value -c "Floating IP Address" 2>/dev/null)
fi
export JUMP_HOST_VIP

# Keypair management
createOrUpdateKeypair

# Bastion / SSH transport setup
configure_ssh_transport

###############################################################################
# Phase 4: Provision nodes
###############################################################################
_log STEP "Phase 4: Provision nodes"
_server_pids=()

if ! openstack server show ${LAB_NAME_PREFIX}-0 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating server ${LAB_NAME_PREFIX}-0"
    openstack server create ${LAB_NAME_PREFIX}-0 \
        --port "${WORKER_0_PORT}" \
        --port "${COMPUTE_0_PORT}" \
        --image "${OS_IMAGE}" \
        --flavor "${OS_FLAVOR}" \
        --key-name ${LAB_NAME_PREFIX}-key >/dev/null 2>&1 &
    _server_pids+=($!)
fi
if ! openstack server show ${LAB_NAME_PREFIX}-1 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating server ${LAB_NAME_PREFIX}-1"
    openstack server create ${LAB_NAME_PREFIX}-1 \
        --port "${WORKER_1_PORT}" \
        --port "${COMPUTE_1_PORT}" \
        --image "${OS_IMAGE}" \
        --flavor "${OS_FLAVOR}" \
        --key-name ${LAB_NAME_PREFIX}-key >/dev/null 2>&1 &
    _server_pids+=($!)
fi
if ! openstack server show ${LAB_NAME_PREFIX}-2 -f value -c status >/dev/null 2>&1; then
    _log INFO "Creating server ${LAB_NAME_PREFIX}-2"
    openstack server create ${LAB_NAME_PREFIX}-2 \
        --port "${WORKER_2_PORT}" \
        --port "${COMPUTE_2_PORT}" \
        --image "${OS_IMAGE}" \
        --flavor "${OS_FLAVOR}" \
        --key-name ${LAB_NAME_PREFIX}-key >/dev/null 2>&1 &
    _server_pids+=($!)
fi

for _pid in "${_server_pids[@]}"; do wait "$_pid" || true; done

###############################################################################
# Phase 5: Wait ACTIVE (parallel — ~20 min savings)
###############################################################################
_log STEP "Phase 5: Wait for nodes to reach ACTIVE"
_parallel_wait_servers_active 3 600 5 || exit 1

###############################################################################
# Phase 6: Wait for SSH
###############################################################################
_log STEP "Phase 6: Wait for SSH access"

# Wait for jump host SSH
wait_ssh_reachable "${SSH_TARGET}" "Jump host SSH" 960 4

###############################################################################
# Phase 7: Volume creation + attachment (parallel - if cinder enabled)
###############################################################################
if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
    _log STEP "Phase 7: Cinder volume attachment"

    _vol_pids=()
    for _i in 0 1 2; do
        if ! openstack volume show "${LAB_NAME_PREFIX}-${_i}-cv1" -f value -c status >/dev/null 2>&1; then
            _log INFO "Creating volume ${LAB_NAME_PREFIX}-${_i}-cv1"
            openstack volume create --size 150 --type Performance \
                --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-${_i}" \
                "${LAB_NAME_PREFIX}-${_i}-cv1" >/dev/null 2>&1 &
            _vol_pids+=($!)
        fi
    done
    for _pid in "${_vol_pids[@]}"; do
        wait "${_pid}" || true
    done

    _log STEP "  Waiting for volumes to become available"
    for _i in 0 1 2; do
        _waited=0
        while true; do
            _st=$(openstack volume show "${LAB_NAME_PREFIX}-${_i}-cv1" -f value -c status 2>/dev/null || echo "ERROR")
            case "${_st}" in
                available|in-use)
                    _log INFO "Volume ${LAB_NAME_PREFIX}-${_i}-cv1 ready"
                    break
                    ;;
            esac
            sleep 1
            _waited=$((_waited + 1))
            if [ "${_waited}" -ge 400 ]; then
                _log ERROR "Volume ${LAB_NAME_PREFIX}-${_i}-cv1 did not become ready"
                exit 1
            fi
        done
    done

    _log STEP "  Attaching volumes"
    _vol_attach_pids=()
    for _i in 0 1 2; do
        if [ "$(openstack volume show "${LAB_NAME_PREFIX}-${_i}-cv1" -f value -c status 2>/dev/null)" = "available" ]; then
            _log INFO "Attaching volume ${LAB_NAME_PREFIX}-${_i}-cv1"
            openstack server add volume --enable-delete-on-termination \
                "${LAB_NAME_PREFIX}-${_i}" "${LAB_NAME_PREFIX}-${_i}-cv1" >/dev/null 2>&1 &
            _vol_attach_pids+=($!)
        fi
    done
    for _pid in "${_vol_attach_pids[@]}"; do
        wait "${_pid}" || true
    done
    _log INFO "Cinder volumes attached"
else
    _log INFO "Skipping volume setup (HYPERCONVERGED_CINDER_VOLUME=false)"
fi

###############################################################################
# Phase 8: Host preparation
###############################################################################
_log STEP "Phase 8: Host preparation"

_wait_ip_pids=()
for _i in 0 1 2; do
    (
        openstack port show ${LAB_NAME_PREFIX}-${_i}-mgmt-port -f json 2>/dev/null | jq -r '.fixed_ips[0].ip_address' >"/tmp/${LAB_NAME_PREFIX}-${_i}-mgmt-ip"
    ) &
    _wait_ip_pids+=($!)
done

for _i in 0 1 2; do
    wait "${_wait_ip_pids[$_i]}"
    eval "WORKER_${_i}_IP=\$(cat /tmp/${LAB_NAME_PREFIX}-${_i}-mgmt-ip)"
    export WORKER_${_i}_IP
    rm -f "/tmp/${LAB_NAME_PREFIX}-${_i}-mgmt-ip"
done
_log INFO "Worker IPs: ${WORKER_0_IP}, ${WORKER_1_IP}, ${WORKER_2_IP}"

# SCP keys to jump host
_log INFO "Copying SSH keys to jump host"
scp ${SSH_OPTS_STR} ~/.ssh/${LAB_NAME_PREFIX}-key.pem "${SSH_USERNAME}@${JUMP_HOST_VIP}:~/.ssh/" 2>/dev/null || true
scp ${SSH_OPTS_STR} ~/.ssh/${LAB_NAME_PREFIX}-key.pub "${SSH_USERNAME}@${JUMP_HOST_VIP}:~/.ssh/" 2>/dev/null || true

# Write SSH config + /etc/hosts + .bashrc
_log INFO "Configuring SSH and /etc/hosts on all nodes"
_ssh_tty "cat > ~/.ssh/config <<'SSHCFG'
Host ${LAB_NAME_PREFIX}-0
    HostName ${WORKER_0_IP}
    User ${SSH_USERNAME}
    IdentityFile ~/.ssh/${LAB_NAME_PREFIX}-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host ${LAB_NAME_PREFIX}-1
    HostName ${WORKER_1_IP}
    User ${SSH_USERNAME}
    IdentityFile ~/.ssh/${LAB_NAME_PREFIX}-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host ${LAB_NAME_PREFIX}-2
    HostName ${WORKER_2_IP}
    User ${SSH_USERNAME}
    IdentityFile ~/.ssh/${LAB_NAME_PREFIX}-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host *
    UserKnownHostsFile /dev/null
SSHCFG
chmod 600 ~/.ssh/config"

# Parallel /etc/hosts + .bashrc on all workers
_write_host_pids=()
for _i in 0 1 2; do
    (
        _ssh_tty "if ! grep -q '${WORKER_0_IP:-0}' /etc/hosts 2>/dev/null; then
            echo '${WORKER_0_IP} ${LAB_NAME_PREFIX}-0.cluster.local ${LAB_NAME_PREFIX}-0' | sudo tee -a /etc/hosts >/dev/null
        fi
        if ! grep -q '${WORKER_1_IP:-0}' /etc/hosts 2>/dev/null; then
            echo '${WORKER_1_IP} ${LAB_NAME_PREFIX}-1.cluster.local ${LAB_NAME_PREFIX}-1' | sudo tee -a /etc/hosts >/dev/null
        fi
        if ! grep -q '${WORKER_2_IP:-0}' /etc/hosts 2>/dev/null; then
            echo '${WORKER_2_IP} ${LAB_NAME_PREFIX}-2.cluster.local ${LAB_NAME_PREFIX}-2' | sudo tee -a /etc/hosts >/dev/null
        fi
        if ! grep -qF 'source /opt/genestack/scripts/genestack.rc' ~/.bashrc 2>/dev/null; then
            echo 'source /opt/genestack/scripts/genestack.rc' >> ~/.bashrc
        fi"
    ) &
    _write_host_pids+=($!)
done
for _pid in "${_write_host_pids[@]}"; do wait "$_pid" || true; done

# RAK.Mirror.APT fix on jump host
_log INFO "Applying apt mirror workaround on jump host"
_configure_apt_sources "${JUMP_HOST_VIP}" "${SSH_OPTS_STR}" "${SSH_USERNAME}"

# Parallel APT fix on workers (from jump host via SSH)
_apt_pids=()
for _i in 1 2; do
    (
        _ssh_tty "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${SSH_USERNAME}@${LAB_NAME_PREFIX}-${_i} '${_configure_apt_sources_cmd}'" 2>/dev/null
    ) &
    _apt_pids+=($!)
done
for _pid in "${_apt_pids[@]}"; do wait "$_pid" || true; done
_log INFO "Host preparation complete"

###############################################################################
# Phase 9: Prepare Genestack source on jump host
###############################################################################
_log STEP "Phase 9: Prepare jump host source"

prepareJumpHostSource

###############################################################################
# Phase 10: Write Genestack configurations
###############################################################################
_log STEP "Phase 10: Write Genestack configurations"

configureGenestackRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${METAL_LB_IP}" "${GATEWAY_DOMAIN}"

###############################################################################
# Phase 11: Kubespray cluster deployment (~20-40 min)
###############################################################################
_log STEP "Phase 11: Deploy Kubespray (~20-40 min)"

# Generate inventory and run kubespray via a single remote block
_ssh_tty <<'EOCKUBESPRAY'
set -e
# Host bootstrap
if [ ! -f "/usr/local/bin/queue_max.sh" ]; then
    python3 -m venv ~/.venvs/genestack
    ~/.venvs/genestack/bin/pip install -r /opt/genestack/requirements.txt
    source /opt/genestack/scripts/genestack.rc
    ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml --become -e host_required_kernel=$(uname -r)
fi

# Kubespray cluster.yml
if [ ! -d "/var/lib/kubelet" ]; then
    source /opt/genestack/scripts/genestack.rc
    KUBESPRAY_DIR=/opt/genestack/submodules/kubespray
    if [ ! -f "${KUBESPRAY_DIR}/cluster.yml" ] && [ ! -f "${KUBESPRAY_DIR}/playbooks/cluster.yml" ]; then
        echo "Kubespray checkout missing, initializing submodule..."
        pushd /opt/genestack >/dev/null
            sudo git config --global --add safe.directory /opt/genestack
            sudo git submodule sync --recursive
            sudo git submodule update --init --recursive submodules/kubespray
        popd >/dev/null
    fi
    KUBESPRAY_PLAYBOOK=
    if [ -f "${KUBESPRAY_DIR}/cluster.yml" ]; then
        KUBESPRAY_PLAYBOOK="${KUBESPRAY_DIR}/cluster.yml"
    elif [ -f "${KUBESPRAY_DIR}/playbooks/cluster.yml" ]; then
        KUBESPRAY_PLAYBOOK="${KUBESPRAY_DIR}/playbooks/cluster.yml"
    fi
    if [ -z "${KUBESPRAY_PLAYBOOK}" ]; then
        echo "ERROR: Kubespray cluster playbook not found in ${KUBESPRAY_DIR}"
        exit 1
    fi
    cd "${KUBESPRAY_DIR}"
    ANSIBLE_SSH_PIPELINING=0 ansible-playbook "${KUBESPRAY_PLAYBOOK}" --become || true
fi
sudo mkdir -p /opt/kube-plugins
sudo chown ${USER}:${USER} /opt/kube-plugins
pushd /opt/kube-plugins
    if [ ! -f "/usr/local/bin/kubectl" ]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    fi
    if [ ! -f "/usr/local/bin/kubectl-convert" ]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
        sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
    fi
    if [ ! -f "/usr/local/bin/kubectl-ko" ]; then
        curl -LO https://raw.githubusercontent.com/kubeovn/kube-ovn/refs/heads/release-1.12/dist/images/kubectl-ko
        sudo install -o root -g root -m 0755 kubectl-ko /usr/local/bin/kubectl-ko
    fi
popd
EOCKUBESPRAY

###############################################################################
# Phase 12: Wait for Kube-OVN to be Ready (critical — pods need IPs!)
###############################################################################
_log STEP "Phase 12: Wait for Kube-OVN to be ready (critical path)"

_wait_kube_ovn() {
    local _max_wait=1800 _interval=30 _elapsed=0
    while true; do
        if _ssh "kubectl -n kube-ovn get pods -l app.kubernetes.io/name=kube-ovn-cni 2>/dev/null | grep -q Running" \
            && _ssh "kubectl -n kube-ovn get pods -l app.kubernetes.io/name=kube-ovn-controller 2>/dev/null | grep -q Running"; then
            _log INFO "Kube-OVN is ready"
            return 0
        fi
        _elapsed=$((_elapsed + _interval))
        if [ $((_elapsed % 60)) -eq 0 ]; then
            _log "  Kube-OVN not ready yet (${_elapsed}s)"
        fi
        if [ ${_elapsed} -ge ${_max_wait} ]; then
            _log "WARN: Kube-OVN readiness check timed out after ${_elapsed}s"
            return 1
        fi
        sleep ${_interval}
    done
}
_wait_kube_ovn || _log WARN "Proceeding — other pods may take longer to start"

###############################################################################
# Phase 13: Deploy Genestack infrastructure
###############################################################################
_log STEP "Phase 13: Deploy Genestack infrastructure"

# Run setup-infrastructure (longhorn + kube-ovn + rook)
# The infrastructure script includes kube-ovn but since Phase 12 already
# verified it's ready, we can skip kube-ovn re-install via flag
_log INFO "Installing OpenStack Infrastructure"
ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    "${SSH_USERNAME}@${JUMP_HOST_VIP}" \
    "sudo LONGHORN_STORAGE_REPLICAS=1 GATEWAY_DOMAIN='${GATEWAY_DOMAIN}' ACME_EMAIL='${ACME_EMAIL}' HYPERCONVERGED=true /opt/genestack/bin/setup-infrastructure.sh" 2>&1 | tee -a /tmp/hyperconverged-kubespray.log

if [ "${DISABLE_OPENSTACK}" = "false" ]; then
    _log INFO "Installing OpenStack"
    _ssh_tty "sudo /opt/genestack/bin/setup-openstack.sh"
    _ssh_tty "sudo /opt/genestack/bin/setup-openstack-rc.sh"
fi

###############################################################################
# Phase 14: Post-setup & testing
###############################################################################
_log STEP "Phase 14: Post-setup"

# Install cinder backends via cinderVolumeSetup (if enabled and not disabled)
if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ] && [ "${DISABLE_OPENSTACK}" = "false" ]; then
    _log INFO "Setting up Cinder volume backends"
    cinderVolumeSetup
fi

# Install Octavia preconf
if [ "${RUN_EXTRAS}" -eq 1 ]; then
    _log INFO "Installing Octavia preconf"
    install_preconf_octavia
    _log INFO "Installing Octavia"
    _ssh_tty "sudo /opt/genestack/bin/install.sh --service octavia"
fi

# Install k9s
if [ "${RUN_EXTRAS}" -eq 1 ]; then
    installK9sRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
fi

# Tests vs API ready
if [ "${TEST_LEVEL}" = "off" ]; then
    waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
    createPostSetupResourcesRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}"
    deployTrove "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}" "${COMPUTE_SUBNET_CIDR:-192.168.102.0/24}" "${MGMT_SUBNET_CIDR:-192.168.100.0/24}"
else
    if [ ${DISABLE_OPENSTACK} = "false" ]; then
        waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"
        _log INFO "Running tests at level: ${TEST_LEVEL}"
        _ssh "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"
        mkdir -p test-results 2>/dev/null || true
        scp ${SSH_OPTS_STR} "${SSH_TARGET}:/tmp/test-results/*.xml" ./test-results/ 2>/dev/null || _log "No test result XML files found"
        scp ${SSH_OPTS_STR} "${SSH_TARGET}:/tmp/test-results/*.txt" ./test-results/ 2>/dev/null || _log "No test result text files found"
    fi
fi

###############################################################################
# Summary
###############################################################################
_log STEP "Deployment complete (${SECONDS}s)"

_DISPLAY_JUMP_VIP="${JUMP_HOST_VIP_REAL:-${JUMP_HOST_VIP}}"
if [ -n "${SSH_GATEWAY:-}" ]; then
    _SSH_HINT="ssh -A -o KexAlgorithms=+diffie-hellman-group1-sha1 \
-o Ciphers=aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc \
-o MACs=hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com \
-o GSSAPIAuthentication=no \
\"gu=${SSH_USER:-${USER}}@${SSH_DEST_USER:-${SSH_USERNAME}}@${_DISPLAY_JUMP_VIP}@${SSH_GATEWAY}\""
else
    _SSH_HINT="ssh ${SSH_USERNAME}@${_DISPLAY_JUMP_VIP}"
fi

_log INFO "================================================================================"
_log INFO "Kubespray Hyperconverged Lab Deployment Complete!"
_log INFO "Timestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')"
_log INFO "================================================================================"
_log INFO "Cluster Information:"
_log INFO "  - Jump Host Address: ${_DISPLAY_JUMP_VIP}"
_log INFO "  - MetalLB Internal IP: ${METAL_LB_IP}"
_log INFO "  - MetalLB Public VIP: ${METAL_LB_VIP}"
_log INFO ""
_log INFO "SSH Access:"
_log INFO "  ${_SSH_HINT}"
_log INFO ""
_log INFO "Kubernetes Access (from jump host):"
_log INFO "  kubectl get nodes"
_log INFO ""
_log INFO "Important Notes:"
_log INFO "  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem"
_log INFO "  - All cluster operations should be performed from the jump host"
_log INFO "================================================================================"

# Write structured output for machine parsing
cat > "/tmp/hyperconverged-kubespray-output.txt" <<OUTEOF
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
duration_seconds=${SECONDS}
lab_name_prefix=${LAB_NAME_PREFIX}
jump_host=${_DISPLAY_JUMP_VIP}
metal_lb_internal=${METAL_LB_IP}
metal_lb_vip=${METAL_LB_VIP}
worker_0_ip=${WORKER_0_IP}
worker_1_ip=${WORKER_1_IP}
worker_2_ip=${WORKER_2_IP}
ssh_user=${SSH_USERNAME}
OUTEOF
_log INFO "Structured output written to /tmp/hyperconverged-kubespray-output.txt"
