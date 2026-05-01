#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# HCL Builder — Hyperconverged Lab Builder
#
# Builds a fully automated Ubuntu-based Kubernetes cluster running
# Genestack (OpenStack on Kubernetes) in a hyperconverged configuration.
#
#   - Calls install-*.sh scripts DIRECTLY (no setup-openstack.sh)
#   - Uses the hclab_service_conf Ansible role for all configuration
#   - Manages its own parallelism and dependency ordering
#   - Installs Skyline last so its nginx-generator sees all endpoints
#
# Platform: Ubuntu with Kubespray
#
# Configuration precedence (earlier entries override later ones):
#   1. Command-line flags       (highest priority)
#   2. Environment variables
#   3. Config file (-c)
#   4. Defaults                 (lowest priority)
#
# Usage:
#   hcl-builder.sh -c <config> -i <services> [-e <services>] [options]
#
# Options:
#   -c FILE     Config file (sourced as shell variables)
#   -i SVCS     Comma-separated services to install
#   -e SVCS     Comma-separated services to exclude
#   -d DOMAIN   Gateway domain         (prompted if not set)
#   -a EMAIL    ACME email             (prompted if not set)
#   -C CLOUD    OpenStack cloud name   (prompted if not set)
#   -f FLAVOR   Instance flavor        (prompted if not set)
#   -I IMAGE    Instance image         (default: Ubuntu 24.04)
#   -u USER     SSH username           (auto-detected from image)
#   -p PREFIX   Lab name prefix        (default: hyperconverged)
#   -D          Development mode — rsync local checkout to jump host
#   -t LEVEL    Test level: quick, standard, full, off (default: off)
#
#   OpenStack services: manila, octavia, trove, cinder, barbican, heat,
#                       blazar, magnum, masakari, ceilometer, gnocchi,
#                       cloudkitty, freezer, zaqar, designate
#   Extras: k9s
#
# Base services (always installed unless excluded):
#   keystone, glance, cinder, nova, neutron, placement, skyline
#
# Config file format (shell variables):
#   ACME_EMAIL="dan.with@rackspace.com"
#   GATEWAY_DOMAIN="cluster.local"
#   OS_CLOUD="rxt-iad-prod"
#   OS_FLAVOR="gp.0.8.24"
#   OS_IMAGE="Ubuntu 24.04"
#   HYPERCONVERGED_DEV="true"
#   LAB_NAME_PREFIX="hyperconverged"
#   # Comments and blank lines are fine
#
# Examples:
#   hcl-builder.sh -c ~/.hcl/rxt-iad.env -i manila,octavia,trove,cinder,k9s
#   hcl-builder.sh -d cluster.local -C rxt-iad-prod -f gp.0.8.24 -D -i manila
#   hcl-builder.sh -i manila -e heat
#

set -o pipefail
set -e
SECONDS=0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Defaults
export LAB_NETWORK_MTU="${LAB_NETWORK_MTU:-1500}"
export DISABLE_OPENSTACK="${DISABLE_OPENSTACK:-false}"

#############################################################################
# Helpers
#############################################################################

_ssh() {
    ssh -o ForwardAgent=yes \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -t ${SSH_USERNAME}@${JUMP_HOST_VIP} "$@"
}

_ssh_bg() {
    ssh -o ForwardAgent=yes \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        ${SSH_USERNAME}@${JUMP_HOST_VIP} "$@"
}

wait_pids() {
    local -n _pids=$1
    local -n _names=$2
    for i in "${!_pids[@]}"; do
        wait "${_pids[$i]}" || {
            echo "ERROR: ${_names[$i]} failed (exit code $?)"
            exit 1
        }
        echo "${_names[$i]} complete"
    done
}

# Check if a service is in the install set
svc_enabled() { [[ "${SVC[$1]+x}" == "x" ]]; }

#############################################################################
# yq — YAML processor
#############################################################################

function installYq() {
    echo "Installing yq..."
    local version=${YQ_VERSION:-v4.47.2}
    local os arch binary

    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="darwin" ;;
        *)
            echo "Error: Unsupported operating system: $(uname -s)" >&2
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        amd64)   arch="amd64" ;;
        aarch64) arch="arm64" ;;
        arm64)   arch="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac

    binary="yq_${os}_${arch}"
    echo "Detected platform: ${os}/${arch}"

    export SUDO_CMD=""
    if sudo -l 2>/dev/null | grep -q NOPASSWD; then
        SUDO_CMD="/usr/bin/sudo -n "
    fi

    wget "https://github.com/mikefarah/yq/releases/download/${version}/${binary}.tar.gz" -q -O - | tar xz
    ${SUDO_CMD} mv "${binary}" /usr/local/bin/yq
    ${SUDO_CMD} chmod +x /usr/local/bin/yq
}

function ensureYq() {
    if ! yq --version &> /dev/null; then
        echo "yq is not installed. Attempting to install yq"
        installYq
    fi
}

#############################################################################
# Interactive prompts (fallback when flags/config don't set values)
#############################################################################

function promptForCommonInputs() {
    if [ -z "${ACME_EMAIL}" ]; then
        read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
    fi
    ACME_EMAIL="${ACME_EMAIL:-example@aol.com}"
    export ACME_EMAIL

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
        FLAVORS=$(openstack flavor list --min-ram 16000 --min-disk 100 --sort-column Name -c Name -c RAM -c Disk -c VCPUs -f json)
        DEFAULT_OS_FLAVOR=$(echo "${FLAVORS}" | jq -r '[.[] | select( all(.RAM; . < 24576) )] | .[0].Name')
        echo "The following flavors are available for use with this build"
        echo "${FLAVORS}" | jq -r '["Name", "RAM", "Disk", "VCPUs"], (.[] | [.Name, .RAM, .Disk, .VCPUs]) | @tsv' | column -t
        read -rp "Enter name of the flavor to use for the instances [${DEFAULT_OS_FLAVOR}]: " OS_FLAVOR
        export OS_FLAVOR=${OS_FLAVOR:-${DEFAULT_OS_FLAVOR}}
    fi
}

#############################################################################
# OpenStack Infrastructure Functions
#############################################################################

function createRouter() {
    if ! openstack router show ${LAB_NAME_PREFIX}-router 2>/dev/null; then
        openstack router create ${LAB_NAME_PREFIX}-router --external-gateway PUBLICNET
    fi
}

function createNetworks() {
    # Management network
    if ! openstack network show ${LAB_NAME_PREFIX}-net 2>/dev/null; then
        openstack network create ${LAB_NAME_PREFIX}-net \
            --mtu ${LAB_NETWORK_MTU}
    fi

    # Management subnet
    if ! TENANT_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-subnet -f json 2>/dev/null | jq -r '.id'); then
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
    export TENANT_SUB_NETWORK_ID

    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2>/dev/null | jq -r '.interfaces_info[].subnet_id' | grep -q ${TENANT_SUB_NETWORK_ID}; then
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet
    fi

    # Compute network (no port security for flat provider network)
    if ! openstack network show ${LAB_NAME_PREFIX}-compute-net 2>/dev/null; then
        openstack network create ${LAB_NAME_PREFIX}-compute-net \
            --disable-port-security \
            --mtu ${LAB_NETWORK_MTU}
    fi

    # Compute subnet (no DHCP)
    if ! TENANT_COMPUTE_SUB_NETWORK_ID=$(openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f json 2>/dev/null | jq -r '.id'); then
        echo "Creating the ${LAB_NAME_PREFIX}-compute-subnet"
        TENANT_COMPUTE_SUB_NETWORK_ID=$(
            openstack subnet create ${LAB_NAME_PREFIX}-compute-subnet \
                --network ${LAB_NAME_PREFIX}-compute-net \
                --subnet-range 192.168.102.0/24 \
                --no-dhcp -f json | jq -r '.id'
        )
    fi
    export TENANT_COMPUTE_SUB_NETWORK_ID

    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json | jq -r '.interfaces_info[].subnet_id' | grep -q ${TENANT_COMPUTE_SUB_NETWORK_ID} 2>/dev/null; then
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet
    fi
}

function createCommonSecurityGroups() {
    # HTTP/HTTPS security group
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup 2>/dev/null; then
        openstack security group create ${LAB_NAME_PREFIX}-http-secgroup
    fi

    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 443; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 443 \
            --description "https"
    fi
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 80; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp \
            --ingress \
            --remote-ip 0.0.0.0/0 \
            --dst-port 80 \
            --description "http"
    fi

    # Trove guest VM connectivity — scoped to internal networks only (not public).
    # RabbitMQ (5672) and Keystone (5000) are on the MetalLB shared VIP.
    # Two rules per port: flat network (source) and mgmt network (SNAT).
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 5672; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp --ingress --dst-port 5672 \
            --remote-ip ${COMPUTE_SUBNET_CIDR:-192.168.102.0/24} \
            --description "RabbitMQ for Trove guest VMs (flat network)"
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp --ingress --dst-port 5672 \
            --remote-ip ${MGMT_SUBNET_CIDR:-192.168.100.0/24} \
            --description "RabbitMQ for Trove guest VMs (mgmt network / SNAT)"
    fi
    if ! openstack security group show ${LAB_NAME_PREFIX}-http-secgroup -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -q 5000; then
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp --ingress --dst-port 5000 \
            --remote-ip ${COMPUTE_SUBNET_CIDR:-192.168.102.0/24} \
            --description "Keystone for Trove guest VMs (flat network)"
        openstack security group rule create ${LAB_NAME_PREFIX}-http-secgroup \
            --protocol tcp --ingress --dst-port 5000 \
            --remote-ip ${MGMT_SUBNET_CIDR:-192.168.100.0/24} \
            --description "Keystone for Trove guest VMs (mgmt network / SNAT)"
    fi

    # Internal traffic security group
    if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup 2>/dev/null; then
        openstack security group create ${LAB_NAME_PREFIX}-secgroup
    fi

    if ! openstack security group show ${LAB_NAME_PREFIX}-secgroup -f json 2>/dev/null | jq -r '.rules[].description' | grep -q "all internal traffic"; then
        openstack security group rule create ${LAB_NAME_PREFIX}-secgroup \
            --protocol any \
            --ingress \
            --remote-ip 192.168.100.0/24 \
            --description "all internal traffic"
    fi
}

function createMetalLBPort() {
    if ! METAL_LB_IP=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f json 2>/dev/null | jq -r '.fixed_ips[0].ip_address'); then
        echo "Creating the MetalLB VIP port"
        METAL_LB_IP=$(openstack port create --security-group ${LAB_NAME_PREFIX}-http-secgroup --network ${LAB_NAME_PREFIX}-net ${LAB_NAME_PREFIX}-metallb-vip-0-port -f json | jq -r '.fixed_ips[0].ip_address')
    fi
    export METAL_LB_IP

    METAL_LB_PORT_ID=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id)
    export METAL_LB_PORT_ID

    if ! METAL_LB_VIP=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
        echo "Creating the MetalLB VIP floating IP"
        METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
    elif [ -z "${METAL_LB_VIP}" ]; then
        METAL_LB_VIP=$(openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} -f json | jq -r '.floating_ip_address')
    fi
    export METAL_LB_VIP
}

function createComputePorts() {
    echo "Creating pre-defined compute ports for the flat test network"
    for i in {100..109}; do
        if ! openstack port show ${LAB_NAME_PREFIX}-0-compute-float-${i}-port 2>/dev/null; then
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --disable-port-security \
                --fixed-ip ip-address="192.168.102.${i}" \
                ${LAB_NAME_PREFIX}-0-compute-float-${i}-port
        fi
    done

    if ! COMPUTE_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_0_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-0-compute-port
        )
    fi
    export COMPUTE_0_PORT

    if ! COMPUTE_1_PORT=$(openstack port show ${LAB_NAME_PREFIX}-1-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_1_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-1-compute-port
        )
    fi
    export COMPUTE_1_PORT

    if ! COMPUTE_2_PORT=$(openstack port show ${LAB_NAME_PREFIX}-2-compute-port -f value -c id 2>/dev/null); then
        export COMPUTE_2_PORT=$(
            openstack port create --network ${LAB_NAME_PREFIX}-compute-net \
                --no-fixed-ip \
                --disable-port-security \
                -f value \
                -c id \
                ${LAB_NAME_PREFIX}-2-compute-port
        )
    fi
    export COMPUTE_2_PORT
}

#############################################################################
# Jump Host Source Preparation
#############################################################################

function cloneGenestackOnJumpHost() {
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

function prepareJumpHostSource() {
    local DEV_PATH="$(readlink -fn ${SCRIPT_DIR}/..)"

    if [ "${HYPERCONVERGED_DEV:-false}" = "true" ]; then
        if [ ! -d "${DEV_PATH}" ]; then
            echo "HYPERCONVERGED_DEV is true, but we've failed to determine the base genestack directory"
            exit 1
        fi
        # Ensure submodules are populated locally before rsync (worktrees
        # start with empty submodule dirs).
        echo "Initializing submodules locally..."
        local STASH_RESULT
        STASH_RESULT=$(git -C "${DEV_PATH}" stash --include-untracked 2>&1) || true
        git -C "${DEV_PATH}" submodule update --init --recursive
        if [[ "${STASH_RESULT}" != *"No local changes"* ]]; then
            git -C "${DEV_PATH}" stash pop 2>/dev/null || true
        fi

        # Install rsync and git, create target directory on the jump host
        _ssh "while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do echo 'Waiting for apt locks to be released...'; sleep 5; done && sudo apt-get update && sudo apt install -y rsync git && sudo mkdir -p /opt/genestack && sudo chown ${SSH_USERNAME}:${SSH_USERNAME} /opt/genestack"
        echo "Copying the development source code to the jump host"
        rsync -avz \
            --exclude='.git' \
            -e "ssh -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
            ${DEV_PATH}/ ${SSH_USERNAME}@${JUMP_HOST_VIP}:/opt/genestack/
    else
        cloneGenestackOnJumpHost
    fi
}

#############################################################################
# Remote Utility Functions
#############################################################################

function installK9sRemote() {
    echo "Installing k9s on jump host..."
    _ssh <<'EOC'
set -e
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
EOC
}

#############################################################################
# Parse Arguments
#
# Two passes: first extract -c to source the config file, then parse
# the rest. This lets flags override config file values.
#############################################################################

# --- Pass 1: extract config file ---
OPTIND=1
_config_file=""
while getopts ":c:" _opt; do
    case $_opt in c) _config_file="$OPTARG" ;; esac
done

if [ -n "$_config_file" ]; then
    if [ ! -f "$_config_file" ]; then
        echo "ERROR: Config file not found: $_config_file"
        exit 1
    fi
    echo "Loading config: $_config_file"
    # shellcheck disable=SC1090
    source "$_config_file"
fi

# --- Pass 2: parse all flags (override config + env) ---
OPTIND=1
INCLUDE_LIST=()
EXCLUDE_LIST=()

# Capture pre-flag env values so flags can override
_flag_domain="" _flag_email="" _flag_cloud="" _flag_flavor=""
_flag_image="" _flag_user="" _flag_prefix="" _flag_dev="" _flag_test=""

while getopts "c:i:e:d:a:C:f:I:u:p:Dt:" opt; do
    case $opt in
        c) ;;  # already handled in pass 1
        i) IFS=',' read -r -a INCLUDE_LIST <<< "$OPTARG" ;;
        e) IFS=',' read -r -a EXCLUDE_LIST <<< "$OPTARG" ;;
        d) _flag_domain="$OPTARG" ;;
        a) _flag_email="$OPTARG" ;;
        C) _flag_cloud="$OPTARG" ;;
        f) _flag_flavor="$OPTARG" ;;
        I) _flag_image="$OPTARG" ;;
        u) _flag_user="$OPTARG" ;;
        p) _flag_prefix="$OPTARG" ;;
        D) _flag_dev="true" ;;
        t) _flag_test="$OPTARG" ;;
        *)
            echo "Usage: $0 -c <config> -i <services> [-e <services>] [options]"
            echo "       $0 -h for help"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Apply: flag > env > config (no hardcoded defaults for prompted values)
# Values left empty here will be prompted by promptForCommonInputs below.
GATEWAY_DOMAIN="${_flag_domain:-${GATEWAY_DOMAIN:-}}"
ACME_EMAIL="${_flag_email:-${ACME_EMAIL:-}}"
OS_CLOUD="${_flag_cloud:-${OS_CLOUD:-}}"
OS_FLAVOR="${_flag_flavor:-${OS_FLAVOR:-}}"
OS_IMAGE="${_flag_image:-${OS_IMAGE:-Ubuntu 24.04}}"
SSH_USERNAME="${_flag_user:-${SSH_USERNAME:-}}"
LAB_NAME_PREFIX="${_flag_prefix:-${LAB_NAME_PREFIX:-hyperconverged}}"
HYPERCONVERGED_DEV="${_flag_dev:-${HYPERCONVERGED_DEV:-false}}"
TEST_LEVEL="${_flag_test:-${TEST_LEVEL:-off}}"

export GATEWAY_DOMAIN ACME_EMAIL OS_CLOUD OS_FLAVOR OS_IMAGE
export SSH_USERNAME LAB_NAME_PREFIX HYPERCONVERGED_DEV TEST_LEVEL

#############################################################################
# Build Service Set
#############################################################################

# Base services — always installed unless explicitly excluded
BASE_SERVICES=(keystone glance cinder nova neutron placement skyline)

# Dependency map: service -> space-separated list of required services
declare -A DEPS
DEPS[cinder]="barbican"
DEPS[manila]="cinder barbican"
DEPS[trove]="cinder barbican"
DEPS[nova]="placement"
DEPS[octavia]=""
DEPS[ceilometer]="gnocchi"
DEPS[cloudkitty]="gnocchi"

# Non-OpenStack extras handled outside install-*.sh
EXTRAS=()

# Start with base services
declare -A SVC
for s in "${BASE_SERVICES[@]}"; do SVC[$s]=1; done

# Add included services
for s in "${INCLUDE_LIST[@]}"; do
    [[ -z "$s" ]] && continue
    # Separate extras from OpenStack services
    case "$s" in
        k9s) EXTRAS+=("$s") ;;
        *)   SVC[$s]=1 ;;
    esac
done

# Remove excluded services (first pass — dependencies may re-add)
declare -A EXCLUDED
for s in "${EXCLUDE_LIST[@]}"; do
    [[ -z "$s" ]] && continue
    EXCLUDED[$s]=1
    unset "SVC[$s]"
done

# Resolve dependencies: if a service is enabled, its deps must be too
for s in "${!SVC[@]}"; do
    for dep in ${DEPS[$s]:-}; do
        if [[ "${SVC[$dep]+x}" != "x" ]]; then
            if [[ "${EXCLUDED[$dep]+x}" == "x" ]]; then
                echo "WARNING: Re-adding '$dep' — required by '$s'"
            fi
            SVC[$dep]=1
        fi
    done
done

# Services that need pre-configuration before their helm install.
# They are installed after preconf, not with the core parallel batch.
PRECONF_SERVICES=(manila octavia trove)

# Skyline installs last (needs all endpoints registered).
# Keystone installs first (everything depends on it).
# These are always separated from the core parallel batch.
ALWAYS_SEPARATE="keystone skyline"

# Build core list: everything in SVC minus preconf services and always-separate
CORE_SERVICES=()
for s in "${!SVC[@]}"; do
    _skip=false
    for p in "${PRECONF_SERVICES[@]}"; do [[ "$s" == "$p" ]] && _skip=true; done
    for p in ${ALWAYS_SEPARATE}; do [[ "$s" == "$p" ]] && _skip=true; done
    $_skip || CORE_SERVICES+=("$s")
done

#############################################################################
# Resolve remaining settings — interactive fallback for anything not
# supplied via flags, env vars, or config file.
#############################################################################

ensureYq

# promptForCommonInputs (from hyperconverged-common.sh) prompts for
# ACME_EMAIL, GATEWAY_DOMAIN, OS_CLOUD, and OS_FLAVOR only when they
# are still empty.  Values already set by -c / -d / -a / -C / -f flags
# are exported and will be skipped.
promptForCommonInputs

# SSH username: auto-detect from image if not provided
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
        read -rp "Enter the default username for the image: " SSH_USERNAME
    fi
    export SSH_USERNAME
fi

echo "=== HCL Builder ==="
echo "  Domain:   ${GATEWAY_DOMAIN}"
echo "  Cloud:    ${OS_CLOUD}"
echo "  Flavor:   ${OS_FLAVOR}"
echo "  Image:    ${OS_IMAGE}"
echo "  User:     ${SSH_USERNAME}"
echo "  Prefix:   ${LAB_NAME_PREFIX}"
echo "  Dev mode: ${HYPERCONVERGED_DEV}"
echo "  Core:     ${CORE_SERVICES[*]}"
echo "  Preconf:  $(for s in "${PRECONF_SERVICES[@]}"; do svc_enabled "$s" && printf '%s ' "$s"; done)"
echo "  Extras:   ${EXTRAS[*]:-none}"
echo "==================="

#############################################################################
# Phase 1: Create OpenStack Infrastructure
#############################################################################

createRouter
createNetworks
createCommonSecurityGroups

# Kubespray-specific: jump host security group
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
# Phase 1: Create Ports and Floating IPs
#############################################################################

createMetalLBPort

if ! WORKER_0_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id 2>/dev/null); then
    export WORKER_0_PORT=$(
        openstack port create --allowed-address ip-address=${METAL_LB_IP} \
            --security-group ${LAB_NAME_PREFIX}-secgroup \
            --security-group ${LAB_NAME_PREFIX}-jump-secgroup \
            --security-group ${LAB_NAME_PREFIX}-http-secgroup \
            --network ${LAB_NAME_PREFIX}-net \
            -f value -c id \
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
            -f value -c id \
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
            -f value -c id \
            ${LAB_NAME_PREFIX}-2-mgmt-port
    )
fi
export WORKER_2_PORT

if ! JUMP_HOST_VIP=$(openstack floating ip list --port ${WORKER_0_PORT} -f json 2>/dev/null | jq -r '.[]."Floating IP Address"'); then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
elif [ -z "${JUMP_HOST_VIP}" ]; then
    JUMP_HOST_VIP=$(openstack floating ip create PUBLICNET --port ${WORKER_0_PORT} -f json | jq -r '.floating_ip_address')
fi
export JUMP_HOST_VIP

createComputePorts

# Create Trove service ports on the mgmt network (third NIC).
# This NIC bridges OVN's physnet2 to the physical management L2 where
# MetalLB VIPs live. Created with --no-fixed-ip to avoid DHCP conflicts.
if svc_enabled trove; then
    for _idx in 0 1 2; do
        TROVE_PORT_NAME="${LAB_NAME_PREFIX}-${_idx}-trove-mgmt-port"
        if ! openstack port show ${TROVE_PORT_NAME} 2>/dev/null; then
            openstack port create \
                --disable-port-security \
                --no-fixed-ip \
                --network ${LAB_NAME_PREFIX}-net \
                ${TROVE_PORT_NAME}
        fi
        eval "export TROVE_MGMT_${_idx}_PORT=$(openstack port show ${TROVE_PORT_NAME} -f value -c id)"
    done
fi

#############################################################################
# Phase 1: SSH Key Management
#############################################################################

if [ ! -d "~/.ssh" ]; then
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

ssh-add ~/.ssh/${LAB_NAME_PREFIX}-key.pem 2>/dev/null || true

#############################################################################
# Phase 1: Create Lab Instances
#############################################################################

for _idx in 0 1 2; do
    if ! openstack server show ${LAB_NAME_PREFIX}-${_idx} 2>/dev/null; then
        _port_var="WORKER_${_idx}_PORT"
        _compute_var="COMPUTE_${_idx}_PORT"
        _trove_var="TROVE_MGMT_${_idx}_PORT"
        _trove_port=""
        if [ -n "${!_trove_var:-}" ]; then
            _trove_port="--port ${!_trove_var}"
        fi
        openstack server create ${LAB_NAME_PREFIX}-${_idx} \
            --port ${!_port_var} \
            --port ${!_compute_var} \
            ${_trove_port} \
            --image "${OS_IMAGE}" \
            --key-name ${LAB_NAME_PREFIX}-key \
            --flavor ${OS_FLAVOR}
    fi
done

#############################################################################
# Phase 1: Wait for Jump Host SSH Access
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
# Phase 1: Create and Attach Lab Volumes (when cinder is in -i)
#############################################################################

if svc_enabled cinder; then
    for _idx in 0 1 2; do
        READY_COUNT=0
        while [ $(openstack server show ${LAB_NAME_PREFIX}-${_idx} -f yaml | yq '.status') != 'ACTIVE' ]; do
            echo "Server instance ${_idx} is not ready, waiting..."
            READY_COUNT=$((READY_COUNT + 1))
            if [ $READY_COUNT -gt 200 ]; then
                echo "VM: ${LAB_NAME_PREFIX}-${_idx} never built"
                exit 1
            fi
        done
    done

    for _idx in 0 1 2; do
        if ! openstack volume show ${LAB_NAME_PREFIX}-${_idx}-cv1 2>/dev/null; then
            openstack volume create \
                --size 200 \
                --type Performance \
                --description "cinder-volumes-1 on ${LAB_NAME_PREFIX}-${_idx}" \
                ${LAB_NAME_PREFIX}-${_idx}-cv1
        fi
    done

    sleep 2

    for _idx in 0 1 2; do
        READY_COUNT=0
        while [[ ! $(openstack volume show ${LAB_NAME_PREFIX}-${_idx}-cv1 -f yaml | yq '.status') =~ ^(available|in-use)$ ]]; do
            sleep 0.2
            echo "Data volume ${_idx} is not ready, Trying again..."
            READY_COUNT=$((READY_COUNT + 1))
            if [ $READY_COUNT -gt 200 ]; then
                echo "Volume: ${LAB_NAME_PREFIX}-${_idx}-cv1 not built"
                exit 1
            fi
        done
    done

    for _idx in 0 1 2; do
        if [ $(openstack volume show ${LAB_NAME_PREFIX}-${_idx}-cv1 -f yaml | yq '.status') == 'available' ]; then
            openstack server add volume \
                --enable-delete-on-termination \
                ${LAB_NAME_PREFIX}-${_idx} \
                ${LAB_NAME_PREFIX}-${_idx}-cv1
        else
            echo "Data volume ${_idx} is not available"
        fi
    done

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
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pem \
    ~/.ssh/${LAB_NAME_PREFIX}-key.pub \
    ${SSH_USERNAME}@${JUMP_HOST_VIP}:/home/${SSH_USERNAME}/.ssh/
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
# Phase 2: Bootstrap, Inventory, and Kubespray
#############################################################################

prepareJumpHostSource

# Bootstrap is designed to run as root (writes to /usr/local/bin, /etc/genestack).
# Production runs it as root via infra-deploy.yaml; hyperconverged-lab-kubespray.sh
# uses plain `sudo`.  The docs recommend `sudo -E` to preserve the caller's env.
#
# We use `sudo -E HOME=\${HOME}` so:
#   - Root privileges for /usr/local/bin writes and /etc/genestack creation
#   - HOME stays as /home/ubuntu so the venv is created at the correct path
#     (/home/ubuntu/.venvs/genestack) where genestack.rc expects it
#   - No duplicate pip install needed
_ssh <<EOC
set -e
if [ ! -d "/etc/genestack" ]; then
    sudo -E HOME=\${HOME} /opt/genestack/bootstrap.sh
    sudo chown -R \${USER}:\${USER} /etc/genestack
    # /etc/genestack/kustomize/<svc>/base is a symlink to
    # /opt/genestack/base-kustomize/<svc>/base, and the kustomize.sh
    # post-renderer writes <svc>/base/all.yaml when helm upgrades run.
    # Chown the symlink target so non-root install-*.sh runs can write.
    sudo chown -R \${USER}:\${USER} /opt/genestack/base-kustomize
    # Bootstrap ran as root with HOME=/home/ubuntu — fix any root-owned
    # dotfiles it created (.ansible, .venvs, .local, .cache, etc.)
    sudo chown -R \${USER}:\${USER} \${HOME}/.ansible \${HOME}/.venvs \${HOME}/.local \${HOME}/.cache 2>/dev/null || true
fi
# Ensure yq is installed — install scripts use it but don't install it themselves
if ! command -v yq >/dev/null 2>&1; then
    source /opt/genestack/scripts/lib/functions.sh
    installYq
fi
# Make genestack.rc auto-source on login so interactive shells inherit
# OS_CLOUD, kubeconfig, the genestack venv, etc. without manual sourcing.
if ! grep -qF "source /opt/genestack/scripts/genestack.rc" \${HOME}/.bashrc 2>/dev/null; then
    echo "source /opt/genestack/scripts/genestack.rc" >> \${HOME}/.bashrc
fi
EOC

# Step 2b: Write Kubespray inventory BEFORE cluster.yml or host-setup runs
# host-setup.yml targets "hosts: all" so the inventory must exist first,
# otherwise packages (nfs-client, lvm2, etc.) only install on localhost.
echo "Writing Kubespray inventory on jump host..."
_ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags inventory \
    -e worker_0_ip=${WORKER_0_IP} \
    -e worker_1_ip=${WORKER_1_IP} \
    -e worker_2_ip=${WORKER_2_IP} \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e gateway_domain=${GATEWAY_DOMAIN}
EOC

# Host-setup playbook: installs distro packages (nfs-client, lvm2, lldpd,
# etc.), kernel modules, sysctl tuning on ALL nodes.  Must run after
# inventory is written so "hosts: all" reaches the worker nodes.
_ssh <<EOC
set -e
if [ ! -f "/usr/local/bin/queue_max.sh" ]; then
    source /opt/genestack/scripts/genestack.rc
    ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/host-setup.yml \
        -i /etc/genestack/inventory/inventory.yaml \
        --become \
        -e host_required_kernel=\$(uname -r)
fi
EOC

# Step 2c: Run Kubespray (needs inventory at /etc/genestack/inventory/inventory.yaml)
_ssh <<EOC
set -e
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

# Set up kubeconfig for the ubuntu user so kubectl works without sudo
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown \$(id -u):\$(id -g) ~/.kube/config
kubectl get nodes || { echo "ERROR: Kubernetes cluster not healthy"; exit 1; }
EOC

#############################################################################
# Phase 3: Ansible Role — Service Configuration
# Writes MetalLB, helm overrides, endpoints.
# Inventory was already written in Phase 2b (before Kubespray).
#############################################################################

echo "Running hclab_service_conf Ansible role on jump host..."

_ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags metallb,helm_overrides,endpoints \
    -e metal_lb_ip=${METAL_LB_IP} \
    -e gateway_domain=${GATEWAY_DOMAIN} \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e worker_0_ip=${WORKER_0_IP} \
    -e worker_1_ip=${WORKER_1_IP} \
    -e worker_2_ip=${WORKER_2_IP} \
    -e run_manila_preconf=$(svc_enabled manila && echo true || echo false) \
    -e run_trove_preconf=$(svc_enabled trove && echo true || echo false)
EOC

#############################################################################
# Phase 4: Kubernetes Infrastructure (MariaDB, RabbitMQ, Memcached, etc.)
#############################################################################

echo "Installing Kubernetes infrastructure on jump host..."

_ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc

if kubectl -n envoy-gateway get gateway flex-gateway &>/dev/null; then
  echo "Resetting flex-gateway listeners to base pair for idempotent rerun"
  kubectl -n envoy-gateway get gateway flex-gateway -o json | \
    jq '.spec.listeners = [.spec.listeners[] | select(.name == "cluster-http" or .name == "cluster-tls")]' | \
    kubectl apply -f -
fi

echo "Installing Kubernetes Infrastructure"
sudo LONGHORN_STORAGE_REPLICAS=1 \
     GATEWAY_DOMAIN="${GATEWAY_DOMAIN}" \
     ACME_EMAIL="${ACME_EMAIL}" \
     HYPERCONVERGED=true \
     /opt/genestack/bin/setup-infrastructure.sh

# setup-infrastructure.sh runs as root and its nested install-*.sh post-renderers
# write root-owned all.yaml into /opt/genestack/base-kustomize/<svc>/base/.
# Sweep ownership back to \${USER} so subsequent non-sudo install-*.sh runs
# (Phase 5 onwards) can rewrite those files without permission errors.
sudo chown -R \${USER}:\${USER} /opt/genestack/base-kustomize
EOC

if [ "${DISABLE_OPENSTACK}" = "true" ]; then
    echo "OpenStack disabled — skipping all service installations."
    echo "Deployment took ${SECONDS} seconds."
    exit 0
fi

#############################################################################
# Phase 4b: Wire trove physnet2 to br-service via OVN node annotations
#
# Trove guest VMs need L2 reach to MetalLB-announced VIPs (e.g. the
# trove-services-vip carrying RabbitMQ + Keystone). MetalLB advertises on
# the host management VLAN — the same L2 segment the workers' enp5s0 sits
# on (the third NIC, attached to LAB_NAME_PREFIX-net via TROVE_MGMT_*_PORT).
#
# To get there we need:
#   1. br-service exists on every chassis as an OVS bridge.
#   2. enp5s0 is a port of br-service (not br-ex).
#   3. ovn-bridge-mappings includes physnet2:br-service.
#
# All three are owned by the genestack ovn-setup daemonset (deployed by
# setup-infrastructure.sh), which reconciles bridges/ports/mappings off
# `ovn.openstack.org/*` node annotations. We update the annotations here
# and let the daemon do the work.
#
# `setup-infrastructure.sh` initially set bridges='br-ex',
# ports='br-ex:enp5s0', mappings='physnet1:br-ex' — which is wrong for our
# use case (enp5s0 is the trove mgmt port, not an external-network port).
# This block reassigns enp5s0 to br-service.
#
# enp5s0's Linux interface stays DOWN by default (its Neutron port is
# created with --no-fixed-ip), so we also force it up on each worker.
#############################################################################

if svc_enabled trove; then
    echo "Reassigning enp5s0 from br-ex to br-service via OVN node annotations..."
    _ssh <<'EOC'
set -e

# Overwrite annotations on every openstack-network/compute-labelled node.
# `--overwrite` ensures we replace the values setup-infrastructure.sh set
# rather than failing with "annotation already exists".
kubectl annotate --overwrite \
    nodes -l openstack-compute-node=enabled -l openstack-network-node=enabled \
    ovn.openstack.org/bridges='br-ex,br-service'

kubectl annotate --overwrite \
    nodes -l openstack-compute-node=enabled -l openstack-network-node=enabled \
    ovn.openstack.org/ports='br-service:enp5s0'

kubectl annotate --overwrite \
    nodes -l openstack-compute-node=enabled -l openstack-network-node=enabled \
    ovn.openstack.org/mappings='physnet1:br-ex,physnet2:br-service'

# The ovn-setup daemonset reconciles on annotation change. Force a fresh
# pass by deleting its sentinel label so the readiness check re-runs.
kubectl label --overwrite \
    nodes -l openstack-compute-node=enabled \
    ovn.openstack.org/configured-

# Wait for daemon to converge: every chassis should show enp5s0 on
# br-service (and *not* on br-ex), with physnet2:br-service in mappings.
echo "Waiting for ovn-setup daemon to reconcile (enp5s0 → br-service)..."
DEADLINE=$(($(date +%s) + 240))
while [ $(date +%s) -lt $DEADLINE ]; do
    ALL_GOOD=true
    for pod in $(kubectl -n kube-system get pods -l app=ovs -o name); do
        NODE=$(kubectl -n kube-system get ${pod} -o jsonpath='{.spec.nodeName}')
        SVCPORTS=$(kubectl -n kube-system exec ${pod} -c openvswitch -- \
            ovs-vsctl list-ports br-service 2>/dev/null || echo "")
        MAPPING=$(kubectl -n kube-system exec ${pod} -c openvswitch -- \
            ovs-vsctl get Open_vSwitch . external-ids:ovn-bridge-mappings 2>/dev/null | tr -d '"')
        if echo "${SVCPORTS}" | grep -q '^enp5s0$' \
                && echo "${MAPPING}" | grep -q 'physnet2:br-service'; then
            continue
        fi
        ALL_GOOD=false
        echo "  ${NODE}: not ready (br-service ports=${SVCPORTS//$'\n'/,}, mappings=${MAPPING})"
        break
    done
    if [ "${ALL_GOOD}" = "true" ]; then
        echo "All chassis have enp5s0 on br-service and physnet2 mapped."
        break
    fi
    sleep 10
done
if [ "${ALL_GOOD}" != "true" ]; then
    echo "ERROR: ovn-setup did not converge to enp5s0 on br-service in 240s" >&2
    exit 1
fi

# Bring enp5s0 up on every worker — its OpenStack port has --no-fixed-ip
# so cloud-init never brings it up, and OVS happily holds a DOWN port
# without warning. ARP from the trove guest can't reach metallb until the
# kernel link is operationally up.
echo "Bringing enp5s0 up on each worker..."
for node in $(kubectl get nodes -l openstack-network-node=enabled -o name | sed 's|^node/||'); do
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${node} \
        'sudo ip link set enp5s0 up' \
        && echo "  ${node}: enp5s0 up" \
        || echo "  ${node}: WARNING failed to bring enp5s0 up"
done
EOC
fi

#############################################################################
# Phase 5: Install Keystone (blocking — everything depends on it)
#############################################################################

echo "Installing Keystone..."
_ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
/opt/genestack/bin/install-keystone.sh
# Generate clouds.yaml for ubuntu user (not sudo — script uses $(whoami)
# to determine the target path, so running as root puts it in /root/)
/opt/genestack/bin/setup-openstack-rc.sh
EOC

#############################################################################
# Phase 6: Install Core Services in Parallel
#############################################################################

echo "Installing core services in parallel: ${CORE_SERVICES[*]}"

CORE_PIDS=()
CORE_NAMES=()
for svc in "${CORE_SERVICES[@]}"; do
    _ssh_bg bash -s <<EOC &
set -e
source /opt/genestack/scripts/genestack.rc
/opt/genestack/bin/install-${svc}.sh
EOC
    CORE_PIDS+=($!)
    CORE_NAMES+=("install-${svc}")
done

wait_pids CORE_PIDS CORE_NAMES
echo "All core services installed."

#############################################################################
# Phase 6b: Start Cinder Volume Setup (background)
# cinder-volume (bare metal systemd service) must be running before services
# that depend on block storage (Trove, Manila).  Start it in the background
# now — it only needs the cinder K8s secrets from the Helm chart (Phase 6).
# We block on it before Phase 9 (preconf service installs).
#############################################################################

CINDER_VOLUME_PID=""
if svc_enabled cinder; then
    echo "Starting cinder volume setup in background..."
    (
        # PV/VG creation on worker nodes
        _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags cinder \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e worker_0_ip=${WORKER_0_IP} \
    -e worker_1_ip=${WORKER_1_IP} \
    -e worker_2_ip=${WORKER_2_IP}
EOC

        # Wait for apt locks on worker nodes
        _ssh <<EOC
source /opt/genestack/scripts/genestack.rc
for node in ${LAB_NAME_PREFIX}-0 ${LAB_NAME_PREFIX}-1 ${LAB_NAME_PREFIX}-2; do
    echo "Waiting for apt locks on \${node}..."
    ssh -o StrictHostKeyChecking=no \${node} \
        'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo "  apt lock held, waiting..."; sleep 5; done'
done
EOC

        # Deploy cinder-volume systemd service to all nodes
        echo "Running deploy-cinder-volumes-reference playbook..."
        _ssh <<EOC
source /opt/genestack/scripts/genestack.rc
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    -e cinder_release_branch="stable/2025.1" \
    -e storage_network_interface=ansible_enp3s0 \
    -e storage_network_interface_secondary=ansible_enp3s0 \
    -e storage_network_multipath=true \
    -e cinder_backend_name="lvmdriver-1" \
    -e cinder_worker_name="lvm" \
    /opt/genestack/ansible/playbooks/deploy-cinder-volume.yaml -f1 -v
if [ \$? -ne 0 ]; then
    echo "ERROR: deploy-cinder-volume.yaml failed!"
    exit 1
fi
EOC

        # Create volume type and QoS
        echo "Creating cinder volume type and QoS..."
        _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
openstack --os-cloud=default volume type create \
    --description 'Standard with LUKS encryption' \
    --encryption-provider luks \
    --encryption-cipher aes-xts-plain64 \
    --encryption-key-size 256 \
    --encryption-control-location front-end \
    --property volume_backend_name=LVM_iSCSI \
    --property provisioning:max_vol_size='199' \
    --property provisioning:min_vol_size='1' \
    Standard
openstack --os-cloud=default volume qos create \
    --property read_iops_sec_per_gb='20' \
    --property write_iops_sec_per_gb='20' \
    Standard-Block
openstack --os-cloud=default volume qos associate Standard-Block Standard
openstack --os-cloud=default volume type set --private __DEFAULT__
EOC
    ) &
    CINDER_VOLUME_PID=$!
fi

#############################################################################
# Phase 7: Wait for APIs, then parallel long-running prep
#
# Three independent work streams run in parallel:
#   A) Manila: secrets → image build (serial — image needs secrets,
#      and image ID is required for Helm values later)
#   B) Trove: preconf (keypair, secgroup) → image build (serial —
#      image build can background since Trove Helm doesn't need image ID)
#   C) Octavia: preconf (amphora setup)
#############################################################################

echo "Waiting for OpenStack APIs to become ready..."
_ssh <<'EOC'
set -e
source /opt/genestack/scripts/genestack.rc

TIMEOUT=300
INTERVAL=10

if [ ! -f ~/.config/openstack/clouds.yaml ]; then
    echo "ERROR: clouds.yaml not found at ~/.config/openstack/clouds.yaml"
    echo "  setup-openstack-rc.sh may not have run or ran as wrong user"
    exit 1
fi

# Keystone
echo "  Checking Keystone authentication..."
elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    if timeout 15 openstack --os-cloud default token issue >/dev/null 2>&1; then
        echo "  Keystone is ready"
        break
    fi
    echo "  Keystone not ready yet, waiting ${INTERVAL}s... (${elapsed}s/${TIMEOUT}s)"
    sleep $INTERVAL
    ((elapsed+=INTERVAL))
done
if [[ $elapsed -ge $TIMEOUT ]]; then
    echo "ERROR: Timeout waiting for Keystone API"
    exit 1
fi

# Nova
echo "  Checking Nova API..."
elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    if timeout 15 openstack --os-cloud default compute service list >/dev/null 2>&1; then
        nova_up=$(timeout 15 openstack --os-cloud default compute service list -f value -c State 2>/dev/null | grep -c "up" || true)
        if [[ $nova_up -gt 0 ]]; then
            echo "  Nova API is ready (${nova_up} service(s) up)"
            break
        fi
    fi
    echo "  Nova API not ready yet, waiting ${INTERVAL}s... (${elapsed}s/${TIMEOUT}s)"
    sleep $INTERVAL
    ((elapsed+=INTERVAL))
done
if [[ $elapsed -ge $TIMEOUT ]]; then
    echo "ERROR: Timeout waiting for Nova API"
    exit 1
fi

# Neutron
echo "  Checking Neutron API..."
elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    if timeout 15 openstack --os-cloud default network agent list >/dev/null 2>&1; then
        neutron_alive=$(timeout 15 openstack --os-cloud default network agent list -f value -c Alive 2>/dev/null | grep -ci "true" || true)
        if [[ $neutron_alive -gt 0 ]]; then
            echo "  Neutron API is ready (${neutron_alive} agent(s) alive)"
            break
        fi
    fi
    echo "  Neutron API not ready yet, waiting ${INTERVAL}s... (${elapsed}s/${TIMEOUT}s)"
    sleep $INTERVAL
    ((elapsed+=INTERVAL))
done
if [[ $elapsed -ge $TIMEOUT ]]; then
    echo "ERROR: Timeout waiting for Neutron API"
    exit 1
fi

echo "OpenStack APIs are ready"
EOC

#############################################################################
# Phase 7a: Post-setup OpenStack resources (unconditional)
# Flat provider network, router, tenant network, test flavor.
# These are general infrastructure — needed regardless of which preconf
# services are enabled.  Must run AFTER the Neutron API wait so network
# creation has an endpoint to talk to.
#############################################################################

echo "Creating post-setup OpenStack resources (flat network, router, tenant network)..."
if svc_enabled trove; then
    TROVE_MGMT_FLAG="-e create_trove_mgmt_network=true"
else
    TROVE_MGMT_FLAG=""
fi
_ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags post_setup \
    -e create_post_setup_resources=true \
    ${TROVE_MGMT_FLAG} \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC

PREP_PIDS=()
PREP_NAMES=()
TROVE_IMAGE_PID=""

if svc_enabled manila; then
    echo "Starting Manila prep: secrets → image build (blocking for Helm)..."
    _ssh_bg bash -s <<EOC &
set -e
source /opt/genestack/scripts/genestack.rc
# Step 1: Create K8s secrets (keypair, passwords, RabbitMQ/MariaDB sync)
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_secrets \
    -e run_manila_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
# Step 2: Build image (embeds SSH public key from K8s secret, uploads to Glance)
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_image_build \
    -e run_manila_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
    PREP_PIDS+=($!)
    PREP_NAMES+=("manila-secrets-and-image-build")
fi

if svc_enabled trove; then
    echo "Starting Trove prep: secrets → preconf → helm config..."
    _ssh_bg bash -s <<EOC &
set -e
source /opt/genestack/scripts/genestack.rc
# Step 1: Create K8s secrets (SSH keypair, passwords, RabbitMQ/MariaDB sync)
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_secrets \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
# Step 2: Install troveclient
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_client \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
# Step 3: Preconf — keypair, secgroup, re-render helm overrides with real IDs
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_preconf \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
# Step 4: Helm config — deep-merge driver config (admin password, network IDs)
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_helm_config \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX} \
    -e metal_lb_ip=${METAL_LB_IP}
EOC
    PREP_PIDS+=($!)
    PREP_NAMES+=("trove-secrets-preconf-and-helm-config")
fi

if svc_enabled octavia; then
    echo "Starting Octavia pre-configuration..."
    _ssh_bg bash -s <<'EOC' &
set -e
source /opt/genestack/scripts/genestack.rc
OCTAVIA_HELM_FILE=/etc/genestack/helm-configs/octavia/octavia-preconf-overrides.yaml
ANSIBLE_SSH_PIPELINING=0 ansible-playbook /opt/genestack/ansible/playbooks/octavia-preconf-main.yaml \
    -e octavia_os_password=$(kubectl get secrets keystone-admin -n openstack -o jsonpath='{.data.password}' | base64 -d) \
    -e octavia_os_region_name=$(openstack --os-cloud=default endpoint list --service keystone --interface internal -c Region -f value) \
    -e octavia_os_auth_url=$(openstack --os-cloud=default endpoint list --service keystone --interface internal -c URL -f value) \
    -e octavia_os_endpoint_type=internal \
    -e octavia_helm_file=$OCTAVIA_HELM_FILE \
    -e interface=internal \
    -e endpoint_type=internal
EOC
    PREP_PIDS+=($!)
    PREP_NAMES+=("octavia-preconf")
fi

# Manila MUST complete here — we need the image ID for Helm values.
# Trove and Octavia must also complete their preconf before pre-deploy
# touches shared config files.
if [ ${#PREP_PIDS[@]} -gt 0 ]; then
    echo "Waiting for parallel prep to complete..."
    wait_pids PREP_PIDS PREP_NAMES
fi

#############################################################################
# Phase 7b: Allow Trove services VIP as a source on each worker's primary
# port in the OUTER cloud
#
# Trove's helm_config task allocated a VIP from the trove-mgmt subnet pool
# and parked it in a MetalLB IPAddressPool. MetalLB-L2 announces from the
# host's primary NIC (enp3s0 → WORKER_X_PORT in the outer cloud) — the
# only NIC with an IP in the VIP's subnet. The outer cloud's port-security
# on WORKER_X_PORT only allows METAL_LB_IP as a source IP; without an
# explicit allowed-address-pair for the trove VIP, MetalLB's ARP replies
# get dropped and trove guests can't reach RabbitMQ/Keystone via the VIP.
#
# Runs after Phase 7 because the VIP only exists once trove_helm_config
# has applied the IPAddressPool. Uses the outer-cloud OS_CLOUD that the
# script was launched with.
#############################################################################

if svc_enabled trove; then
    TROVE_SVC_VIP=$(_ssh "kubectl -n metallb-system get ipaddresspool trove-services-pool -o jsonpath='{.spec.addresses[0]}' 2>/dev/null" \
                    | tr -d '\r' | sed 's|/.*||')
    if [ -n "${TROVE_SVC_VIP}" ]; then
        echo "Allowing Trove services VIP ${TROVE_SVC_VIP} on each worker's outer-cloud mgmt port..."
        for _idx in 0 1 2; do
            _port_name="${LAB_NAME_PREFIX}-${_idx}-mgmt-port"
            _existing=$(openstack port show "${_port_name}" -f value -c allowed_address_pairs 2>/dev/null \
                        | tr -d '\n')
            if echo "${_existing}" | grep -q "${TROVE_SVC_VIP}"; then
                echo "  ${_port_name}: ${TROVE_SVC_VIP} already permitted"
            else
                openstack port set --allowed-address ip-address="${TROVE_SVC_VIP}" "${_port_name}"
                echo "  ${_port_name}: added allowed-address ${TROVE_SVC_VIP}"
            fi
        done
    else
        echo "WARNING: trove-services-pool not found via kubectl on jump host; skipping outer-cloud allowed-address update" >&2
    fi
fi

#############################################################################
# Phase 8: Pre-deploy config (serial — shared files)
# Gateway listeners, kustomize overlays, and Helm values all write to
# shared files under /etc/genestack.  Run these sequentially to avoid
# race conditions on endpoints.yaml and the flex-gateway.
#############################################################################

if svc_enabled manila; then
    echo "Running Manila pre-deploy (gateway, kustomize, Helm config with image ID)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_gateway,manila_helm_config \
    -e run_manila_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

if svc_enabled trove; then
    echo "Running Trove pre-deploy (gateway, kustomize)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_gateway \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

#############################################################################
# Phase 9: Install Preconf Services in Parallel
# Manila, Trove, Octavia Helm charts — all independent.
# Block on cinder-volume first — Trove/Manila need block storage at runtime.
#############################################################################

if [ -n "${CINDER_VOLUME_PID:-}" ]; then
    echo "Waiting for cinder-volume setup to complete before installing dependent services..."
    wait ${CINDER_VOLUME_PID} || { echo "ERROR: Cinder volume setup failed"; exit 1; }
    echo "Cinder volume setup complete."
    CINDER_VOLUME_PID=""
fi

PRECONF_INSTALL_PIDS=()
PRECONF_INSTALL_NAMES=()

for svc in "${PRECONF_SERVICES[@]}"; do
    svc_enabled "$svc" || continue
    echo "Installing ${svc}..."
    _ssh_bg bash -s <<EOC &
set -e
source /opt/genestack/scripts/genestack.rc
/opt/genestack/bin/install-${svc}.sh
EOC
    PRECONF_INSTALL_PIDS+=($!)
    PRECONF_INSTALL_NAMES+=("install-${svc}")
done

if [ ${#PRECONF_INSTALL_PIDS[@]} -gt 0 ]; then
    echo "Waiting for preconf service installs to complete..."
    wait_pids PRECONF_INSTALL_PIDS PRECONF_INSTALL_NAMES
fi

#############################################################################
# Phase 9b: Trove image build (background)
# Secrets, preconf, and helm config already ran in Phase 7.
# The Helm install in Phase 9 deployed Trove with correct overrides.
# Kick off the image build now — datastore setup (Phase 10) will wait for it.
#############################################################################

if svc_enabled trove; then
    echo "Starting Trove image build (background)..."
    _ssh_bg bash -s <<EOC &
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_image_build \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
    TROVE_IMAGE_PID=$!
fi

#############################################################################
# Phase 9c: Wait for preconf service APIs before post-deploy tasks
# Helm charts were just installed in Phase 9 — pods need time to start.
# Wait for Manila/Trove APIs to become reachable before running their
# post-deploy setup (share types, datastore registration, etc.).
#############################################################################

if svc_enabled manila || svc_enabled trove; then
    if svc_enabled manila; then WAIT_MANILA=true; else WAIT_MANILA=false; fi
    if svc_enabled trove;  then WAIT_TROVE=true;  else WAIT_TROVE=false;  fi
    echo "Waiting for preconf service APIs to become ready for post-deploy..."
    _ssh <<EOC
source /opt/genestack/scripts/genestack.rc

TIMEOUT=600
INTERVAL=15

if [ "${WAIT_MANILA}" = "true" ]; then
    echo "  Checking Manila API..."
    elapsed=0
    while [[ \$elapsed -lt \$TIMEOUT ]]; do
        if timeout 15 openstack --os-cloud default share type list -f json >/dev/null 2>&1; then
            echo "  Manila API is ready"
            break
        fi
        echo "  Manila API not ready yet, waiting \${INTERVAL}s... (\${elapsed}s/\${TIMEOUT}s)"
        sleep \$INTERVAL
        ((elapsed+=INTERVAL))
    done
    if [[ \$elapsed -ge \$TIMEOUT ]]; then
        echo "WARNING: Timeout waiting for Manila API — share type setup may be skipped"
    fi
fi

if [ "${WAIT_TROVE}" = "true" ]; then
    echo "  Checking Trove API..."
    elapsed=0
    while [[ \$elapsed -lt \$TIMEOUT ]]; do
        if timeout 15 openstack --os-cloud default datastore list -f json >/dev/null 2>&1; then
            echo "  Trove API is ready"
            break
        fi
        echo "  Trove API not ready yet, waiting \${INTERVAL}s... (\${elapsed}s/\${TIMEOUT}s)"
        sleep \$INTERVAL
        ((elapsed+=INTERVAL))
    done
    if [[ \$elapsed -ge \$TIMEOUT ]]; then
        echo "WARNING: Timeout waiting for Trove API — datastore setup may be skipped"
    fi
fi

echo "Preconf service API checks complete"
EOC
fi

#############################################################################
# Phase 10: Post-Deploy Tasks
# Manila share type and Trove datastore setup.
#############################################################################

if svc_enabled manila; then
    echo "Running Manila post-deploy (share type setup)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags manila_post_deploy \
    -e run_manila_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

if svc_enabled trove; then
    # Keypair must be created AFTER Trove helm install (trove-ks-user job
    # creates the Keystone user). The API wait above guarantees this.
    echo "Creating Trove keypair (post-deploy, requires trove Keystone user)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_keypair \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC

    # Wait for Trove image build (backgrounded in Phase 9b) — datastore
    # needs the image to exist in Glance.
    if [ -n "${TROVE_IMAGE_PID:-}" ]; then
        echo "Waiting for Trove image build to complete..."
        wait ${TROVE_IMAGE_PID} || { echo "ERROR: Trove image build failed"; exit 1; }
        echo "Trove image build complete."
    fi

    echo "Running Trove post-deploy (datastore setup)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_datastore \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

#############################################################################
# Phase 12: Trove SSH Key Distribution
#############################################################################

if svc_enabled trove; then
    echo "Distributing Trove SSH key to nodes..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
ansible-playbook /opt/genestack/ansible/playbooks/hclab-service-conf.yaml \
    --tags trove_post_deploy \
    -e run_trove_preconf=true \
    -e lab_name_prefix=${LAB_NAME_PREFIX}
EOC
fi

#############################################################################
# Phase 13: Install Skyline LAST
# Skyline's nginx-generator reads the Keystone service catalog at pod
# startup — all service endpoints must be registered before this runs.
#############################################################################

if svc_enabled skyline; then
    echo "Installing Skyline (all service endpoints now registered)..."
    _ssh <<EOC
set -e
source /opt/genestack/scripts/genestack.rc
/opt/genestack/bin/install-skyline.sh
EOC
fi

#############################################################################
# Extras
#############################################################################

for extra in "${EXTRAS[@]}"; do
    case "$extra" in
        k9s) installK9sRemote ;;
        *)   echo "Unknown extra: $extra" ;;
    esac
done

#############################################################################
# Tests
#############################################################################

if [ "${TEST_LEVEL}" != "off" ]; then
    echo "Waiting for OpenStack APIs before running tests..."
    _ssh <<'EOC'
set -e
source /opt/genestack/scripts/genestack.rc
TIMEOUT=300
INTERVAL=10
if [ ! -f ~/.config/openstack/clouds.yaml ]; then
    echo "ERROR: clouds.yaml not found at ~/.config/openstack/clouds.yaml"
    exit 1
fi
elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    if timeout 15 openstack --os-cloud default token issue >/dev/null 2>&1; then
        echo "  Keystone is ready"; break
    fi
    echo "  Keystone not ready yet (${elapsed}s/${TIMEOUT}s)"; sleep $INTERVAL; ((elapsed+=INTERVAL))
done
[[ $elapsed -ge $TIMEOUT ]] && echo "ERROR: Timeout waiting for Keystone" && exit 1
echo "OpenStack APIs are ready for tests"
EOC
    echo "Running tests at level: ${TEST_LEVEL}"
    _ssh "sudo TEST_RESULTS_DIR=/tmp/test-results /opt/genestack/scripts/tests/run-all-tests.sh ${TEST_LEVEL}"
    mkdir -p test-results
    scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.xml ./test-results/ 2>/dev/null || echo "No test result XML files found"
    scp -o ForwardAgent=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        ${SSH_USERNAME}@${JUMP_HOST_VIP}:/tmp/test-results/*.txt ./test-results/ 2>/dev/null || echo "No test result text files found"
fi

#############################################################################
# Phase 14: Skyline gateway route fixup
# install-skyline.sh attaches custom-skyline-gateway-route to the default
# listener; flex-gateway needs it on the cluster-tls listener instead so the
# Skyline UI is reachable via HTTPS.
#############################################################################

if svc_enabled skyline; then
    echo "Patching skyline gateway route to use cluster-tls listener..."
    _ssh <<'EOC'
set -e
source /opt/genestack/scripts/genestack.rc
kubectl patch httproute custom-skyline-gateway-route -n openstack \
    --type=json \
    -p '[{"op": "replace", "path": "/spec/parentRefs/0/sectionName", "value": "cluster-tls"}]'
EOC
fi

#############################################################################
# Output Summary
#############################################################################

ALL_SERVICES=("${CORE_SERVICES[@]}")
for s in "${PRECONF_SERVICES[@]}"; do svc_enabled "$s" && ALL_SERVICES+=("$s"); done
svc_enabled skyline && ALL_SERVICES+=("skyline")

{ cat | tee /tmp/output.txt; } <<EOF
================================================================================
HCL Builder — Hyperconverged Lab Deployment Complete!
================================================================================

Deployment took ${SECONDS} seconds to complete.

Cluster Information:
  - Jump Host Address: ${JUMP_HOST_VIP}
  - MetalLB Internal IP: ${METAL_LB_IP}
  - MetalLB Public VIP: ${METAL_LB_VIP}

Services Installed: ${ALL_SERVICES[*]}
Extras: ${EXTRAS[*]:-none}

SSH Access:
  ssh ${SSH_USERNAME}@${JUMP_HOST_VIP}

Kubernetes Access (from jump host):
  kubectl get nodes

Important Notes:
  - SSH key stored at ~/.ssh/${LAB_NAME_PREFIX}-key.pem
  - All cluster operations should be performed from the jump host
================================================================================
EOF
