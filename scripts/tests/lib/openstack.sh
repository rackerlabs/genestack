#!/bin/bash
# OpenStack helper functions for Genestack testing
# Provides common OpenStack CLI operations and health checks

set -eo pipefail

# Source OpenStack credentials
source_credentials() {
    local rc_file="/opt/genestack/scripts/genestack.rc"

    if [ ! -f "${rc_file}" ]; then
        echo "ERROR: OpenStack credentials file not found: ${rc_file}"
        return 1
    fi

    source "${rc_file}"
}

# Check if openstack CLI is available
check_openstack_cli() {
    if ! command -v openstack >/dev/null 2>&1; then
        echo "ERROR: openstack command not found"
        return 1
    fi
}

# Execute OpenStack command with default cloud
# Arguments: OpenStack command and arguments
os_cmd() {
    openstack --os-cloud default "$@" 2>&1
}

# Check if OpenStack service is available
# Arguments:
#   $1 - Service name (e.g., keystone, nova, glance)
is_service_available() {
    local service="$1"

    os_cmd catalog show "${service}" >/dev/null 2>&1
}

# Get authentication token
get_token() {
    os_cmd token issue -f value -c id
}

# Check if token can be obtained
can_authenticate() {
    get_token >/dev/null 2>&1
}

# List compute services
list_compute_services() {
    os_cmd compute service list -f value
}

# Check if all compute services are up
are_compute_services_up() {
    local down_count=$(os_cmd compute service list -f value -c State | grep -c "down" || echo "0")
    [ "${down_count}" -eq 0 ]
}

# List network agents
list_network_agents() {
    os_cmd network agent list -f value
}

# Check if all network agents are alive
are_network_agents_alive() {
    local dead_count=$(os_cmd network agent list -f value -c Alive | grep -ci "false" || echo "0")
    [ "${dead_count}" -eq 0 ]
}

# List volume services
list_volume_services() {
    os_cmd volume service list -f value 2>/dev/null
}

# Check if all volume services are up
are_volume_services_up() {
    if ! is_service_available cinder; then
        echo "Cinder service not available, skipping"
        return 0
    fi

    local down_count=$(os_cmd volume service list -f value -c State 2>/dev/null | grep -c "down" || echo "0")
    [ "${down_count}" -eq 0 ]
}

# List resource providers (Placement)
list_resource_providers() {
    os_cmd resource provider list -f value
}

# Check if resource providers exist
resource_providers_exist() {
    local provider_count=$(os_cmd resource provider list -f value | wc -l)
    [ "${provider_count}" -gt 0 ]
}

# List images
list_images() {
    os_cmd image list -f value
}

# Check if image exists by name
# Arguments:
#   $1 - Image name
image_exists() {
    local image_name="$1"
    os_cmd image show "${image_name}" -f value -c id >/dev/null 2>&1
}

# Create image
# Arguments:
#   $1 - Image name
#   $2 - Image file path
#   $3 - Disk format (default: qcow2)
#   $4 - Container format (default: bare)
create_image() {
    local image_name="$1"
    local image_file="$2"
    local disk_format="${3:-qcow2}"
    local container_format="${4:-bare}"

    os_cmd image create "${image_name}" \
        --file "${image_file}" \
        --disk-format "${disk_format}" \
        --container-format "${container_format}" \
        --public
}

# Delete image
# Arguments:
#   $1 - Image name or ID
delete_image() {
    local image="$1"
    os_cmd image delete "${image}" 2>/dev/null || true
}

# List networks
list_networks() {
    os_cmd network list -f value
}

# Create network
# Arguments:
#   $1 - Network name
create_network() {
    local network_name="$1"
    os_cmd network create "${network_name}"
}

# Delete network
# Arguments:
#   $1 - Network name or ID
delete_network() {
    local network="$1"
    os_cmd network delete "${network}" 2>/dev/null || true
}

# Create subnet
# Arguments:
#   $1 - Subnet name
#   $2 - Network name or ID
#   $3 - CIDR
#   $4 - DNS nameserver (optional)
create_subnet() {
    local subnet_name="$1"
    local network="$2"
    local cidr="$3"
    local dns="${4:-8.8.8.8}"

    os_cmd subnet create "${subnet_name}" \
        --network "${network}" \
        --subnet-range "${cidr}" \
        --dns-nameserver "${dns}"
}

# Delete subnet
# Arguments:
#   $1 - Subnet name or ID
delete_subnet() {
    local subnet="$1"
    os_cmd subnet delete "${subnet}" 2>/dev/null || true
}

# Create router
# Arguments:
#   $1 - Router name
create_router() {
    local router_name="$1"
    os_cmd router create "${router_name}"
}

# Delete router
# Arguments:
#   $1 - Router name or ID
delete_router() {
    local router="$1"
    os_cmd router delete "${router}" 2>/dev/null || true
}

# Add subnet to router
# Arguments:
#   $1 - Router name or ID
#   $2 - Subnet name or ID
router_add_subnet() {
    local router="$1"
    local subnet="$2"
    os_cmd router add subnet "${router}" "${subnet}"
}

# Remove subnet from router
# Arguments:
#   $1 - Router name or ID
#   $2 - Subnet name or ID
router_remove_subnet() {
    local router="$1"
    local subnet="$2"
    os_cmd router remove subnet "${router}" "${subnet}" 2>/dev/null || true
}

# List flavors
list_flavors() {
    os_cmd flavor list -f value
}

# Check if flavor exists
# Arguments:
#   $1 - Flavor name or ID
flavor_exists() {
    local flavor="$1"
    os_cmd flavor show "${flavor}" -f value -c id >/dev/null 2>&1
}

# Create flavor
# Arguments:
#   $1 - Flavor name
#   $2 - RAM in MB
#   $3 - Disk in GB
#   $4 - VCPUs
create_flavor() {
    local flavor_name="$1"
    local ram="$2"
    local disk="$3"
    local vcpus="$4"

    os_cmd flavor create "${flavor_name}" \
        --ram "${ram}" \
        --disk "${disk}" \
        --vcpus "${vcpus}"
}

# Create server/instance
# Arguments:
#   $1 - Server name
#   $2 - Image name or ID
#   $3 - Flavor name or ID
#   $4 - Network name or ID
create_server() {
    local server_name="$1"
    local image="$2"
    local flavor="$3"
    local network="$4"

    os_cmd server create "${server_name}" \
        --image "${image}" \
        --flavor "${flavor}" \
        --network "${network}" \
        --wait
}

# Delete server
# Arguments:
#   $1 - Server name or ID
delete_server() {
    local server="$1"
    os_cmd server delete "${server}" --wait 2>/dev/null || true
}

# Get server status
# Arguments:
#   $1 - Server name or ID
get_server_status() {
    local server="$1"
    os_cmd server show "${server}" -f value -c status
}

# Wait for server to reach status
# Arguments:
#   $1 - Server name or ID
#   $2 - Expected status
#   $3 - Timeout in seconds (default: 300)
wait_for_server_status() {
    local server="$1"
    local expected_status="$2"
    local timeout="${3:-300}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local status=$(get_server_status "${server}" 2>/dev/null || echo "ERROR")

        if [ "${status}" = "${expected_status}" ]; then
            return 0
        fi

        if [ "${status}" = "ERROR" ]; then
            echo "Server entered ERROR state"
            return 1
        fi

        sleep 5
        ((elapsed+=5))
    done

    echo "Timeout waiting for server to reach status: ${expected_status}"
    return 1
}

# Create volume
# Arguments:
#   $1 - Volume name
#   $2 - Size in GB
create_volume() {
    local volume_name="$1"
    local size="$2"

    os_cmd volume create "${volume_name}" --size "${size}"
}

# Delete volume
# Arguments:
#   $1 - Volume name or ID
delete_volume() {
    local volume="$1"
    os_cmd volume delete "${volume}" --force 2>/dev/null || true
}

# Get volume status
# Arguments:
#   $1 - Volume name or ID
get_volume_status() {
    local volume="$1"
    os_cmd volume show "${volume}" -f value -c status
}

# Wait for volume to reach status
# Arguments:
#   $1 - Volume name or ID
#   $2 - Expected status
#   $3 - Timeout in seconds (default: 120)
wait_for_volume_status() {
    local volume="$1"
    local expected_status="$2"
    local timeout="${3:-120}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local status=$(get_volume_status "${volume}" 2>/dev/null || echo "error")

        if [ "${status}" = "${expected_status}" ]; then
            return 0
        fi

        sleep 5
        ((elapsed+=5))
    done

    echo "Timeout waiting for volume to reach status: ${expected_status}"
    return 1
}

# Attach volume to server
# Arguments:
#   $1 - Server name or ID
#   $2 - Volume name or ID
attach_volume_to_server() {
    local server="$1"
    local volume="$2"

    os_cmd server add volume "${server}" "${volume}"
}

# Detach volume from server
# Arguments:
#   $1 - Server name or ID
#   $2 - Volume name or ID
detach_volume_from_server() {
    local server="$1"
    local volume="$2"

    os_cmd server remove volume "${server}" "${volume}" 2>/dev/null || true
}
