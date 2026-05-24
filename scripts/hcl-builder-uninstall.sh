#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# HCL Builder — Uninstall / Teardown
#
# Destroys all OpenStack resources created by hcl-builder.sh.
# Reverse order: servers → volumes → floating IPs → ports → keypair →
#                security groups → router interfaces → subnets →
#                networks → router
#
# Resource names are deterministic (all ${PREFIX}-*), so we skip
# per-resource existence checks and just delete with || true.
# Only floating IPs require a lookup (we need the actual IP values).
#
# Usage:
#   hcl-builder-uninstall.sh -c <config> [-y]
#   hcl-builder-uninstall.sh -p <prefix> [-C <cloud>] [-y]
#
# Options:
#   -c FILE     Config file (same format as hcl-builder.sh)
#   -p PREFIX   Lab name prefix (overrides config, default: hyperconverged)
#   -C CLOUD    OpenStack cloud name (overrides config, default: default)
#   -y          Skip confirmation prompt
#

set -o pipefail
set -e

SKIP_CONFIRM=false
_flag_prefix=""
_flag_cloud=""

# Pass 1: source config file first
OPTIND=1
while getopts "c:p:C:y" opt; do
    case $opt in
        c)
            if [ ! -f "$OPTARG" ]; then
                echo "Config file not found: $OPTARG"
                exit 1
            fi
            source "$OPTARG"
            ;;
        *) ;;
    esac
done

# Pass 2: flags override config
OPTIND=1
while getopts "c:p:C:y" opt; do
    case $opt in
        c) ;;
        p) _flag_prefix="$OPTARG" ;;
        C) _flag_cloud="$OPTARG" ;;
        y) SKIP_CONFIRM=true ;;
        *)
            echo "Usage: $0 -c <config> [-p prefix] [-C cloud] [-y]"
            exit 1
            ;;
    esac
done

PREFIX="${_flag_prefix:-${LAB_NAME_PREFIX:-hyperconverged}}"
export OS_CLOUD="${_flag_cloud:-${OS_CLOUD:-default}}"

echo "=== HCL Builder Uninstall ==="
echo "  Prefix: ${PREFIX}"
echo "  Cloud:  ${OS_CLOUD}"
echo ""

# All resource names are known — just list what will be attempted.
# Only floating IPs need a single API call to resolve actual addresses.
FLOATING_IPS=()
for port_name in ${PREFIX}-metallb-vip-0-port ${PREFIX}-0-mgmt-port; do
    fip=$(openstack floating ip list --port ${port_name} -f value -c "Floating IP Address" 2>/dev/null || true)
    [ -n "$fip" ] && FLOATING_IPS+=("$fip")
done

echo "Resources to destroy:"
echo "  Servers:         ${PREFIX}-0 ${PREFIX}-1 ${PREFIX}-2"
echo "  Volumes:         ${PREFIX}-0-cv1 ${PREFIX}-1-cv1 ${PREFIX}-2-cv1"
[ ${#FLOATING_IPS[@]} -gt 0 ] && echo "  Floating IPs:    ${FLOATING_IPS[*]}"
echo "  Mgmt ports:      ${PREFIX}-0-mgmt-port ${PREFIX}-1-mgmt-port ${PREFIX}-2-mgmt-port"
echo "  Compute ports:   ${PREFIX}-0-compute-port ${PREFIX}-1-compute-port ${PREFIX}-2-compute-port"
echo "  Float ports:     ${PREFIX}-0-compute-float-{100..109}-port"
echo "  MetalLB port:    ${PREFIX}-metallb-vip-0-port"
echo "  Security groups: ${PREFIX}-jump-secgroup ${PREFIX}-http-secgroup ${PREFIX}-secgroup"
echo "  Keypair:         ${PREFIX}-key (OpenStack only — local SSH keys preserved)"
echo "  Subnets:         ${PREFIX}-subnet ${PREFIX}-compute-subnet"
echo "  Networks:        ${PREFIX}-net ${PREFIX}-compute-net"
echo "  Router:          ${PREFIX}-router"
echo ""

if [ "$SKIP_CONFIRM" != true ]; then
    read -rp "Destroy all resources with prefix '${PREFIX}'? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# From here on, don't bail on individual failures — resources may not exist.
set +e

#############################################################################
# 1. Delete servers (this detaches volumes automatically)
#############################################################################

for idx in 0 1 2; do
    echo "Deleting server ${PREFIX}-${idx}..."
    openstack server delete --wait ${PREFIX}-${idx} 2>/dev/null
done

#############################################################################
# 2. Delete volumes
#############################################################################

for idx in 0 1 2; do
    vol="${PREFIX}-${idx}-cv1"
    # Wait briefly for volume to detach after server delete
    for _ in $(seq 1 30); do
        status=$(openstack volume show ${vol} -f value -c status 2>/dev/null || echo "gone")
        [[ "$status" =~ ^(available|error|gone)$ ]] && break
        sleep 2
    done
    if [ "$status" != "gone" ]; then
        echo "Deleting volume ${vol}..."
        openstack volume delete ${vol} 2>/dev/null
    fi
done

#############################################################################
# 3. Delete floating IPs
#############################################################################

for fip in "${FLOATING_IPS[@]}"; do
    echo "Deleting floating IP ${fip}..."
    openstack floating ip delete ${fip} 2>/dev/null
done

#############################################################################
# 4. Delete ports
#############################################################################

for idx in 0 1 2; do
    echo "Deleting port ${PREFIX}-${idx}-mgmt-port..."
    openstack port delete ${PREFIX}-${idx}-mgmt-port 2>/dev/null
    echo "Deleting port ${PREFIX}-${idx}-compute-port..."
    openstack port delete ${PREFIX}-${idx}-compute-port 2>/dev/null
    echo "Deleting port ${PREFIX}-${idx}-trove-mgmt-port..."
    openstack port delete ${PREFIX}-${idx}-trove-mgmt-port 2>/dev/null
done

for i in $(seq 100 109); do
    openstack port delete ${PREFIX}-0-compute-float-${i}-port 2>/dev/null
done

echo "Deleting MetalLB port ${PREFIX}-metallb-vip-0-port..."
openstack port delete ${PREFIX}-metallb-vip-0-port 2>/dev/null

#############################################################################
# 5. Delete keypair (OpenStack only — local key files preserved)
#############################################################################

echo "Deleting keypair ${PREFIX}-key from OpenStack..."
openstack keypair delete ${PREFIX}-key 2>/dev/null

#############################################################################
# 6. Delete security groups
#############################################################################

for sg in ${PREFIX}-jump-secgroup ${PREFIX}-http-secgroup ${PREFIX}-secgroup; do
    echo "Deleting security group ${sg}..."
    openstack security group delete ${sg} 2>/dev/null
done

#############################################################################
# 7. Remove router interfaces, delete subnets
#############################################################################

for sub in ${PREFIX}-subnet ${PREFIX}-compute-subnet; do
    echo "Removing ${sub} from router..."
    openstack router remove subnet ${PREFIX}-router ${sub} 2>/dev/null
done

for sub in ${PREFIX}-subnet ${PREFIX}-compute-subnet; do
    echo "Deleting subnet ${sub}..."
    openstack subnet delete ${sub} 2>/dev/null
done

#############################################################################
# 8. Delete networks
#############################################################################

for net in ${PREFIX}-net ${PREFIX}-compute-net; do
    echo "Deleting network ${net}..."
    openstack network delete ${net} 2>/dev/null
done

#############################################################################
# 9. Delete router
#############################################################################

echo "Deleting router ${PREFIX}-router..."
openstack router delete ${PREFIX}-router 2>/dev/null

echo ""
echo "=== Teardown complete ==="
echo "All resources with prefix '${PREFIX}' have been removed."
