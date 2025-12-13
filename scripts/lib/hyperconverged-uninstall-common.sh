#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Uninstall Common Library
#
# This library contains shared functions used by both Kubespray
# and Talos Linux hyperconverged lab uninstall scripts.
#
# Source this file from platform-specific uninstall scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/hyperconverged-uninstall-common.sh"
#

#############################################################################
# Common Uninstall Functions
#############################################################################

function serverDelete() {
    if ! openstack server delete "${1}" 2> /dev/null; then
        echo "Failed to delete server ${1} (may not exist)"
    else
        echo "Deleted server ${1}"
    fi
}

function portDelete() {
    if ! openstack port delete "${1}" 2> /dev/null; then
        echo "Failed to delete port ${1} (may not exist)"
    else
        echo "Deleted port ${1}"
    fi
}

function securityGroupDelete() {
    if ! openstack security group delete "${1}" 2> /dev/null; then
        echo "Failed to delete security group ${1} (may not exist)"
    else
        echo "Deleted security group ${1}"
    fi
}

function networkDelete() {
    if ! openstack network delete "${1}" 2> /dev/null; then
        echo "Failed to delete network ${1} (may not exist)"
    else
        echo "Deleted network ${1}"
    fi
}

function subnetDelete() {
    if ! openstack subnet delete "${1}" 2> /dev/null; then
        echo "Failed to delete subnet ${1} (may not exist)"
    else
        echo "Deleted subnet ${1}"
    fi
}

function keypairDelete() {
    if ! openstack keypair delete "${1}" 2> /dev/null; then
        echo "Failed to delete keypair ${1} (may not exist)"
    else
        echo "Deleted keypair ${1}"
    fi
}

function promptForCloudConfig() {
    # Prompt for OS_CLOUD if not set
    if [ -z "${OS_CLOUD}" ]; then
        read -rp "Enter name of the cloud configuration used for this build [default]: " OS_CLOUD
        export OS_CLOUD="${OS_CLOUD:-default}"
    fi
}

function deleteFloatingIPs() {
    # Delete all floating IPs associated with the lab router
    # Usage: deleteFloatingIPs <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting floating IPs..."
    for i in $(openstack floating ip list --router ${lab_prefix}-router -f value -c "Floating IP Address" 2>/dev/null); do
        if ! openstack floating ip unset "${i}" 2> /dev/null; then
            echo "Failed to unset floating ip ${i}"
        fi
        if ! openstack floating ip delete "${i}" 2> /dev/null; then
            echo "Failed to delete floating ip ${i}"
        else
            echo "Deleted floating ip ${i}"
        fi
    done
}

function deleteServers() {
    # Delete lab servers
    # Usage: deleteServers <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting servers..."
    serverDelete ${lab_prefix}-2
    serverDelete ${lab_prefix}-1
    serverDelete ${lab_prefix}-0
}

function deleteComputePorts() {
    # Delete compute network ports
    # Usage: deleteComputePorts <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting compute ports..."
    portDelete ${lab_prefix}-2-compute-port
    portDelete ${lab_prefix}-1-compute-port
    portDelete ${lab_prefix}-0-compute-port

    # Delete floating compute ports
    for i in {100..109}; do
        portDelete "${lab_prefix}-0-compute-float-${i}-port"
    done
}

function deleteManagementPorts() {
    # Delete management network ports
    # Usage: deleteManagementPorts <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting management ports..."
    portDelete ${lab_prefix}-2-mgmt-port
    portDelete ${lab_prefix}-1-mgmt-port
    portDelete ${lab_prefix}-0-mgmt-port
    portDelete ${lab_prefix}-metallb-vip-0-port
}

function deleteCommonSecurityGroups() {
    # Delete common security groups
    # Usage: deleteCommonSecurityGroups <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting security groups..."
    securityGroupDelete ${lab_prefix}-http-secgroup
    securityGroupDelete ${lab_prefix}-secgroup
}

function deleteRouterAndSubnets() {
    # Remove subnets from router and delete router
    # Usage: deleteRouterAndSubnets <lab_name_prefix>
    local lab_prefix="$1"

    echo "Removing subnets from router..."
    if ! openstack router remove subnet ${lab_prefix}-router ${lab_prefix}-subnet 2> /dev/null; then
        echo "Failed to remove ${lab_prefix}-subnet from router ${lab_prefix}-router"
    fi
    if ! openstack router remove subnet ${lab_prefix}-router ${lab_prefix}-compute-subnet 2> /dev/null; then
        echo "Failed to remove ${lab_prefix}-compute-subnet from router ${lab_prefix}-router"
    fi

    echo "Removing gateway from router..."
    if ! openstack router remove gateway ${lab_prefix}-router PUBLICNET 2> /dev/null; then
        echo "Failed to remove gateway from router ${lab_prefix}-router"
    fi

    echo "Deleting router..."
    if ! openstack router delete ${lab_prefix}-router 2> /dev/null; then
        echo "Failed to delete router ${lab_prefix}-router"
    else
        echo "Deleted router ${lab_prefix}-router"
    fi
}

function deleteSubnets() {
    # Delete subnets
    # Usage: deleteSubnets <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting subnets..."
    subnetDelete ${lab_prefix}-compute-subnet
    subnetDelete ${lab_prefix}-subnet
}

function deleteNetworks() {
    # Delete networks
    # Usage: deleteNetworks <lab_name_prefix>
    local lab_prefix="$1"

    echo "Deleting networks..."
    networkDelete ${lab_prefix}-compute-net
    networkDelete ${lab_prefix}-net
}

function runCommonUninstall() {
    # Run common uninstall steps for all platforms
    # Usage: runCommonUninstall <lab_name_prefix>
    local lab_prefix="$1"

    deleteFloatingIPs "${lab_prefix}"
    deleteServers "${lab_prefix}"
    deleteComputePorts "${lab_prefix}"
    deleteManagementPorts "${lab_prefix}"
    deleteCommonSecurityGroups "${lab_prefix}"
    deleteRouterAndSubnets "${lab_prefix}"
    deleteSubnets "${lab_prefix}"
    deleteNetworks "${lab_prefix}"
}
