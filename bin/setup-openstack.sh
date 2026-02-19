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
    prompt_component "glance" "Glance (Image Service)"
    prompt_component "heat" "Heat (Orchestration)"
    prompt_component "barbican" "Barbican (Key Manager)"
    prompt_component "blazar" "Blazar (Reservation)"
    prompt_component "cinder" "Cinder (Block Storage)"
    prompt_component "designate" "Designate (DNS)"
    prompt_component "trove" "Trove (Databases)"
    prompt_component "placement" "Placement"
    prompt_component "nova" "Nova (Compute)"
    prompt_component "neutron" "Neutron (Networking)"
    prompt_component "magnum" "Magnum (Container Orchestration)"
    prompt_component "octavia" "Octavia (Load Balancer)"
    prompt_component "masakari" "Masakari (Instance High Availability)"
    prompt_component "manila" "Manila (Shared Filesystem)"
    prompt_component "ceilometer" "Ceilometer (Telemetry)"
    prompt_component "gnocchi" "Gnocchi (Time Series Database)"
    prompt_component "cloudkitty" "Cloudkitty (Rating and Chargeback)"
    prompt_component "skyline" "Skyline (Dashboard)"
    prompt_component "freezer" "Freezer (Backup Restore)"
    prompt_component "zaqar" "Zaqar (Messaging)"
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

# Run selected services in parallel
is_component_enabled "glance" && runTrackErator /opt/genestack/bin/install-glance.sh
is_component_enabled "heat" && runTrackErator /opt/genestack/bin/install-heat.sh
is_component_enabled "barbican" && runTrackErator /opt/genestack/bin/install-barbican.sh
is_component_enabled "blazar" && runTrackErator /opt/genestack/bin/install-blazar.sh
is_component_enabled "cinder" && runTrackErator /opt/genestack/bin/install-cinder.sh
is_component_enabled "designate" && runTrackErator /opt/genestack/bin/install-designate.sh
is_component_enabled "trove" && runTrackErator /opt/genestack/bin/install-trove.sh
is_component_enabled "placement" && runTrackErator /opt/genestack/bin/install-placement.sh
is_component_enabled "nova" && runTrackErator /opt/genestack/bin/install-nova.sh
is_component_enabled "neutron" && runTrackErator /opt/genestack/bin/install-neutron.sh
is_component_enabled "magnum" && runTrackErator /opt/genestack/bin/install-magnum.sh
is_component_enabled "octavia" && runTrackErator /opt/genestack/bin/install-octavia.sh
is_component_enabled "masakari" && runTrackErator /opt/genestack/bin/install-masakari.sh
is_component_enabled "manila" && runTrackErator /opt/genestack/bin/install-manila.sh
is_component_enabled "ceilometer" && runTrackErator /opt/genestack/bin/install-ceilometer.sh
is_component_enabled "gnocchi" && runTrackErator /opt/genestack/bin/install-gnocchi.sh
is_component_enabled "cloudkitty" && runTrackErator /opt/genestack/bin/install-cloudkitty.sh
is_component_enabled "freezer" && runTrackErator /opt/genestack/bin/install-freezer.sh
is_component_enabled "zaqar" && runTrackErator /opt/genestack/bin/install-zaqar.sh

# --- PHASE 4: DASHBOARD ---
# Skyline is usually installed last once APIs are responsive.
is_enabled "skyline" && /opt/genestack/bin/install-skyline.sh $ROTATE_FLAG

echo "==== OpenStack Deployment Complete ===="
