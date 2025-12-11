#!/bin/bash
# OpenStack Service Health Tests for Genestack
# Validates individual OpenStack service health using OpenStack CLI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/openstack.sh"

# Source OpenStack credentials
if ! source_credentials; then
    echo "ERROR: Failed to source OpenStack credentials"
    exit 1
fi

# Test: Can obtain Keystone authentication token
test_keystone_token() {
    check_openstack_cli || return 1

    local token=$(get_token 2>&1)
    local result=$?

    if [ ${result} -ne 0 ]; then
        echo "Failed to obtain authentication token"
        echo "${token}"
        return 1
    fi

    echo "Successfully obtained authentication token"
    return 0
}

# Test: Glance API is responding
test_glance_api() {
    check_openstack_cli || return 1

    if ! is_service_available glance; then
        echo "Glance service is not available in service catalog"
        return 1
    fi

    if ! list_images >/dev/null 2>&1; then
        echo "Glance API is not responding"
        return 1
    fi

    local image_count=$(list_images 2>/dev/null | wc -l)
    echo "Glance API is healthy (${image_count} images)"
    return 0
}

# Test: Nova compute services are up
test_nova_services() {
    check_openstack_cli || return 1

    if ! is_service_available nova; then
        echo "Nova service is not available in service catalog"
        return 1
    fi

    local services_output=$(list_compute_services 2>&1)
    local result=$?

    if [ ${result} -ne 0 ]; then
        echo "Failed to list compute services"
        echo "${services_output}"
        return 1
    fi

    local total_services=$(echo "${services_output}" | wc -l)
    local down_services=$(echo "${services_output}" | awk '{print $4}' | grep -c "down" || echo "0")

    if [ "${down_services}" -gt 0 ]; then
        echo "Found ${down_services} compute services that are down"
        echo "${services_output}"
        return 1
    fi

    echo "All Nova compute services are up (${total_services} services)"
    return 0
}

# Test: Neutron network agents are alive
test_neutron_agents() {
    check_openstack_cli || return 1

    if ! is_service_available neutron; then
        echo "Neutron service is not available in service catalog"
        return 1
    fi

    local agents_output=$(list_network_agents 2>&1)
    local result=$?

    if [ ${result} -ne 0 ]; then
        echo "Failed to list network agents"
        echo "${agents_output}"
        return 1
    fi

    local total_agents=$(echo "${agents_output}" | wc -l)
    local dead_agents=$(echo "${agents_output}" | awk '{print $5}' | grep -ci "false" || echo "0")

    if [ "${dead_agents}" -gt 0 ]; then
        echo "Found ${dead_agents} network agents that are not alive"
        echo "${agents_output}"
        return 1
    fi

    echo "All Neutron agents are alive (${total_agents} agents)"
    return 0
}

# Test: Cinder volume services are up (skip if not available)
test_cinder_services() {
    check_openstack_cli || return 1

    if ! is_service_available cinderv3; then
        echo "Cinder service is not available, skipping test"
        return 0
    fi

    local services_output=$(list_volume_services 2>&1)
    local result=$?

    if [ ${result} -ne 0 ]; then
        echo "Failed to list volume services"
        echo "${services_output}"
        return 1
    fi

    local total_services=$(echo "${services_output}" | wc -l)

    if [ "${total_services}" -eq 0 ]; then
        echo "No Cinder services found (may not be configured)"
        return 0
    fi

    local down_services=$(echo "${services_output}" | awk '{print $3}' | grep -c "down" || echo "0")

    if [ "${down_services}" -gt 0 ]; then
        echo "Found ${down_services} volume services that are down"
        echo "${services_output}"
        return 1
    fi

    echo "All Cinder volume services are up (${total_services} services)"
    return 0
}

# Test: Placement resource providers exist
test_placement_resources() {
    check_openstack_cli || return 1

    if ! is_service_available placement; then
        echo "Placement service is not available in service catalog"
        return 1
    fi

    local providers_output=$(list_resource_providers 2>&1)
    local result=$?

    if [ ${result} -ne 0 ]; then
        echo "Failed to list resource providers"
        echo "${providers_output}"
        return 1
    fi

    local provider_count=$(echo "${providers_output}" | wc -l)

    if [ "${provider_count}" -eq 0 ]; then
        echo "No resource providers found in Placement"
        return 1
    fi

    echo "Placement service is healthy (${provider_count} resource providers)"
    return 0
}

# Main test execution
main() {
    TEST_SUITE_NAME="openstack-service-tests"
    init_tests "${TEST_SUITE_NAME}"

    echo ""
    echo "Running OpenStack Service Health Tests..."
    echo ""

    run_test "keystone_token" test_keystone_token
    run_test "glance_api" test_glance_api
    run_test "nova_services" test_nova_services
    run_test "neutron_agents" test_neutron_agents
    run_test "cinder_services" test_cinder_services
    run_test "placement_resources" test_placement_resources

    finalize_tests
}

# Run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
    exit $?
fi
