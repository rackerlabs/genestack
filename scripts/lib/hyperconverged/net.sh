#!/usr/bin/env bash
# Shell networking functions for hyperconverged lab
# Sourced from helpers.sh or orchestrator scripts

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function createRouter() {
    if ! openstack router show ${LAB_NAME_PREFIX}-router -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating router ${LAB_NAME_PREFIX}-router"
        openstack router create ${LAB_NAME_PREFIX}-router --external-gateway PUBLICNET >/dev/null 2>&1 || { _log ERROR "Router creation failed"; return 1; }
    fi
}

function createNetworks() {
    if ! openstack network show ${LAB_NAME_PREFIX}-net -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating network ${LAB_NAME_PREFIX}-net"
        openstack network create ${LAB_NAME_PREFIX}-net --mtu ${LAB_NETWORK_MTU} >/dev/null 2>&1 || { _log ERROR "Network creation failed"; return 1; }
    fi

    if ! openstack subnet show ${LAB_NAME_PREFIX}-subnet -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating subnet ${LAB_NAME_PREFIX}-subnet"
        openstack subnet create ${LAB_NAME_PREFIX}-subnet \
            --network ${LAB_NAME_PREFIX}-net \
            --subnet-range 192.168.100.0/24 \
            --dns-nameserver 1.1.1.1 \
            --dns-nameserver 1.0.0.1 >/dev/null 2>&1 || { _log ERROR "Subnet creation failed"; return 1; }
    fi

    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2>/dev/null | jq -r '.interfaces_info[].subnet_id' | grep -q $(openstack subnet show ${LAB_NAME_PREFIX}-subnet -f value -c id 2>/dev/null) 2>/dev/null; then
        _log INFO "Adding subnet ${LAB_NAME_PREFIX}-subnet to router"
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet >/dev/null 2>&1 || { _log ERROR "Failed to add subnet to router"; return 1; }
    fi

    if ! openstack network show ${LAB_NAME_PREFIX}-compute-net -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating compute network ${LAB_NAME_PREFIX}-compute-net"
        openstack network create ${LAB_NAME_PREFIX}-compute-net --disable-port-security --mtu ${LAB_NETWORK_MTU} >/dev/null 2>&1 || { _log ERROR "Compute network creation failed"; return 1; }
    fi

    if ! openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f value -c name >/dev/null 2>&1; then
        _log INFO "Creating compute subnet ${LAB_NAME_PREFIX}-compute-subnet"
        openstack subnet create ${LAB_NAME_PREFIX}-compute-subnet \
            --network ${LAB_NAME_PREFIX}-compute-net \
            --subnet-range 192.168.102.0/24 \
            --no-dhcp >/dev/null 2>&1 || { _log ERROR "Compute subnet creation failed"; return 1; }
    fi

    if ! openstack router show ${LAB_NAME_PREFIX}-router -f json 2>/dev/null | jq -r '.interfaces_info[].subnet_id' | grep -q $(openstack subnet show ${LAB_NAME_PREFIX}-compute-subnet -f value -c id 2>/dev/null) 2>/dev/null; then
        _log INFO "Adding compute subnet ${LAB_NAME_PREFIX}-compute-subnet to router"
        openstack router add subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet >/dev/null 2>&1 || { _log ERROR "Failed to add compute subnet to router"; return 1; }
    fi
}

function createMetalLBPort() {
    if ! openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id >/dev/null 2>&1; then
        _log INFO "Creating MetalLB VIP port"
        openstack port create \
            --security-group ${LAB_NAME_PREFIX}-http-secgroup \
            --network ${LAB_NAME_PREFIX}-net \
            ${LAB_NAME_PREFIX}-metallb-vip-0-port >/dev/null 2>&1 || { _log ERROR "MetalLB VIP port creation failed"; return 1; }
    fi
    METAL_LB_PORT_ID=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id 2>/dev/null)
    export METAL_LB_PORT_ID
    METAL_LB_IP=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f json 2>/dev/null | jq -r '.fixed_ips[0].ip_address')
    export METAL_LB_IP

    if ! openstack floating ip list --port ${METAL_LB_PORT_ID} -f value -c "Floating IP Address" >/dev/null 2>&1; then
        _log INFO "Creating MetalLB VIP floating IP"
        openstack floating ip create PUBLICNET --port ${METAL_LB_PORT_ID} >/dev/null 2>&1 || { _log ERROR "MetalLB floating IP creation failed"; return 1; }
    fi
    METAL_LB_VIP=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f value -c "Floating IP Address" 2>/dev/null)
    export METAL_LB_VIP
}
