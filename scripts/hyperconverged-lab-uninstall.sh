#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Uninstall Selector
#
# This script provides a simple interface to uninstall Genestack hyperconverged
# lab deployments for either platform:
#
#   1. Kubespray
#   2. Talos Linux
#
# Usage:
#   ./hyperconverged-lab-uninstall.sh                  # Interactive mode
#   ./hyperconverged-lab-uninstall.sh kubespray        # Uninstall Kubespray lab
#   ./hyperconverged-lab-uninstall.sh talos            # Uninstall Talos lab
#

set -o pipefail
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

function show_usage() {
    cat <<EOF
Hyperconverged Lab Uninstall Script

This script removes all resources created by the hyperconverged lab deployment scripts.

USAGE:
    $(basename "$0") [PLATFORM]

PLATFORMS:
    kubespray    Uninstall Kubespray lab deployment
    talos        Uninstall Talos Linux lab deployment
    help         Show this help message

ENVIRONMENT VARIABLES:
    OS_CLOUD         OpenStack cloud configuration name (will prompt if not set)
    LAB_NAME_PREFIX  Prefix used during deployment (default: hyperconverged or talos-hyperconverged)

EXAMPLES:
    # Interactive mode - will prompt for platform choice
    $(basename "$0")

    # Uninstall Kubespray deployment
    $(basename "$0") kubespray

    # Uninstall Talos deployment
    $(basename "$0") talos

    # Uninstall with custom prefix
    LAB_NAME_PREFIX=my-lab $(basename "$0") kubespray

For more information, see the Genestack documentation.
EOF
}

function prompt_for_platform() {
    echo ""
    echo "Hyperconverged Lab Uninstall"
    echo "============================"
    echo ""
    echo "Select which deployment to uninstall:"
    echo ""
    echo "  1) Kubespray   - LAB_NAME_PREFIX default: hyperconverged"
    echo "  2) Talos Linux - LAB_NAME_PREFIX default: talos-hyperconverged"
    echo ""

    read -rp "Enter your choice [1/2]: " choice

    case "$choice" in
        1|kubespray|Kubespray|KUBESPRAY)
            echo ""
            echo "Selected: Kubespray"
            PLATFORM="kubespray"
            ;;
        2|talos|Talos|TALOS)
            echo ""
            echo "Selected: Talos Linux"
            PLATFORM="talos"
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            exit 1
            ;;
    esac
}

# Check for help flag first
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Determine platform from first argument or prompt
if [[ -n "$1" && "$1" != -* ]]; then
    case "$1" in
        kubespray|Kubespray|KUBESPRAY)
            PLATFORM="kubespray"
            shift
            ;;
        talos|Talos|TALOS)
            PLATFORM="talos"
            shift
            ;;
        *)
            echo "Unknown platform: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
else
    prompt_for_platform
fi

# Execute the appropriate platform-specific uninstall script
case "$PLATFORM" in
    kubespray)
        echo ""
        echo "Launching Kubespray uninstall..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-kubespray-uninstall.sh" "$@"
        ;;
    talos)
        echo ""
        echo "Launching Talos Linux uninstall..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-talos-uninstall.sh" "$@"
        ;;
esac
