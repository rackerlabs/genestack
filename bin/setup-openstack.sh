#!/usr/bin/env bash
set -e

# Track the PIDs of the services deploying in parallel
declare -A pids
declare -A pid_commands

function runTrackErator() {
    "${1}" &
    local pid=$!
    pids[$pid]=1
    pid_commands[$pid]="${1}"
    echo "Started ${1} with PID ${pid}"
}

function waitErator() {
    local start_time
    start_time=$(date +%s)
    local timeout_seconds=$((30 * 60))  # 30 minutes
    
    while [ ${#pids[@]} -gt 0 ]; do
        # Check for timeout
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -ge $timeout_seconds ]; then
            echo "==== PROCESS TIMEOUT ====================================="
            echo "Timeout after 30 minutes. Remaining processes:"
            for pid in "${!pids[@]}"; do
                echo "  PID ${pid}: ${pid_commands[$pid]}"
                kill ${pid} 2>/dev/null || true
            done
            echo "==== PROCESS TIMEOUT ====================================="
            exit 1
        fi
        
        for pid in "${!pids[@]}"; do
            # Check if process is still running
            if ! kill -0 ${pid} 2>/dev/null; then
                # Process finished, check exit status
                # Use || to prevent set -e from killing the script before we can log the failure
                wait ${pid} || local exit_code=$?
                exit_code=${exit_code:-0}
                
                if [ $exit_code -ne 0 ]; then
                    echo "==== PROCESS FAILED ====================================="
                    echo "Command: ${pid_commands[$pid]}"
                    echo "PID: ${pid}"
                    echo "Exit Code: ${exit_code}"
                    echo "==== PROCESS FAILED ====================================="
                    exit 1
                else
                    echo "Successfully completed ${pid_commands[$pid]} (PID ${pid})"
                fi
                unset "pids[$pid]"
            fi
        done
        sleep 1
    done
    
    echo "All processes completed successfully."
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
    prompt_component "manila" "Manila (Shared Filesystem)"
    prompt_component "ceilometer" "Ceilometer (Telemetry)"
    prompt_component "gnocchi" "Gnocchi (Time Series Database)"
    prompt_component "cloudkitty" "Cloudkitty (Rating and Chargeback)"
    prompt_component "skyline" "Skyline (Dashboard)"
    prompt_component "freezer" "Freezer (Backup Restore)"
    prompt_component "zaqar" "Zaqar (Messaging)"
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
is_component_enabled "manila" && runTrackErator /opt/genestack/bin/install-manila.sh
is_component_enabled "ceilometer" && runTrackErator /opt/genestack/bin/install-ceilometer.sh
is_component_enabled "gnocchi" && runTrackErator /opt/genestack/bin/install-gnocchi.sh
is_component_enabled "cloudkitty" && runTrackErator /opt/genestack/bin/install-cloudkitty.sh
is_component_enabled "freezer" && runTrackErator /opt/genestack/bin/install-freezer.sh
is_component_enabled "zaqar" && runTrackErator /opt/genestack/bin/install-zaqar.sh

waitErator

# Install skyline after all services are up
is_component_enabled "skyline" && /opt/genestack/bin/install-skyline.sh
