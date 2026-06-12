#!/usr/bin/env bash
# shellcheck disable=SC2154
# Copyright 2024-Present, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

_Helpers_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_Helpers_DIR}/functions.sh"

# =========================================================================
# Standardized Logging
# =========================================================================
_LOG_LEVEL="${_LOG_LEVEL:-INFO}"

function _log() {
    local level="${1}"
    shift
    if [ "${level}" = "SKIP" ]; then return 0; fi
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    case "${level}" in
        ERROR)
            printf '[%s] ERROR: %s\n' "${ts}" "$*" >&2
            ;;
        WARN)
            printf '[%s] WARN:  %s\n' "${ts}" "$*" >&2
            ;;
        INFO)
            printf '[%s] INFO:  %s\n' "${ts}" "$*"
            ;;
        STEP)
            printf '\n[%s] === %s: %s ===\n' "${ts}" "$*" >&2
            ;;
        DEBUG)
            if [ "${_LOG_LEVEL}" = "DEBUG" ]; then
                printf '[%s] DEBUG: %s\n' "${ts}" "$*" >&2
            fi
            ;;
        *)
            printf '[%s] INFO:  %s\n' "${ts}" "$*"
            ;;
    esac
}

# =========================================================================
# Argument Parsing
# =========================================================================
function parseCommonArgs() {
    RUN_EXTRAS=0
    if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
        INCLUDE_LIST=("keystone" "barbican" "glance" "nova" "neutron" "placement" "trove")
        EXCLUDE_LIST=("cinder")
    else
        INCLUDE_LIST=("keystone" "glance" "cinder" "nova" "neutron" "placement")
        EXCLUDE_LIST=()
    fi

    while getopts "i:e:x" opt; do
        case $opt in
            x)     RUN_EXTRAS=1 ;;
            i)     local old_IFS="$IFS"; IFS=','; read -r -a INCLUDE_LIST <<< "$OPTARG"; IFS="$old_IFS" ;;
            e)     local old_IFS="$IFS"; IFS=','; read -r -a EXCLUDE_LIST <<< "$OPTARG"; IFS="$old_IFS" ;;
            \?|*)  echo "Usage: $0 [-i <include>] [-e <exclude>] [-x (extras)>" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    export RUN_EXTRAS
    export INCLUDE_LIST
    export EXCLUDE_LIST
}

# =========================================================================
# Prompting
# =========================================================================
function promptForCommonInputs() {
    if [ -z "${ACME_EMAIL}" ]; then
        read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL || _log SKIP
    fi
    export ACME_EMAIL="${ACME_EMAIL:-example@aol.com}"

    if [ -z "${GATEWAY_DOMAIN}" ]; then
        read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN || _log SKIP
        export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cluster.local}"
    fi

    if [ -z "${OS_CLOUD}" ]; then
        read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD || _log SKIP
        export OS_CLOUD="${OS_CLOUD:-default}"
    fi

    if [ -z "${OS_FLAVOR}" ]; then
        _log INFO "Listing available flavors"
        local FLAVORS
        FLAVORS=$(openstack flavor list --min-ram 16000 --min-disk 100 --sort-column Name -c Name -c RAM -c Disk -c VCPUs -f json 2>/dev/null)
        local DEFAULT_OS_FLAVOR
        DEFAULT_OS_FLAVOR=$(echo "${FLAVORS}" | jq -r '[.[] | select( all(.RAM; . < 24576) )] | .[0].Name')
        read -rp "Enter name of the flavor to use for the instances [${DEFAULT_OS_FLAVOR}]: " OS_FLAVOR || _log SKIP
        export OS_FLAVOR="${OS_FLAVOR:-${DEFAULT_OS_FLAVOR}}"
    fi
}

# =========================================================================
# Detect Jump Host SSH Username
# =========================================================================
function detectJumpHostSSHUsername() {
    if [ -z "${SSH_USERNAME}" ]; then
        local IMAGE_DEFAULT_PROPERTY
        IMAGE_DEFAULT_PROPERTY=$(openstack image show "${JUMP_HOST_IMAGE}" -f json 2>/dev/null | jq -r '.properties.default_user // empty')
        if [ -n "${IMAGE_DEFAULT_PROPERTY}" ]; then
            read -rp "Confirm SSH username [${IMAGE_DEFAULT_PROPERTY}]: " SSH_USERNAME || _log SKIP
            export SSH_USERNAME="${SSH_USERNAME:-${IMAGE_DEFAULT_PROPERTY}}"
        else
            read -rp "Enter the SSH username for the jump host [ubuntu]: " SSH_USERNAME || _log SKIP
            export SSH_USERNAME="${SSH_USERNAME:-ubuntu}"
        fi
    fi
}

# =========================================================================
# SSH Options Builder
# =========================================================================
function _ssh_ciphers() { echo "aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc"; }
function _ssh_kex() { echo "+diffie-hellman-group1-sha1,+ecdh-sha2-nistp256,+ecdh-sha2-nistp384,+ecdh-sha2-nistp521,+diffie-hellman-group-exchange-sha256,+diffie-hellman-group14-sha1"; }
function _ssh_macs() { echo "hmac-sha2-512,hmac-sha2-256,hmac-md5,hmac-sha1,umac-128@openssh.com"; }

_configure_apt_sources_cmd='for _i in $(seq 1 60); do sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1 || break; echo "  waiting for apt locks (${_i}/60)..."; sleep 5; done; sudo sed -i "s|rax\.mirror\.rackspace\.com|archive.ubuntu.com|g" /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; for f in /etc/apt/sources.list.d/*rax.mirror.rackspace.com*; do [ -e "$f" ] && sudo rm -f "$f"; done 2>/dev/null || true; sudo apt-get clean >/dev/null; sudo apt-get update >/dev/null'

function _build_ssh_opts() {
    printf -v _ssh_opts '%s ' \
        "-o ForwardAgent=yes" \
        "-o UserKnownHostsFile=/dev/null" \
        "-o StrictHostKeyChecking=${1:-accept-new}" \
        "-o ConnectTimeout=30" \
        "-o ConnectionAttempts=3" \
        "-o GSSAPIAuthentication=no" \
        "-o ServerAliveInterval=60" \
        "-o ServerAliveCountMax=120" \
        "-o KexAlgorithms=$(_ssh_kex)" \
        "-o Ciphers=$(_ssh_ciphers)" \
        "-o MACs=$(_ssh_macs)"
    SSH_OPTS_STR="${_ssh_opts% }"
}

# =========================================================================
# RAX.Mirror.APT Workaround
# =========================================================================
function _configure_apt_sources() {
    local _target="$1" _opts="$2" _user="$3"
    ssh ${_opts} "${_user}@${_target}" "${_configure_apt_sources_cmd}"
}

# =========================================================================
# Parallel WAIT — Server ACTIVE
# =========================================================================
function _parallel_wait_servers_active() {
    local count="${1:-3}" max_wait="${2:-600}" interval="${3:-5}"
    local prefix="${LAB_NAME_PREFIX:-hyperconverged}"
    local ready=0 elapsed=0

    _log STEP "Waiting for ${count} ${prefix} nodes to reach ACTIVE (timeout: ${max_wait}s)"
    declare -a waiters

    for i in $(seq 0 $((count - 1))); do
        (
            _attempts=0
            while true; do
                _status=$(openstack server show ${prefix}-${i} -f value -c status 2>/dev/null || echo "UNKNOWN")
                if [ "$_status" = "ACTIVE" ]; then
                    echo "ACTIVE" > "/tmp/hyperconverged-${i}.done"
                    exit 0
                elif [ "$_status" = "ERROR" ]; then
                    openstack server show ${prefix}-${i} >&2 || true
                    echo "ERROR" > "/tmp/hyperconverged-${i}.done"
                    exit 1
                fi
                sleep "${interval}"
                _attempts=$((_attempts + 1))
                if (( _attempts % 6 == 0 )); then
                    echo "  Node ${i}: status=${_status}" >&2
                fi
            done
        ) &
        waiters[$i]=$!
    done

    while [ $ready -lt $count ]; do
        sleep "${interval}"
        elapsed=$((elapsed + interval))
        for i in $(seq 0 $((count - 1))); do
            if [ -f "/tmp/hyperconverged-${i}.done" ]; then
                _status=$(cat "/tmp/hyperconverged-${i}.done")
                if [ "$_status" = "ACTIVE" ]; then
                    ready=$((ready + 1))
                    _log INFO "${prefix}-${i} is ACTIVE"
                    rm -f "/tmp/hyperconverged-${i}.done"
                elif [ "$_status" = "ERROR" ]; then
                    _log ERROR "${prefix}-${i} reached ERROR — aborting"
                    for p in $(seq 0 $((count - 1))); do
                        kill "${waiters[$p]}" 2>/dev/null || true
                        rm -f "/tmp/hyperconverged-${p}.done"
                    done
                    return 1
                fi
            fi
        done
        if [ $((elapsed % 30)) -eq 0 ] && [ $ready -lt $count ]; then
            _log "  ...still waiting (took ${elapsed}s, ${ready}/${count} ready)"
        fi
        if [ "${elapsed}" -ge "${max_wait}" ]; then
            _log "ERROR: Timeout — ${count} servers not ACTIVE after ${elapsed}s"
            for i in $(seq 0 $((count - 1))); do
                [ ! -f "/tmp/hyperconverged-${i}.done" ] && _log "ERROR:  Node ${i} never reached ACTIVE"
            done
            for i in $(seq 0 $((count - 1))); do rm -f "/tmp/hyperconverged-${i}.done"; done
            return 1
        fi
    done
    _log INFO "All ${count} nodes are ACTIVE (took ${elapsed}s)"
}

# =========================================================================
# Parallel WAIT — SSH Reachable
# =========================================================================
function wait_ssh_reachable() {
    local target="$1" description="${2:-host}" max_wait="${3:-960}" interval="${4:-4}"
    local elapsed=0

    _log STEP "Waiting for ${description} (${target}) SSH"
    while ! ssh ${SSH_OPTS_STR} -o ConnectTimeout=2 -q "${target}" exit 2>/dev/null; do
        sleep "${interval}"
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 30)) -eq 0 ]; then
            _log INFO "  ...still waiting for ${description} (${elapsed}s)"
        fi
        if [ "${elapsed}" -ge "${max_wait}" ]; then
            _log ERROR "${description} SSH not reachable after ${elapsed}s"
            return 1
        fi
    done
    _log INFO "${description} reachable at ${target}"
}

# =========================================================================
# Parallel WAIT — Volume Ready
# =========================================================================
function _wait_volume_ready() {
    local vol="${1:-genestack-0-cv1}" max_wait="${2:-300}"
    local elapsed=0

    while true; do
        local _status
        _status=$(openstack volume show "${vol}" -f value -c status 2>/dev/null || echo "ERROR")
        if [[ "$_status" =~ ^(available|in-use)$ ]]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $((elapsed % 20)) -eq 0 ]; then
            _log "  ...volume ${vol} status=${_status} (${elapsed}s)"
        fi
        if [ "${elapsed}" -ge "${max_wait}" ]; then
            _log "ERROR: Volume ${vol} not ready after ${elapsed}s"
            return 1
        fi
    done
}

# =========================================================================
# Parallel Compute Ports — {100..109} + per-node (saves ~50-60s)
# =========================================================================
function _parallel_compute_ports() {
    local prefix="$1"
    local _pids=()

    for i in {100..109}; do
        if ! openstack port show ${prefix}-0-compute-float-${i}-port -f value -c id >/dev/null 2>&1; then
            _log INFO "Creating compute float port 192.168.102.${i}"
            openstack port create --network ${prefix}-compute-net \
                --disable-port-security \
                --fixed-ip ip-address="192.168.102.${i}" \
                ${prefix}-0-compute-float-${i}-port >/dev/null 2>&1 &
            _pids+=($!)
        fi
    done
    for _pid in "${_pids[@]}"; do wait "$_pid" || true; done
    _pids=()

    for i in 0 1 2; do
        if ! openstack port show ${prefix}-${i}-compute-port -f value -c id >/dev/null 2>&1; then
            _log INFO "Creating ${i}-compute-port"
            openstack port create --network ${prefix}-compute-net --disable-port-security \
                ${prefix}-${i}-compute-port >/dev/null 2>&1 &
            _pids+=($!)
        fi
    done
    for _pid in "${_pids[@]}"; do wait "$_pid" || true; done
    _log INFO "Compute ports ready"
}

# =========================================================================
# Parallel SSH — generic
# =========================================================================
function _parallel_ssh() {
    local prefix="$1"
    shift
    local _ips=("$@")
    local _ssh_opts="${SSH_OPTS_STR}"
    local _ssh_user="${SSH_USERNAME}"
    local cmd="$3"
    local _pids=()
    local _results=()

    _log INFO "Parallel SSH [${prefix}] on: ${_ips[*]}"

    local _i
    for _i in "${!_ips[@]}"; do
        (
            local _ip="${_ips[$_i]}"
            local _output
            _output=$(ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "${_ssh_user}@${_ip}" "${cmd}" 2>&1)
            printf '%s\t%s\t%s\n' "${_ip}" "$?" "${_output}" > "/tmp/hyperconverged-ssh-${prefix}-${_i}.out"
        ) &
        _pids+=($!)
        _results+=("${_i}")
    done

    for _pid in "${_pids[@]}"; do wait "$_pid" || true; done

    for _ri in "${_results[@]}"; do
        local _outfile="/tmp/hyperconverged-ssh-${prefix}-${_ri}.out"
        [ -f "${_outfile}" ] || continue
        local _ip _rc _out
        _ip=$(awk -F'\t' '{print $1}' "${_outfile}")
        _rc=$(awk -F'\t' '{print $2}' "${_outfile}")
        _out=$(awk -F'\t' '{$1=""; $2=""; print $0}' "${_outfile}" | sed 's/^  *//')
        if [ "${_rc}" -eq 0 ]; then
            [ -n "${_out}" ] && echo "[${_ip}] ${_out}"
        else
            echo "[${_ip}] FAIL (rc=${_rc}):" >&2
            echo "${_out}" | sed "s/^/[  ] ${_ip}/;s/^/[  ]   /" >&2
        fi
        rm -f "${_outfile}"
    done
}

# =========================================================================
# Parallel Host Prep
# =========================================================================
function _parallel_host_prep() {
    local prefix="$1" ssh_target="$2" ssh_opts="$3" ssh_user="$4"
    shift 4
    local worker_ips=("$@")

    _log INFO "Copying SSH keys to ${ssh_target}"
    scp ${ssh_opts} "${SCRIPT_DIR}/../../.ssh/${prefix}-key.pem" "${ssh_user}@${ssh_target}:~/.ssh/" 2>/dev/null || true
    scp ${ssh_opts} "${SCRIPT_DIR}/../../.ssh/${prefix}-key.pub" "${ssh_user}@${ssh_target}:~/.ssh/" 2>/dev/null || true

    _log INFO "Updating /etc/hosts on ${#worker_ips[@]} nodes"
    _log INFO "Running APT fix on all nodes"
    _configure_apt_sources "${ssh_target}" "${ssh_opts}" "${ssh_user}"

    for _wip in "${worker_ips[@]}"; do
        (
            ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t "${ssh_user}@${ssh_target}" \
                "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${ssh_user}@${_wip} '${_configure_apt_sources_cmd}'" 2>/dev/null
        ) &
    done
    wait
    _log INFO "Host preparation complete"
}
