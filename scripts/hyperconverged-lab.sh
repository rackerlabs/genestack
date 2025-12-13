#!/usr/bin/env bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086,SC2087,SC2155
#
# Hyperconverged Lab Deployment Selector
#
# This script provides a simple interface to deploy Genestack (OpenStack on Kubernetes)
# in a hyperconverged configuration using either:
#
#   1. Kubespray   - Traditional approach using Ubuntu VMs and Kubespray/Ansible
#   2. Talos Linux - Modern approach using Talos Linux immutable OS
#
# Usage:
#   ./hyperconverged-lab.sh                    # Interactive mode - prompts for platform
#   ./hyperconverged-lab.sh kubespray [args]   # Deploy using Kubespray
#   ./hyperconverged-lab.sh talos [args]       # Deploy using Talos Linux
#
# For uninstall, use the corresponding uninstall scripts:
#   ./hyperconverged-lab-kubespray-uninstall.sh
#   ./hyperconverged-lab-talos-uninstall.sh
#

set -o pipefail
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

function show_usage() {
    cat <<EOF
Hyperconverged Lab Deployment Script

This script deploys Genestack (OpenStack on Kubernetes) in a hyperconverged
configuration on OpenStack infrastructure.

USAGE:
    $(basename "$0") [PLATFORM] [OPTIONS]

PLATFORMS:
    kubespray    Deploy using Kubespray on Ubuntu (traditional approach)
                 - Uses Ubuntu VMs with SSH access
                 - Kubernetes deployed via Kubespray/Ansible
                 - Requires SSH keypair for node access

    talos        Deploy using Talos Linux (modern approach)
                 - Uses Talos Linux immutable OS
                 - Kubernetes deployed via talosctl
                 - No SSH - managed via Talos API
                 - Includes Talos-specific configs for Longhorn, Kube-OVN, Ceph

    help         Show this help message

OPTIONS:
    -i <list>    Comma-separated list of OpenStack services to include
    -e <list>    Comma-separated list of OpenStack services to exclude
    -x           Run extra operations (k9s install, Octavia preconf, etc.)

ENVIRONMENT VARIABLES:
    ACME_EMAIL          Email for ACME/Let's Encrypt certificates
    GATEWAY_DOMAIN      Domain name for the gateway (default: cluster.local)
    OS_CLOUD            OpenStack cloud configuration name (default: default)
    OS_FLAVOR           Flavor to use for instances
    OS_IMAGE            Image to use (platform-specific defaults apply)
    LAB_NAME_PREFIX     Prefix for all created resources
    LAB_NETWORK_MTU     MTU for lab networks (default: 1500)
    HYPERCONVERGED_DEV  If set to "true", enables development mode which transports
                        the local environment checkout into the hyperconverged lab
                        for easier testing and debugging.

EXAMPLES:
    # Interactive mode - will prompt for platform choice
    $(basename "$0")

    # Deploy using Kubespray
    $(basename "$0") kubespray

    # Deploy using Talos Linux
    $(basename "$0") talos

    # Deploy Kubespray with extra services and extras enabled
    $(basename "$0") kubespray -i heat,octavia -x

    # Deploy Talos with specific services excluded
    $(basename "$0") talos -e skyline

UNINSTALL:
    Use the platform-specific uninstall scripts:

    # Uninstall Kubespray deployment
    ./hyperconverged-lab-kubespray-uninstall.sh

    # Uninstall Talos deployment
    ./hyperconverged-lab-talos-uninstall.sh

For more information, see the Genestack documentation.
EOF
}

function prompt_for_platform() {
    echo ""
    echo "Hyperconverged Lab Deployment"
    echo "============================="
    echo ""
    echo "Select your deployment platform:"
    echo ""
    echo "  1) Kubespray"
    echo "     - Traditional approach using Ubuntu VMs"
    echo "     - Kubernetes deployed via Kubespray/Ansible"
    echo "     - SSH-based node management"
    echo ""
    echo "  2) Talos Linux"
    echo "     - Modern immutable Linux OS designed for Kubernetes"
    echo "     - API-based management (no SSH)"
    echo "     - Includes Talos-specific configurations for Longhorn, Kube-OVN, Ceph"
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

# Execute the appropriate platform-specific script
case "$PLATFORM" in
    kubespray)
        echo ""
        echo "Launching Kubespray deployment..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-kubespray.sh" "$@"
        ;;
    talos)
        echo ""
        echo "Launching Talos Linux deployment..."
        echo ""
        exec "${SCRIPT_DIR}/hyperconverged-lab-talos.sh" "$@"
        ;;
esac
