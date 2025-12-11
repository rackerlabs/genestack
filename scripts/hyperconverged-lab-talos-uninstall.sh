#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Uninstall Script for Talos Linux
#
# This script removes all resources created by the Talos hyperconverged lab script.
#

set -o pipefail
set -e
SECONDS=0

# Source common uninstall library
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/lib/hyperconverged-uninstall-common.sh"

#############################################################################
# Initialize
#############################################################################

promptForCloudConfig

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-talos-hyperconverged}"

#############################################################################
# Run Common Uninstall
#############################################################################

runCommonUninstall "${LAB_NAME_PREFIX}"

#############################################################################
# Talos-Specific: Delete Jump Host, Security Groups, and Keypair
#############################################################################

echo "Deleting Talos-specific resources..."

# Delete jump host
serverDelete ${LAB_NAME_PREFIX}-jump
portDelete ${LAB_NAME_PREFIX}-jump-mgmt-port

# Delete security groups
securityGroupDelete ${LAB_NAME_PREFIX}-talos-secgroup
securityGroupDelete ${LAB_NAME_PREFIX}-jump-secgroup

# Delete keypair
keypairDelete ${LAB_NAME_PREFIX}-key

#############################################################################
# Optional: Remove Talos Image from Glance
#############################################################################

read -rp "Do you want to remove the Talos image from Glance? [y/N]: " REMOVE_IMAGE
if [[ "${REMOVE_IMAGE}" =~ ^[Yy]$ ]]; then
    TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
    TALOS_IMAGE_NAME="${TALOS_IMAGE_NAME:-talos-${TALOS_VERSION}-genestack}"
    if openstack image show "${TALOS_IMAGE_NAME}" 2>/dev/null; then
        openstack image delete "${TALOS_IMAGE_NAME}"
        echo "Talos image '${TALOS_IMAGE_NAME}' deleted"
    else
        echo "Talos image '${TALOS_IMAGE_NAME}' not found"
    fi
fi

#############################################################################
# Cleanup Complete
#############################################################################

echo "Cleanup complete"
echo "The Talos lab uninstall took ${SECONDS} seconds to complete."
echo ""
echo "Note: Local SSH key files (~/.ssh/${LAB_NAME_PREFIX}-key.pem, ~/.ssh/${LAB_NAME_PREFIX}-key.pub)"
echo "were NOT removed. Delete them manually if no longer needed."
