#!/usr/bin/env bash
set -o pipefail
export OS_CLOUD="${OS_CLOUD:-dfw-dev-me}"

# Accept platform as first arg or prompt
if [ -n "$1" ]; then
    PLATFORM="$1"
else
    echo ""
    echo "Hyperconverged Lab Uninstall"
    echo "============================="
    echo ""
    echo "Select platform to uninstall:"
    echo ""
    echo "  1) Kubespray — Ubuntu VMs + Kubespray"
    echo "  2) Talos — Talos Linux + talosctl"
    echo ""
    read -rp "Enter choice [1/2]: " choice
    case "${choice:-1}" in
        1|kubespray) PLATFORM="kubespray" ;;
        2|talos)     PLATFORM="talos" ;;
        *)           echo "Invalid choice."; exit 1 ;;
    esac
fi

echo ""
echo "Uninstalling ${PLATFORM} lab..."
echo ""

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"
source "$(dirname "${BASH_SOURCE[0]}")/lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/hyperconverged-uninstall-common.sh"

_log STEP "Starting ${PLATFORM} uninstall"

# Delete servers (skip VM setup for kubespray, only servers exist)
_log INFO "Deleting servers"
for i in 0 1 2; do
    if openstack server show ${LAB_NAME_PREFIX}-${i} -f value -c status >/dev/null 2>&1; then
        _log INFO "  Deleting server ${LAB_NAME_PREFIX}-${i}"
        openstack server delete ${LAB_NAME_PREFIX}-${i} >/dev/null 2>&1
    fi
done

# Wait for servers to terminate
_log INFO "Waiting for servers to terminate"
_wait_for_servers_term 180
_wait_for_servers_term 180

# Delete volumes if cinder enabled
if [ "${HYPERCONVERGED_CINDER_VOLUME:-false}" = "true" ]; then
    _log INFO "Deleting cinder volumes"
    for i in 0 1 2; do
        openstack volume delete --recursive ${LAB_NAME_PREFIX}-${i}-cv1 2>/dev/null || true
    done
    _wait_volumes_term 120
fi

# Delete floating IPs on jump host (mgmt port 0)
_log INFO "Deleting jump host floating IP"
if openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id >/dev/null 2>&1; then
    JUMP_HOST_PORT=$(openstack port show ${LAB_NAME_PREFIX}-0-mgmt-port -f value -c id)
    if FIP_ID=$(openstack floating ip list --port ${JUMP_HOST_PORT} -f value -c ID 2>/dev/null); then
        openstack floating ip delete ${FIP_ID} >/dev/null 2>&1 || true
    fi
fi

# Delete MetalLB floating IP
_log INFO "Deleting MetalLB floating IP"
if openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id >/dev/null 2>&1; then
    METAL_LB_PORT_ID=$(openstack port show ${LAB_NAME_PREFIX}-metallb-vip-0-port -f value -c id)
    if FIP_ID=$(openstack floating ip list --port ${METAL_LB_PORT_ID} -f value -c ID 2>/dev/null); then
        openstack floating ip delete ${FIP_ID} >/dev/null 2>&1 || true
    fi
fi

# Detach router state before deleting lab ports so router-owned interfaces
# do not keep the network resources pinned.
_log INFO "Detaching router gateway and subnets"
openstack router set --no-gateway ${LAB_NAME_PREFIX}-router 2>/dev/null || true
openstack router remove subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-compute-subnet 2>/dev/null || true
openstack router remove subnet ${LAB_NAME_PREFIX}-router ${LAB_NAME_PREFIX}-subnet 2>/dev/null || true

# Delete all ports (compute + metadata + mgmt + metalLB)
_log INFO "Deleting all ports"
_delete_all_ports "${LAB_NAME_PREFIX}"

# Delete security groups
_log INFO "Deleting security groups (rules first)"
_delete_security_groups "${LAB_NAME_PREFIX}"

# Delete subnets (need from router first)
_log INFO "Deleting subnets"
openstack subnet delete ${LAB_NAME_PREFIX}-compute-subnet 2>/dev/null || true
openstack subnet delete ${LAB_NAME_PREFIX}-subnet 2>/dev/null || true

# Delete networks
_log INFO "Deleting networks"
openstack network delete ${LAB_NAME_PREFIX}-compute-net 2>/dev/null || true
openstack network delete ${LAB_NAME_PREFIX}-net 2>/dev/null || true

# Delete router
_log INFO "Deleting router"
openstack router delete ${LAB_NAME_PREFIX}-router 2>/dev/null || true

# Delete keypair
_log INFO "Deleting keypair"
openstack keypair delete ${LAB_NAME_PREFIX}-key 2>/dev/null || true

# Clean up local SSH files
if [ -f "${HOME}/.ssh/${LAB_NAME_PREFIX}-key.pem" ]; then
    _log INFO "Cleaning local SSH keys"
    rm -f "${HOME}/.ssh/${LAB_NAME_PREFIX}-key.pem" "${HOME}/.ssh/${LAB_NAME_PREFIX}-key.pub"
fi

_log STEP "Uninstall complete"
