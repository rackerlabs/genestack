#!/usr/bin/env bash
set -e

# Track the PIDs of the services deploying in parallel
pids=()

function runTrackErator() {
    exec "${1}" &
    pids+=($!)
}

function waitErator() {
    for pid in ${pids[*]}; do
        if ! timeout --preserve-status --verbose 30m tail --pid=${pid} -f /dev/null; then
            echo "==== PROCESS TIMEOUT ====================================="
            cat /proc/${pid}/cmdline | xargs -0 echo
            echo "==== PROCESS TIMEOUT ====================================="
            echo "Timeout after 30 minutes waiting for process ${pid} to finish. Exiting."
            exit 1
        fi
    done
}

# Function to prompt user for component installation
prompt_component() {
    local component=$1
    local prompt=$2
    read -p "Install ${prompt}? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "  ${component}: true" >> /etc/genestack/openstack-components.yaml
    else
        echo "  ${component}: false" >> /etc/genestack/openstack-components.yaml
    fi
}

# Function to check if a component is set to true in the YAML file
is_component_enabled() {
    local component=$1
    grep -qi "^[[:space:]]*${component}:[[:space:]]*true" "$CONFIG_FILE"
}

# Check for YAML file and create if it doesn't exist
CONFIG_FILE="/etc/genestack/openstack-components.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found. Creating it..."
    cat > "$CONFIG_FILE" << EOF
components:
  keystone: true
EOF
    prompt_component "glance" "Glance (Image Service)"
    prompt_component "heat" "Heat (Orchestration)"
    prompt_component "barbican" "Barbican (Key Manager)"
    prompt_component "blazar" "Blazar (Reservation)"
    prompt_component "cinder" "Cinder (Block Storage)"
    prompt_component "placement" "Placement"
    prompt_component "nova" "Nova (Compute)"
    prompt_component "neutron" "Neutron (Networking)"
    prompt_component "magnum" "Magnum (Container Orchestration)"
    prompt_component "octavia" "Octavia (Load Balancer)"
    prompt_component "masakari" "Masakari (Instance High Availability)"
    prompt_component "ceilometer" "Ceilometer (Telemetry)"
    prompt_component "gnocchi" "Gnocchi (Time Series Database)"
    prompt_component "cloudkitty" "Cloudkitty (Rating and Chargeback)"
    prompt_component "skyline" "Skyline (Dashboard)"
    prompt_component "freezer" "Freezer (Backup Restore)"
fi

# Block on Keystone
/opt/genestack/bin/install-keystone.sh

# Run selected services in parallel
is_component_enabled "glance" && runTrackErator /opt/genestack/bin/install-glance.sh
is_component_enabled "heat" && runTrackErator /opt/genestack/bin/install-heat.sh
is_component_enabled "barbican" && runTrackErator /opt/genestack/bin/install-barbican.sh
is_component_enabled "blazar" && runTrackErator /opt/genestack/bin/install-blazar.sh
is_component_enabled "cinder" && runTrackErator /opt/genestack/bin/install-cinder.sh
is_component_enabled "placement" && runTrackErator /opt/genestack/bin/install-placement.sh
is_component_enabled "nova" && runTrackErator /opt/genestack/bin/install-nova.sh
is_component_enabled "neutron" && runTrackErator /opt/genestack/bin/install-neutron.sh
is_component_enabled "magnum" && runTrackErator /opt/genestack/bin/install-magnum.sh
is_component_enabled "octavia" && runTrackErator /opt/genestack/bin/install-octavia.sh
is_component_enabled "masakari" && runTrackErator /opt/genestack/bin/install-masakari.sh
is_component_enabled "ceilometer" && runTrackErator /opt/genestack/bin/install-ceilometer.sh
is_component_enabled "gnocchi" && runTrackErator /opt/genestack/bin/install-gnocchi.sh
is_component_enabled "cloudkitty" && runTrackErator /opt/genestack/bin/install-cloudkitty.sh
is_component_enabled "freezer" && runTrackErator /opt/genestack/bin/install-freezer.sh

waitErator

# Install skyline after all services are up
is_component_enabled "skyline" && /opt/genestack/bin/install-skyline.sh
