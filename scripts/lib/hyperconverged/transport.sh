#!/usr/bin/env bash
# SSH transport — non-interactive and interactive SSH, bastion/ControlMaster

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function _ssh_cmd() {
    ssh ${SSH_OPTS_STR} "${SSH_TARGET}" "$@"
}

function _ssh() {
    _ssh_cmd "$@"
}

function _ssh_tty() {
    ssh ${SSH_OPTS_STR} -t "${SSH_TARGET}" "$@"
}

# Legacy alias for backward compat — prefer _ssh_cmd for non-interactive
function _ssh_alias() {
    _ssh_tty "$@"
}

function configure_ssh_transport() {
    # Configure direct or bastion-backed SSH transport to the jump host.
    mkdir -p ~/.ssh 2>/dev/null || true
    SSH_TARGET="${SSH_USERNAME:-ubuntu}@${JUMP_HOST_VIP:-}"
    local ssh_identity_file="${HOME}/.ssh/${LAB_NAME_PREFIX:-hyperconverged}-key.pem"

    if [ -n "${SSH_GATEWAY:-}" ]; then
        SSH_USER="${SSH_USER:-${USER}}"
        SSH_DEST_USER="${SSH_DEST_USER:-${SSH_USERNAME:-ubuntu}}"
        SSH_CONTROL_PATH="/tmp/hyperconverged-lab-ssh-$$.sock"

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

        export JUMP_HOST_VIP_REAL="${JUMP_HOST_VIP}"

        if [ -S "${SSH_CONTROL_PATH}" ]; then
            rm -f "${SSH_CONTROL_PATH}"
        fi

        trap 'ssh '"${SSH_OPTS_STR}"' -O exit "'"${SSH_TARGET}"'" 2>/dev/null || true; rm -f "'"${SSH_CONTROL_PATH}"'" 2>/dev/null || true' EXIT
    elif [ -f "${ssh_identity_file}" ]; then
        SSH_OPTS_STR="${SSH_OPTS_STR} -i ${ssh_identity_file}"
    fi

    export SSH_TARGET
    export SSH_OPTS_STR
}

function write_jump_host_ssh_config() {
    # Write SSH client config on jump host for worker access
    # Used by the kubespray orchestrator
    local _hosts_conf=""
    _hosts_conf=$(cat <<SSHEOF
Host ${LAB_NAME_PREFIX}-0
    HostName WORKER_0_IP_PLACEHOLDER
    User PLACEHOLDER_SSH_USER
    IdentityFile ~/.ssh/PLACEHOLDER_PREFIX-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host ${LAB_NAME_PREFIX}-1
    HostName WORKER_1_IP_PLACEHOLDER
    User PLACEHOLDER_SSH_USER
    IdentityFile ~/.ssh/PLACEHOLDER_PREFIX-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host ${LAB_NAME_PREFIX}-2
    HostName WORKER_2_IP_PLACEHOLDER
    User PLACEHOLDER_SSH_USER
    IdentityFile ~/.ssh/PLACEHOLDER_PREFIX-key.pem
    StrictHostKeyChecking no
    ForwardAgent yes
    AddKeysToAgent yes

Host *
    UserKnownHostsFile /dev/null
SSHEOF
)
    _ssh_tty "cat > ~/.ssh/config <<'SSHCFG'
${_hosts_conf}
SSHCFG
chmod 600 ~/.ssh/config"
}

function write_remote_hosts_and_bashrc() {
    # Append /etc/hosts and .bashrc entries on all worker nodes via parallel SSH
    local prefix="$1"
    shift
    local _ips=("$@")

    # SSH config on first target, then parallel /etc/hosts + .bashrc on all
    local host_lines=""
    local i
    for i in "${!_ips[@]}"; do
        host_lines+="${_ips[$i]} ${prefix}-${i}.cluster.local ${prefix}-${i}\n"
    done

    # Write SSH config on jump host first
    _ssh_tty "cat >> ~/.ssh/config <<'EOF'
Host *
    UserKnownHostsFile        /dev/null
    IdentityAgent             ssh-agent
    AddKeysToAgent            yes
EOF
chmod 600 ~/.ssh/config"

    # Parallel write hosts + bashrc
    for i in "${!_ips[@]}"; do
        (
            _ssh_tty "if ! grep -q '${_ips[$i]}' /etc/hosts 2>/dev/null; then
    echo '${_ips[$i]} ${prefix}-${i}.cluster.local ${prefix}-${i}' | sudo tee -a /etc/hosts
fi
if ! grep -qF 'source /opt/genestack/scripts/genestack.rc' ~/.bashrc 2>/dev/null; then
    echo 'source /opt/genestack/scripts/genestack.rc' >> ~/.bashrc
fi"
        ) &
    done
    wait
}
