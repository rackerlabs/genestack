#!/bin/bash
# Create core infrastructure secrets that multiple services depend on
#
# This script creates the minimal set of shared infrastructure secrets
# that must exist before deploying OpenStack services:
#   - mariadb root password
#   - rabbitmq admin password
#   - memcached secret key
#
# All other service-specific secrets are created by the individual
# install scripts using get_or_create_secret().

set -eo pipefail

# Base directories
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Import common functions
LIB_PATH="${GENESTACK_BASE_DIR}/scripts/common-functions.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: Shared library not found at $LIB_PATH" >&2
    exit 1
fi

# Parse arguments
ROTATE_SECRETS=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rotate-secrets) ROTATE_SECRETS=true; shift ;;
        -h|--help)
            cat << 'EOF'
Create Infrastructure Secrets

This script creates core shared infrastructure secrets for Genestack.

Usage:
  create-infrastructure-secrets.sh [OPTIONS]

Options:
  --rotate-secrets  Force rotation of all secrets
  -h, --help        Show this help message

Infrastructure Secrets Created:
  - mariadb (root-password)
  - rabbitmq-admin-password (password)
  - os-memcached (memcache_secret_key)

All service-specific secrets are created automatically by their
respective install scripts.
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

echo "=========================================="
echo "Creating Infrastructure Secrets"
echo "=========================================="
echo ""

if [[ "$ROTATE_SECRETS" == "true" ]]; then
    echo "WARNING: --rotate-secrets will regenerate all infrastructure secrets"
    echo "         This will require updating all services that use these secrets"
    echo ""
fi

# Pre-flight checks
perform_preflight_checks

NAMESPACE="openstack"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
fi

echo "Creating infrastructure secrets in namespace: $NAMESPACE"
echo ""

# MariaDB root password
echo "1. MariaDB root password..."
MARIADB_ROOT=$(get_or_create_secret "$NAMESPACE" "mariadb" "root-password" 32 "$ROTATE_SECRETS")
echo "   ✓ mariadb/root-password"

# RabbitMQ admin password
echo "2. RabbitMQ admin password..."
RABBITMQ_ADMIN=$(get_or_create_secret "$NAMESPACE" "rabbitmq-admin-password" "password" 32 "$ROTATE_SECRETS")
echo "   ✓ rabbitmq-admin-password/password"

# Memcached secret key
echo "3. Memcached secret key..."
MEMCACHED_KEY=$(get_or_create_secret "$NAMESPACE" "os-memcached" "memcache_secret_key" 32 "$ROTATE_SECRETS")
echo "   ✓ os-memcached/memcache_secret_key"

echo ""
echo "=========================================="
echo "Infrastructure Secrets Created"
echo "=========================================="
echo ""
echo "The following infrastructure secrets are now available:"
echo "  - mariadb/root-password"
echo "  - rabbitmq-admin-password/password"
echo "  - os-memcached/memcache_secret_key"
echo ""
echo "All service-specific secrets will be created automatically"
echo "by their respective install scripts when they are run."
echo ""
echo "You can now proceed with service installation:"
echo "  ./bin/install-keystone.sh"
echo "  ./bin/install-glance.sh"
echo "  etc."
