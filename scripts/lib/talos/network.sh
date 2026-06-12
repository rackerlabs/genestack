#!/usr/bin/env bash
# Talos-specific networking functions

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function selectJumpHostFlavor() {
    if [ -z "${JUMP_HOST_FLAVOR}" ]; then
        local SMALL_FLAVORS
        SMALL_FLAVORS=$(openstack flavor list --sort-column Name -c Name -c RAM -c VCPUs -c Disk -f json 2>/dev/null)
        local IDEAL_FLAVORS
        IDEAL_FLAVORS=$(echo "${SMALL_FLAVORS}" | jq -r '[.[] | select( .RAM >= 1536 and .RAM <= 4096 and .VCPUs <= 2 and .Disk >= 10)]')
        local BROADER_FLAVORS
        BROADER_FLAVORS=$(echo "${SMALL_FLAVORS}" | jq -r '[.[] | select( .RAM >= 1024 and .RAM <= 8192 and .VCPUs <= 4 and .Disk >= 10)]')

        local DEFAULT_JUMP_FLAVOR
        DEFAULT_JUMP_FLAVOR=$(echo "${IDEAL_FLAVORS}" | jq -r 'if length > 0 then .[0].Name else "NONE" end')
        if [ "${DEFAULT_JUMP_FLAVOR}" = "NONE" ]; then
            DEFAULT_JUMP_FLAVOR=$(echo "${BROADER_FLAVORS}" | jq -r 'if length > 0 then .[0].Name else "NONE" end')
        fi

        read -rp "Enter the name of the flavor to use for the instances [${DEFAULT_JUMP_FLAVOR}]: " JUMP_HOST_FLAVOR || _log SKIP
        export JUMP_HOST_FLAVOR="${JUMP_HOST_FLAVOR:-${DEFAULT_JUMP_FLAVOR}}"

        if [ -z "${JUMP_HOST_FLAVOR}" ]; then
            _log ERROR "No suitable jump host flavor found"
            exit 1
        fi
    fi
}

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

function createTalosSecurityGroup() {
    local _sg="${LAB_NAME_PREFIX}-talos-secgroup"
    if ! openstack security group show ${_sg} -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating Talos security group"
        openstack security group create ${_sg} >/dev/null 2>&1 || { _log ERROR "Talos security group creation failed"; return 1; }
    fi

    if ! openstack security group show ${_sg} -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -qx 50000; then
        _log INFO "Adding Talos API rule (50000)"
        openstack security group rule create ${_sg} \
            --protocol tcp --ingress --remote-ip 0.0.0.0/0 --dst-port 50000 \
            --description "Talos API" >/dev/null 2>&1 || { _log ERROR "Talos API rule creation failed"; return 1; }
    fi
    if ! openstack security group show ${_sg} -f json 2>/dev/null | jq -r '.rules[].port_range_max' | grep -qx 6443; then
        _log INFO "Adding K8s API rule (6443)"
        openstack security group rule create ${_sg} \
            --protocol tcp --ingress --remote-ip 0.0.0.0/0 --dst-port 6443 \
            --description "K8s API" >/dev/null 2>&1 || { _log ERROR "K8s API rule creation failed"; return 1; }
    fi
    if ! openstack security group show ${_sg} -f json 2>/dev/null | jq -r '.rules[].protocol' | grep -qx icmp; then
        _log INFO "Adding ICMP rule"
        openstack security group rule create ${_sg} \
            --protocol icmp --ingress --remote-ip 0.0.0.0/0 \
            --description "ICMP" >/dev/null 2>&1 || { _log ERROR "ICMP rule creation failed"; return 1; }
    fi
}
