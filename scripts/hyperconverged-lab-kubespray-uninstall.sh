#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Uninstall Script for Kubespray
#
# This script removes all resources created by the Kubespray hyperconverged lab script.
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

export LAB_NAME_PREFIX="${LAB_NAME_PREFIX:-hyperconverged}"

#############################################################################
# Run Common Uninstall
#############################################################################

runCommonUninstall "${LAB_NAME_PREFIX}"

#############################################################################
# Kubespray-Specific: Delete SSH Keypair and Security Group
#############################################################################

echo "Deleting Kubespray-specific resources..."
keypairDelete ${LAB_NAME_PREFIX}-key
securityGroupDelete ${LAB_NAME_PREFIX}-jump-secgroup

#############################################################################
# Cleanup Complete
#############################################################################

echo "Cleanup complete"
echo "The Kubespray lab uninstall took ${SECONDS} seconds to complete."
echo ""
echo "Note: Local SSH key files (~/.ssh/${LAB_NAME_PREFIX}-key.pem, ~/.ssh/${LAB_NAME_PREFIX}-key.pub)"
echo "were NOT removed. Delete them manually if no longer needed."
