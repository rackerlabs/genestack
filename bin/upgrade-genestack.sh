#!/bin/bash
# Comprehensive Genestack Upgrade Script
#
# This script compares installed chart versions against desired versions
# and performs upgrades as needed.
#
# Usage:
#   upgrade-genestack.sh                    # Dry-run mode (shows what would be upgraded)
#   upgrade-genestack.sh --upgrade          # Perform actual upgrades
#   upgrade-genestack.sh --upgrade --rotate-secrets  # Upgrade with secret rotation
#   upgrade-genestack.sh --component <name> # Dry-run for specific component
#   upgrade-genestack.sh --upgrade --component <name> # Upgrade specific component

set -eo pipefail

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
DRY_RUN=true
ROTATE_SECRETS=false
SPECIFIC_COMPONENT=""
FAILED_UPGRADES=()
SUCCESSFUL_UPGRADES=()
SKIPPED_UPGRADES=()

# Import common functions
LIB_PATH="${GENESTACK_BASE_DIR}/scripts/common-functions.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: Shared library not found at $LIB_PATH" >&2
    exit 1
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --upgrade) DRY_RUN=false; shift ;;
        --rotate-secrets) ROTATE_SECRETS=true; shift ;;
        --component) SPECIFIC_COMPONENT="$2"; shift 2 ;;
        -h|--help)
            cat << 'EOF'
Genestack Upgrade Script

Usage:
  upgrade-genestack.sh [OPTIONS]

Options:
  --upgrade              Perform actual upgrades (default: dry-run)
  --rotate-secrets       Rotate secrets during upgrade
  --component <name>     Upgrade only a specific component
  -h, --help            Show this help message

Examples:
  # Dry-run to see what would be upgraded
  upgrade-genestack.sh

  # Perform all upgrades
  upgrade-genestack.sh --upgrade

  # Upgrade specific component
  upgrade-genestack.sh --upgrade --component keystone

  # Upgrade with secret rotation
  upgrade-genestack.sh --upgrade --rotate-secrets
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to get installed chart version from Helm
get_installed_version() {
    local release_name=$1
    local namespace=$2

    helm list -n "$namespace" -o json 2>/dev/null | \
        jq -r ".[] | select(.name==\"$release_name\") | .chart" | \
        sed 's/.*-//' || echo ""
}

# Function to get desired version from config file
get_desired_version() {
    local service_name=$1
    local version_file="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

    if [[ ! -f "$version_file" ]]; then
        echo ""
        return 1
    fi

    grep "^[[:space:]]*${service_name}:" "$version_file" 2>/dev/null | \
        sed "s/.*${service_name}: *//" || echo ""
}

# Function to check if service is installed
is_service_installed() {
    local release_name=$1
    local namespace=$2

    helm list -n "$namespace" 2>/dev/null | grep -q "^${release_name}[[:space:]]"
}

# Function to compare versions
versions_differ() {
    local installed=$1
    local desired=$2

    [[ "$installed" != "$desired" ]]
}

# Function to map service name to install script
get_install_script() {
    local service_name=$1
    echo "${SCRIPT_DIR}/install-${service_name}.sh"
}

# Function to map service name to namespace
get_service_namespace() {
    local service_name=$1

    # Most OpenStack services are in openstack namespace
    case "$service_name" in
        kube-ovn|kube-prometheus-stack|kubernetes-event-exporter|metallb|cert-manager|sealed-secrets|topolvm)
            echo "kube-system"
            ;;
        longhorn)
            echo "longhorn-system"
            ;;
        loki)
            echo "loki"
            ;;
        mariadb-operator)
            echo "mariadb-system"
            ;;
        postgres-operator)
            echo "postgres-operator"
            ;;
        redis-operator)
            echo "redis-system"
            ;;
        prometheus-*|grafana)
            echo "prometheus"
            ;;
        fluentbit)
            echo "fluent-bit"
            ;;
        envoy-gateway)
            echo "envoy-gateway-system"
            ;;
        libvirt)
            echo "libvirt"
            ;;
        *)
            echo "openstack"
            ;;
    esac
}

# Function to map service name to release name
get_release_name() {
    local service_name=$1

    # Most services use the same name, but some differ
    case "$service_name" in
        fluent-bit)
            echo "fluentbit"
            ;;
        *)
            echo "$service_name"
            ;;
    esac
}

# Function to perform upgrade check
check_upgrade_needed() {
    local service_name=$1
    local release_name=$(get_release_name "$service_name")
    local namespace=$(get_service_namespace "$service_name")
    local install_script=$(get_install_script "$service_name")

    # Skip if install script doesn't exist
    if [[ ! -f "$install_script" ]]; then
        return 1
    fi

    # Get versions
    local desired_version=$(get_desired_version "$service_name")
    if [[ -z "$desired_version" ]]; then
        return 1
    fi

    # Check if installed
    if ! is_service_installed "$release_name" "$namespace"; then
        print_status "$YELLOW" "  [NOT INSTALLED] $service_name (desired: $desired_version)"
        return 1
    fi

    local installed_version=$(get_installed_version "$release_name" "$namespace")

    if versions_differ "$installed_version" "$desired_version"; then
        print_status "$BLUE" "  [UPGRADE NEEDED] $service_name: $installed_version -> $desired_version"
        return 0
    else
        print_status "$GREEN" "  [UP TO DATE] $service_name: $installed_version"
        return 1
    fi
}

# Function to perform upgrade
perform_upgrade() {
    local service_name=$1
    local install_script=$(get_install_script "$service_name")

    if [[ ! -f "$install_script" || ! -x "$install_script" ]]; then
        print_status "$RED" "  [ERROR] Install script not found or not executable: $install_script"
        FAILED_UPGRADES+=("$service_name (script not found)")
        return 1
    fi

    print_status "$BLUE" "  [UPGRADING] $service_name..."

    local upgrade_args=()
    if [[ "$ROTATE_SECRETS" == "true" ]]; then
        upgrade_args+=("--rotate-secrets")
    fi

    if "$install_script" "${upgrade_args[@]}"; then
        print_status "$GREEN" "  [SUCCESS] $service_name upgraded successfully"
        SUCCESSFUL_UPGRADES+=("$service_name")
        return 0
    else
        print_status "$RED" "  [FAILED] $service_name upgrade failed"
        FAILED_UPGRADES+=("$service_name")
        return 1
    fi
}

# Main execution
main() {
    print_status "$BLUE" "=========================================="
    print_status "$BLUE" "Genestack Upgrade Script"
    print_status "$BLUE" "=========================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "$YELLOW" "MODE: DRY-RUN (use --upgrade to perform actual upgrades)"
    else
        print_status "$GREEN" "MODE: UPGRADE"
        if [[ "$ROTATE_SECRETS" == "true" ]]; then
            print_status "$YELLOW" "  Secrets will be rotated during upgrade"
        fi
    fi
    echo ""

    # Pre-flight checks
    print_status "$BLUE" "Performing pre-flight checks..."
    check_dependencies "kubectl" "helm" "jq" "grep" "sed"
    check_cluster_connection
    print_status "$GREEN" "Pre-flight checks passed"
    echo ""

    # Get list of services to check
    local services_to_check=()

    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        services_to_check=("$SPECIFIC_COMPONENT")
        print_status "$BLUE" "Checking specific component: $SPECIFIC_COMPONENT"
    else
        # Read all services from helm-chart-versions.yaml
        local version_file="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"
        if [[ ! -f "$version_file" ]]; then
            print_status "$RED" "Error: Version file not found: $version_file"
            exit 1
        fi

        mapfile -t services_to_check < <(grep -v '^#' "$version_file" | grep ':' | sed 's/:.*//' | sed 's/^[[:space:]]*//')
        print_status "$BLUE" "Checking all components from: $version_file"
    fi

    echo ""
    print_status "$BLUE" "Checking versions..."
    echo ""

    # Check each service
    local upgrades_needed=()
    for service in "${services_to_check[@]}"; do
        if check_upgrade_needed "$service"; then
            upgrades_needed+=("$service")
        fi
    done

    echo ""

    # Summary of dry-run
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ ${#upgrades_needed[@]} -eq 0 ]]; then
            print_status "$GREEN" "No upgrades needed. All components are up to date."
        else
            print_status "$YELLOW" "=========================================="
            print_status "$YELLOW" "Upgrades needed: ${#upgrades_needed[@]}"
            print_status "$YELLOW" "=========================================="
            for service in "${upgrades_needed[@]}"; do
                echo "  - $service"
            done
            echo ""
            print_status "$BLUE" "To perform these upgrades, run:"
            print_status "$BLUE" "  $0 --upgrade"
        fi
        exit 0
    fi

    # Perform upgrades
    if [[ ${#upgrades_needed[@]} -eq 0 ]]; then
        print_status "$GREEN" "No upgrades needed. All components are up to date."
        exit 0
    fi

    print_status "$BLUE" "=========================================="
    print_status "$BLUE" "Starting upgrades..."
    print_status "$BLUE" "=========================================="
    echo ""

    for service in "${upgrades_needed[@]}"; do
        perform_upgrade "$service"
        echo ""
    done

    # Final summary
    print_status "$BLUE" "=========================================="
    print_status "$BLUE" "Upgrade Summary"
    print_status "$BLUE" "=========================================="
    echo ""

    if [[ ${#SUCCESSFUL_UPGRADES[@]} -gt 0 ]]; then
        print_status "$GREEN" "Successful upgrades (${#SUCCESSFUL_UPGRADES[@]}):"
        for service in "${SUCCESSFUL_UPGRADES[@]}"; do
            echo "  - $service"
        done
        echo ""
    fi

    if [[ ${#FAILED_UPGRADES[@]} -gt 0 ]]; then
        print_status "$RED" "Failed upgrades (${#FAILED_UPGRADES[@]}):"
        for service in "${FAILED_UPGRADES[@]}"; do
            echo "  - $service"
        done
        echo ""
        exit 1
    fi

    print_status "$GREEN" "All upgrades completed successfully!"
}

# Run main function
main
