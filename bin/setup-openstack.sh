#!/usr/bin/env bash
set -e

# Import Orchestration Framework
LIB_PATH="/opt/genestack/scripts/common-functions.sh"
if [[ -f "$LIB_PATH" ]]; then
    source "$LIB_PATH"
else
    echo "Error: Shared library not found at $LIB_PATH" >&2
    exit 1
fi

# Parse global flags
ROTATE_FLAG=""
[[ "$*" == *"--rotate-secrets"* ]] && ROTATE_FLAG="--rotate-secret"

# Check for component config and create if it doesn't exist
CONFIG_FILE="${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found. Initializing..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
components:
  keystone: true
EOF
    # Optional: User could add logic here to prompt for components via a helper function
fi

# --- PHASE 1: KEYSTONE ---
# Everything depends on Keystone; it must be ready first.
echo "Deploying Keystone Identity Service..."
/opt/genestack/bin/install-keystone.sh $ROTATE_FLAG

# --- PHASE 2: PRE-SEED SHARED SECRETS ---
# We generate these now so the parallel processes don't race to create the same Kubernetes Secret.
echo "Pre-seeding infrastructure secrets..."
IS_ROTATE=$([[ -n "$ROTATE_FLAG" ]] && echo "true" || echo "false")

get_or_create_secret "openstack" "mariadb" "root-password" 32 "$IS_ROTATE"
get_or_create_secret "openstack" "rabbitmq-default-user" "password" 32 "false"
get_or_create_secret "openstack" "os-memcached" "memcache_secret_key" 64 "false"

# --- PHASE 3: PARALLEL BURST ---
echo "Starting parallel deployment of enabled services..."

is_enabled "glance"     && run_parallel "/opt/genestack/bin/install-glance.sh $ROTATE_FLAG"
is_enabled "heat"       && run_parallel "/opt/genestack/bin/install-heat.sh $ROTATE_FLAG"
is_enabled "barbican"   && run_parallel "/opt/genestack/bin/install-barbican.sh $ROTATE_FLAG"
is_enabled "blazar"     && run_parallel "/opt/genestack/bin/install-blazar.sh $ROTATE_FLAG"
is_enabled "cinder"     && run_parallel "/opt/genestack/bin/install-cinder.sh $ROTATE_FLAG"
is_enabled "placement"  && run_parallel "/opt/genestack/bin/install-placement.sh $ROTATE_FLAG"
is_enabled "nova"       && run_parallel "/opt/genestack/bin/install-nova.sh $ROTATE_FLAG"
is_enabled "neutron"    && run_parallel "/opt/genestack/bin/install-neutron.sh $ROTATE_FLAG"
is_enabled "magnum"     && run_parallel "/opt/genestack/bin/install-magnum.sh $ROTATE_FLAG"
is_enabled "octavia"    && run_parallel "/opt/genestack/bin/install-octavia.sh $ROTATE_FLAG"
is_enabled "masakari"   && run_parallel "/opt/genestack/bin/install-masakari.sh $ROTATE_FLAG"
is_enabled "manila"     && run_parallel "/opt/genestack/bin/install-manila.sh $ROTATE_FLAG"
is_enabled "ceilometer" && run_parallel "/opt/genestack/bin/install-ceilometer.sh $ROTATE_FLAG"
is_enabled "gnocchi"    && run_parallel "/opt/genestack/bin/install-gnocchi.sh $ROTATE_FLAG"
is_enabled "cloudkitty" && run_parallel "/opt/genestack/bin/install-cloudkitty.sh $ROTATE_FLAG"
is_enabled "freezer"    && run_parallel "/opt/genestack/bin/install-freezer.sh $ROTATE_FLAG"
is_enabled "zaqar"      && run_parallel "/opt/genestack/bin/install-zaqar.sh $ROTATE_FLAG"

# Wait for Phase 3 to finish (defaulting to a 45-minute cluster timeout)
wait_parallel 45

# --- PHASE 4: DASHBOARD ---
# Skyline is usually installed last once APIs are responsive.
is_enabled "skyline" && /opt/genestack/bin/install-skyline.sh $ROTATE_FLAG

echo "==== OpenStack Deployment Complete ===="
