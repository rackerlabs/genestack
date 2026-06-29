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
# Kubespray-Specific: SSH Key Management
#############################################################################

if [ ! -d "~/.ssh" ]; then
    echo "Creating the SSH directory"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
fi

KEY_NAME="${LAB_NAME_PREFIX}-key"
KEY_PEM="${HOME}/.ssh/${KEY_NAME}.pem"
KEY_PUB="${HOME}/.ssh/${KEY_NAME}.pub"

if [ ! -f "${KEY_PEM}" ]; then
    # Create a new keypair in OpenStack and persist the private/public keys locally.
    openstack keypair delete "${KEY_NAME}" >/dev/null 2>&1 || true
    openstack keypair create "${KEY_NAME}" >"${KEY_PEM}"
    chmod 600 "${KEY_PEM}"
    openstack keypair show "${KEY_NAME}" --public-key >"${KEY_PUB}"
else
    # Ensure a matching local .pub exists and reconcile OpenStack keypair if needed.
    if [ ! -f "${KEY_PUB}" ]; then
        ssh-keygen -y -f "${KEY_PEM}" >"${KEY_PUB}"
    fi

    LOCAL_PUB=$(tr -d '\n' <"${KEY_PUB}")
    REMOTE_PUB=$(openstack keypair show "${KEY_NAME}" -f value -c public_key 2>/dev/null || true)
    if [ -z "${REMOTE_PUB}" ] || [ "${LOCAL_PUB}" != "${REMOTE_PUB}" ]; then
        echo "Reconciling keypair ${KEY_NAME} in OpenStack to match local key."
        openstack keypair delete "${KEY_NAME}" >/dev/null 2>&1 || true
        openstack keypair create "${KEY_NAME}" --public-key "${KEY_PUB}"
    fi
fi

ssh-add "${KEY_PEM}"

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
# Configure SSH transport
#
# Building labs and accessing jump host behind a bastion requires 'special'
#  ssh command execution in order to 'tunnel' through the bastion. The 'special' nature
#  of the ssh commands is encapsulated in helper functions. However, the following
#  environment variables must also be setup in order for the 'tunneling' to work:
# export SSH_GATEWAY=support.dfw1.gateway.rackspace.com
# export SSH_USER=<SSO username>
# export SSH_DEST_USER=ubuntu
# export SSH_LOCAL_PORT=12222
#
# We route every ssh/scp/rsync through the bastion
# directly using the gu= form, with ControlMaster + ControlPersist so
# we only pay the gateway-auth latency on the first call. Subsequent
# ssh invocations reuse the master socket and are local-fast.
#
# When SSH_GATEWAY is set:
#   1. Wait for openstack server status=ACTIVE on the jump host.
#   2. Build SSH_TARGET = "gu=USER@DEST@VIP@GATEWAY" and
#      SSH_OPTS_STR with legacy crypto + ControlMaster opts.
#   3. Open the master connection (retry until the back-end sshd
#      answers a no-op `exit` command — proves end-to-end auth).
#   4. Trap EXIT to close the master socket cleanly.
#
# When SSH_GATEWAY is unset, SSH_TARGET stays at the direct
# ${SSH_USERNAME}@${JUMP_HOST_VIP} form — no behavior change for users
# whose clouds don't sit behind a bastion.
#############################################################################

# ----- Wait for the jump host to reach ACTIVE -----
# Whether a bastion is involved or not, every downstream step depends on
# the VM being scheduled. Surface ERROR state immediately if Nova fails.
echo "Waiting for ${LAB_NAME_PREFIX}-0 to reach ACTIVE"
_active_attempts=0
_active_max=120  # ~10 min at 5s sleep
while true; do
    _status=$(openstack server show ${LAB_NAME_PREFIX}-0 -f value -c status 2>/dev/null || echo "UNKNOWN")
    if [ "${_status}" = "ACTIVE" ]; then
        break
    fi
    if [ "${_status}" = "ERROR" ]; then
        echo "ERROR: ${LAB_NAME_PREFIX}-0 reached ERROR state — aborting" >&2
        openstack server show ${LAB_NAME_PREFIX}-0 >&2 || true
        exit 1
    fi
    _active_attempts=$((_active_attempts + 1))
    if [ ${_active_attempts} -ge ${_active_max} ]; then
        echo "ERROR: ${LAB_NAME_PREFIX}-0 never reached ACTIVE (last status: ${_status})" >&2
        exit 1
    fi
    if [ $((_active_attempts % 6)) -eq 0 ]; then
        echo "  ...status=${_status} (attempt ${_active_attempts}/${_active_max})"
    fi
    sleep 5
done
echo "  ${LAB_NAME_PREFIX}-0 is ACTIVE"

# SSH_TARGET and SSH_OPTS_STR are populated below.
# Until then they default to the "no bastion" form (direct ssh to the
# jump host), which lets the helpers be safely defined ahead of the
# JUMP_HOST_VIP allocation. None of the helpers are *called* before
# SSH_TARGET and SSH_OPTS_STR are populated.
#
# SSH_OPTS_STR is intentionally unquoted at use sites — bash
# word-splits it into separate argv. None of our option values contain
# spaces (KexAlgorithms=+x, Ciphers=a,b,c, etc.), so this is safe.
SSH_TARGET="${SSH_USERNAME:-ubuntu}@${JUMP_HOST_VIP:-}"
SSH_OPTS_STR="-o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

if [ -n "${SSH_GATEWAY:-}" ]; then
    echo "SSH_GATEWAY is set so setting up for access through the bastion"
    SSH_USER="${SSH_USER:-${USER}}"
    SSH_DEST_USER="${SSH_DEST_USER:-${SSH_USERNAME}}"
    SSH_CONTROL_PATH="/tmp/hyperconverged-lab-ssh-$$.sock"

    # Build the ssh transport: target is the inband gu= form; opts cover
    # legacy crypto, GSSAPI off (avoids a multi-second auth probe delay),
    # and a master socket so subsequent calls don't re-auth through the
    # gateway.
    # None of these option values contain spaces, so word-splitting at
    # use sites (`ssh ${SSH_OPTS_STR} ...`) is safe.
    SSH_TARGET="gu=${SSH_USER}@${SSH_DEST_USER}@${JUMP_HOST_VIP}@${SSH_GATEWAY}"
    SSH_OPTS_STR="-o ForwardAgent=yes \
-o UserKnownHostsFile=/dev/null \
-o StrictHostKeyChecking=accept-new \
-o GSSAPIAuthentication=no \
-o KexAlgorithms=+diffie-hellman-group1-sha1 \
-o Ciphers=aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc \
-o MACs=hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com \
-o ControlMaster=auto \
-o ControlPath=${SSH_CONTROL_PATH} \
-o ControlPersist=2h \
-o ServerAliveInterval=60 \
-o ServerAliveCountMax=120"

    # Stash the real public IP for the final summary
    export JUMP_HOST_VIP_REAL="${JUMP_HOST_VIP}"

    # Clean up any stale master socket from a previous aborted run
    if [ -S "${SSH_CONTROL_PATH}" ]; then
        echo "Cleaning up stale ssh control socket at ${SSH_CONTROL_PATH}"
        rm -f "${SSH_CONTROL_PATH}"
    fi

    # Tear the master socket down on script exit (success, failure, Ctrl-C)
    trap 'ssh '"${SSH_OPTS_STR}"' -O exit "'"${SSH_TARGET}"'" 2>/dev/null || true; rm -f "'"${SSH_CONTROL_PATH}"'" 2>/dev/null || true' EXIT

    echo "Opening bastion connection via ${SSH_GATEWAY}"
    echo "  (every subsequent ssh/scp/rsync rides this socket — first connect can take ~10s)"
fi

#############################################################################
# Wait for Jump Host SSH Access
#############################################################################
# Bumped to ~16 min (240 × 4s) — Rackspace flex VMs can take 5+ minutes
# of cloud-init before sshd answers public-key auth. ConnectTimeout=4
# keeps each attempt bounded so total wall time is predictable.
#
# This loop also serves as the ControlMaster opener when SSH_GATEWAY
# is set — the first successful ssh call establishes the master socket,
# and every subsequent _ssh / scp / rsync rides it.

echo "Waiting for the jump host (VIP: ${JUMP_HOST_VIP}) to accept SSH auth"
COUNT=0
while ! ssh ${SSH_OPTS_STR} -o ConnectTimeout=8 -q "${SSH_TARGET}" exit 2>/dev/null; do
    sleep 4
    COUNT=$((COUNT + 1))
    if [ $((COUNT % 15)) -eq 0 ]; then
        echo "  ...SSH still not ready (attempt ${COUNT}/240)"
    fi
    if [ $COUNT -gt 240 ]; then
        echo "Failed to ssh into the jump host after ~16 min"
        exit 1
    fi
done
echo "  Jump host is ready"

#############################################################################
# Create and Attach Lab Volumes
#############################################################################

if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
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
        --size 150 \
        --type Performance \
        --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-0" \
        ${LAB_NAME_PREFIX}-0-cv1
    fi

    if ! openstack volume show ${LAB_NAME_PREFIX}-1-cv1 2>/dev/null; then
      openstack volume create \
        --size 150 \
        --type Performance \
        --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-1" \
        ${LAB_NAME_PREFIX}-1-cv1
    fi

    if ! openstack volume show ${LAB_NAME_PREFIX}-2-cv1 2>/dev/null; then
      openstack volume create \
        --size 150 \
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
# Resolve worker IPs (needed for inventory before Kubespray)
#############################################################################

_net_name="${LAB_NAME_PREFIX}-net"
WORKER_0_IP=$(openstack server show ${LAB_NAME_PREFIX}-0 -f json | jq -r '.addresses' | jq --arg n "${_net_name}" -r '.[$n][0]')
WORKER_1_IP=$(openstack server show ${LAB_NAME_PREFIX}-1 -f json | jq -r '.addresses' | jq --arg n "${_net_name}" -r '.[$n][0]')
WORKER_2_IP=$(openstack server show ${LAB_NAME_PREFIX}-2 -f json | jq -r '.addresses' | jq --arg n "${_net_name}" -r '.[$n][0]')

echo "Worker IPs: ${WORKER_0_IP}, ${WORKER_1_IP}, ${WORKER_2_IP}"

#############################################################################
# Copy SSH keys to jump host
#############################################################################

echo "Copying SSH keys to jump host..."
scp ${SSH_OPTS_STR} \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pem \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pub \
    "${SSH_TARGET}:/home/${SSH_USERNAME}/.ssh/"
_ssh "chmod 600 ~/.ssh/${LAB_NAME_PREFIX}-key.pem && chmod 644 ~/.ssh/${LAB_NAME_PREFIX}-key.pub"

#############################################################################
# Write ~/.ssh/config on jump host
#############################################################################

echo "Writing SSH config on jump host..."
_ssh <<SSHCFG
cat > ~/.ssh/config <<EOF
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

#############################################################################
# Populate /etc/hosts on jump host
#############################################################################

echo "Updating /etc/hosts on jump host..."
_ssh <<ETCHOSTS
if ! grep -q "${LAB_NAME_PREFIX}-0.cluster.local" /etc/hosts; then
    sudo tee -a /etc/hosts >/dev/null <<EOF
# BEGIN hyperconverged lab nodes
${WORKER_0_IP} ${LAB_NAME_PREFIX}-0.cluster.local ${LAB_NAME_PREFIX}-0
${WORKER_1_IP} ${LAB_NAME_PREFIX}-1.cluster.local ${LAB_NAME_PREFIX}-1
${WORKER_2_IP} ${LAB_NAME_PREFIX}-2.cluster.local ${LAB_NAME_PREFIX}-2
# END hyperconverged lab nodes
EOF
fi
ETCHOSTS

echo "Updating ${HOME}/.bashrc on jump host..."
_ssh <<BASHRC
# Make genestack.rc auto-source on login so interactive shells inherit
# OS_CLOUD, kubeconfig, the genestack venv, etc. without manual sourcing.
if ! grep -qF "source /opt/genestack/scripts/genestack.rc" \${HOME}/.bashrc 2>/dev/null; then
    echo "source /opt/genestack/scripts/genestack.rc" >> \${HOME}/.bashrc
fi
BASHRC

#############################################################################
# BEGIN WORKAROUND: rax.mirror.rackspace.com GPG signature failures
#
# The outer-cloud vendordata writes rax.mirror.rackspace.com into apt sources
# on every fresh instance via cloud-init. The mirror has been intermittently
# returning InRelease files with invalid signatures (observed 2026-04-29 to
# 2026-04-30), which kills any apt operation downstream — bootstrap.sh,
# host-setup.yml, and the cinder_volumes role's "Install cinder distro
# packages" task all fail.
#
# Swap the mirror to archive.ubuntu.com on the jump host and all three
# workers before any apt operation runs. The jump host SSH config and
# /etc/hosts entries above let us reach workers from the jump host.
#
# Remove this block once the upstream mirror / vendordata issue is fixed.
#############################################################################
echo "Applying rax.mirror -> archive.ubuntu.com workaround on jump host and workers..."

# The fix runs identical commands on each node — define once, run via SSH.
# 1) sed rewrites *any* rax.mirror.rackspace.com reference (any path) to
#    archive.ubuntu.com inside every apt source file (.list and .sources).
# 2) Any source file whose *name* contains rax.mirror.rackspace.com is
#    moved aside in case it has references our sed didn't catch (e.g.,
#    Signed-By: keyring paths in DEB822 format).
# 3) apt-get clean flushes /var/lib/apt/lists so apt-update re-fetches
#    InRelease fresh rather than serving a cached bad signature.
# Apt lock wait + sed/rm + apt-get update. The lock wait keeps us from
# colliding with cloud-init / unattended-upgrades, which on a freshly
# booted node hold the apt locks for several minutes after first boot.
APT_FIX_CMD='for _i in $(seq 1 60); do sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1 || break; echo "  waiting for apt locks (${_i}/60)..."; sleep 5; done; sudo sed -i "s|rax\.mirror\.rackspace\.com|archive.ubuntu.com|g" /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; for f in /etc/apt/sources.list.d/*rax.mirror.rackspace.com*; do [ -e "$f" ] && sudo rm -f "$f"; done 2>/dev/null || true; sudo apt-get clean >/dev/null; sudo apt-get update >/dev/null'

_ssh "${APT_FIX_CMD}"

# Don't `set -e` here — we want to iterate over every worker and report
# any individual failures at the end, rather than aborting on the first
# bad node and leaving the others unfixed.
_ssh <<APTFIX_WORKERS
APT_FAILED_NODES=()
# -0 is the jump host (already patched above); only the other two workers
# need to be reached via SSH from the jump host.
for node in ${LAB_NAME_PREFIX}-1 ${LAB_NAME_PREFIX}-2; do
    echo "  Waiting for SSH on \$node..."
    for i in \$(seq 1 30); do
        ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \$node true 2>/dev/null && break
        sleep 5
    done
    echo "  Patching apt sources on \$node..."
    if ! ssh \$node '${APT_FIX_CMD}'; then
        echo "  ERROR: apt fix failed on \$node — will verify and report" >&2
        APT_FAILED_NODES+=(\$node)
    fi
done

# A failed apt-get update doesn't necessarily mean the sources are still
# pointing at rax.mirror — the sed step is independent and runs first.
# Verify each previously-failed node by checking if any rax.mirror reference
# remains in the apt config; if not, it's a transient lock issue we can
# ignore. If references remain, fail the workaround so the operator catches
# it before host-setup tries to apt-get on that node.
HARD_FAILED=()
for node in "\${APT_FAILED_NODES[@]}"; do
    if ssh \$node "grep -rq 'rax\\.mirror\\.rackspace\\.com' /etc/apt/ 2>/dev/null"; then
        HARD_FAILED+=(\$node)
    else
        echo "  \$node: sources clean despite apt-get update failure (transient lock)"
    fi
done
if [ \${#HARD_FAILED[@]} -gt 0 ]; then
    echo "ERROR: rax.mirror references still present on: \${HARD_FAILED[*]}" >&2
    echo "       host-setup will fail on these nodes. Re-run apt fix manually." >&2
    exit 1
fi
APTFIX_WORKERS
#############################################################################
# END WORKAROUND
#############################################################################

#############################################################################
# Kubespray-Specific: Bootstrap and deploy codebase on Jump Host
#############################################################################

prepareJumpHostSource

#############################################################################
# Kubespray-Specific: Remote Configuration via SSH
#############################################################################

_ssh <<EOC
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
    if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
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
            storage_network_multipath: false
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Block Nodes
        storage_nodes:
          vars:
            enable_iscsi: true
            cinder_backend_name: lvmdriver-1
            cinder_worker_name: lvm
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
            storage_network_multipath: false
          hosts:
            ${LAB_NAME_PREFIX}-0.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-1.${GATEWAY_DOMAIN}: null
            ${LAB_NAME_PREFIX}-2.${GATEWAY_DOMAIN}: null
        # Block Nodes
        storage_nodes:
          vars:
            enable_iscsi: true
            cinder_backend_name: lvmdriver-1
            cinder_worker_name: lvm
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
fi

EOC

#############################################################################
# Write Service Helm Overrides and Endpoints (common function)
#############################################################################

configureGenestackRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${METAL_LB_IP}" "${GATEWAY_DOMAIN}"

#############################################################################
# Kubespray-Specific: Run Host Setup and Kubespray
#############################################################################

_ssh <<EOC
set -e
if [ ! -f "/usr/local/bin/queue_max.sh" ]; then
    python3 -m venv ~/.venvs/genestack
    ~/.venvs/genestack/bin/pip install -r /opt/genestack/requirements.txt
    source /opt/genestack/scripts/genestack.rc
    ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml --become -e host_required_kernel=\$(uname -r)
fi
if [ ! -d "/var/lib/kubelet" ]; then
    source /opt/genestack/scripts/genestack.rc
    KUBESPRAY_DIR=/opt/genestack/submodules/kubespray
    if [ ! -f "\${KUBESPRAY_DIR}/cluster.yml" ] && [ ! -f "\${KUBESPRAY_DIR}/playbooks/cluster.yml" ]; then
        echo "Kubespray checkout missing, initializing submodule..."
        pushd /opt/genestack >/dev/null
            sudo git config --global --add safe.directory /opt/genestack
            sudo git config --global --add safe.directory /opt/genestack/submodules/*
            sudo git submodule sync --recursive
            sudo git submodule update --init --recursive submodules/kubespray
        popd >/dev/null
    fi
    KUBESPRAY_PLAYBOOK=
    if [ -f "\${KUBESPRAY_DIR}/cluster.yml" ]; then
        KUBESPRAY_PLAYBOOK="\${KUBESPRAY_DIR}/cluster.yml"
    elif [ -f "\${KUBESPRAY_DIR}/playbooks/cluster.yml" ]; then
        KUBESPRAY_PLAYBOOK="\${KUBESPRAY_DIR}/playbooks/cluster.yml"
    fi

    if [ -z "\${KUBESPRAY_PLAYBOOK}" ]; then
        echo "ERROR: Kubespray cluster playbook not found in \${KUBESPRAY_DIR}"
        ls -la "\${KUBESPRAY_DIR}" || true
        ls -la "\${KUBESPRAY_DIR}/playbooks" || true
        exit 1
    fi

    cd "\${KUBESPRAY_DIR}"
    ANSIBLE_SSH_PIPELINING=0 ansible-playbook "\${KUBESPRAY_PLAYBOOK}" --become
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

runGenestackSetupRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${GATEWAY_DOMAIN}" "${ACME_EMAIL}" "${DISABLE_OPENSTACK}"

#############################################################################
# Cinder Volume Setup
#############################################################################
if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ] && [ ${DISABLE_OPENSTACK} = "false" ]; then
  cinderVolumeSetup
fi

#############################################################################
# Octavia per-configuration
#############################################################################
if [ "${RUN_EXTRAS}" -eq 1 ] && [ ${DISABLE_OPENSTACK} = "false" ]; then
  install_preconf_octavia
fi

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
    
    createPostSetupResourcesRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}"

    # Trove Setup & Installation
    # Must be run after the flat network has been created
    deployTrove "${SSH_USERNAME}" "${JUMP_HOST_VIP}" "${LAB_NAME_PREFIX}" "${COMPUTE_SUBNET_CIDR}" "${MGMT_SUBNET_CIDR}"

else
    # Wait for Nova and Neutron APIs to be ready before proceeding
    if [ ${DISABLE_OPENSTACK} = "false" ]; then
        waitForOpenStackAPIsReadyRemote "${SSH_USERNAME}" "${JUMP_HOST_VIP}"

        echo "Running tests at level: ${TEST_LEVEL}"

        _ssh "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"
        mkdir -p test-results
        scp ${SSH_OPTS_STR} \
            "${SSH_TARGET}:/tmp/test-results/*.xml" ./test-results/ 2>/dev/null || echo "No test result XML files found"
        scp ${SSH_OPTS_STR} \
            "${SSH_TARGET}:/tmp/test-results/*.txt" ./test-results/ 2>/dev/null || echo "No test result text files found"
    fi
fi
#############################################################################
# Output Summary
#############################################################################

# When going through a bastion, the public IP isn't directly reachable —
# show the inband gu= command the user can paste to get a shell. The
# script's own ControlMaster socket is gone after EXIT, so we print a
# self-contained command rather than referencing it.
_DISPLAY_JUMP_VIP="${JUMP_HOST_VIP_REAL:-${JUMP_HOST_VIP}}"
if [ -n "${SSH_GATEWAY:-}" ]; then
    _SSH_HINT="ssh -A \\
    -o KexAlgorithms=+diffie-hellman-group1-sha1 \\
    -o Ciphers=aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc \\
    -o MACs=hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-64@openssh.com \\
    -o GSSAPIAuthentication=no \\
    \"gu=${SSH_USER}@${SSH_DEST_USER}@${_DISPLAY_JUMP_VIP}@${SSH_GATEWAY}\""
else
    _SSH_HINT="ssh ${SSH_USERNAME}@${_DISPLAY_JUMP_VIP}"
fi

{ cat | tee /tmp/output.txt; } <<EOF
================================================================================
Kubespray Hyperconverged Lab Deployment Complete!
================================================================================

Deployment took ${SECONDS} seconds to complete.

Cluster Information:
  - Jump Host Address: ${_DISPLAY_JUMP_VIP}
  - MetalLB Internal IP: ${METAL_LB_IP}
  - MetalLB Public VIP: ${METAL_LB_VIP}

SSH Access:
  ${_SSH_HINT}

Kubernetes Access (from jump host):
  kubectl get nodes

Important Notes:
  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem
  - All cluster operations should be performed from the jump host
================================================================================
EOF
