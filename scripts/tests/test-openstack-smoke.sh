#!/bin/bash
# OpenStack End-to-End Smoke Tests for Genestack
# Validates complete OpenStack functionality through resource creation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/openstack.sh"

# Source OpenStack credentials
if ! source_credentials; then
    echo "ERROR: Failed to source OpenStack credentials"
    exit 1
fi

# Test resource naming
SMOKE_PREFIX="smoke-test-$(date +%s)"
CLEANUP_PERFORMED=false

# Cleanup function to remove all test resources
cleanup_resources() {
    if [ "${CLEANUP_PERFORMED}" = "true" ]; then
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "Cleaning up smoke test resources..."
    echo "=========================================="

    # Detach and delete volume first
    if os_cmd volume show "${SMOKE_PREFIX}-volume" >/dev/null 2>&1; then
        echo "Detaching volume from instance..."
        detach_volume_from_server "${SMOKE_PREFIX}-instance" "${SMOKE_PREFIX}-volume" || true
        sleep 5
        echo "Deleting volume..."
        delete_volume "${SMOKE_PREFIX}-volume" || true
    fi

    # Delete instance
    if os_cmd server show "${SMOKE_PREFIX}-instance" >/dev/null 2>&1; then
        echo "Deleting instance..."
        delete_server "${SMOKE_PREFIX}-instance" || true
    fi

    # Delete image
    if os_cmd image show "${SMOKE_PREFIX}-image" >/dev/null 2>&1; then
        echo "Deleting image..."
        delete_image "${SMOKE_PREFIX}-image" || true
    fi

    # Remove router from subnet
    if os_cmd router show "${SMOKE_PREFIX}-router" >/dev/null 2>&1; then
        echo "Removing subnet from router..."
        router_remove_subnet "${SMOKE_PREFIX}-router" "${SMOKE_PREFIX}-subnet" || true
        echo "Deleting router..."
        delete_router "${SMOKE_PREFIX}-router" || true
    fi

    # Delete subnet
    if os_cmd subnet show "${SMOKE_PREFIX}-subnet" >/dev/null 2>&1; then
        echo "Deleting subnet..."
        delete_subnet "${SMOKE_PREFIX}-subnet" || true
    fi

    # Delete network
    if os_cmd network show "${SMOKE_PREFIX}-network" >/dev/null 2>&1; then
        echo "Deleting network..."
        delete_network "${SMOKE_PREFIX}-network" || true
    fi

    echo "Cleanup completed"
    CLEANUP_PERFORMED=true
}

# Register cleanup trap
trap cleanup_resources EXIT

# Test: Create network
test_create_network() {
    echo "Creating network: ${SMOKE_PREFIX}-network"
    create_network "${SMOKE_PREFIX}-network" >/dev/null 2>&1
}

# Test: Create subnet
test_create_subnet() {
    echo "Creating subnet: ${SMOKE_PREFIX}-subnet"
    create_subnet "${SMOKE_PREFIX}-subnet" "${SMOKE_PREFIX}-network" "10.99.0.0/24" "1.1.1.1" >/dev/null 2>&1
}

# Test: Create router
test_create_router() {
    echo "Creating router: ${SMOKE_PREFIX}-router"
    create_router "${SMOKE_PREFIX}-router" >/dev/null 2>&1
}

# Test: Add subnet to router
test_router_add_subnet() {
    echo "Adding subnet to router"
    router_add_subnet "${SMOKE_PREFIX}-router" "${SMOKE_PREFIX}-subnet" >/dev/null 2>&1
}

# Test: Download and upload Cirros image
test_upload_image() {
    local cirros_url="http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
    local cirros_file="/tmp/cirros-${SMOKE_PREFIX}.img"

    echo "Downloading Cirros image..."
    if [ ! -f "${cirros_file}" ]; then
        if ! curl -sL --connect-timeout 30 --max-time 300 "${cirros_url}" -o "${cirros_file}"; then
            echo "Failed to download Cirros image"
            return 1
        fi
    fi

    echo "Uploading image to Glance: ${SMOKE_PREFIX}-image"
    create_image "${SMOKE_PREFIX}-image" "${cirros_file}" "qcow2" "bare" >/dev/null 2>&1

    # Wait for image to become active
    local max_wait=60
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local status=$(os_cmd image show "${SMOKE_PREFIX}-image" -f value -c status 2>/dev/null || echo "error")
        if [ "${status}" = "active" ]; then
            echo "Image is active"
            # Clean up local image file
            rm -f "${cirros_file}"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done

    echo "Timeout waiting for image to become active"
    return 1
}

# Test: Create flavor if it doesn't exist
test_ensure_flavor() {
    local flavor_name="smoke-test-flavor"

    if ! flavor_exists "${flavor_name}"; then
        echo "Creating flavor: ${flavor_name}"
        create_flavor "${flavor_name}" 512 1 1 >/dev/null 2>&1
    else
        echo "Flavor ${flavor_name} already exists"
    fi
}

# Test: Create instance
test_create_instance() {
    echo "Creating instance: ${SMOKE_PREFIX}-instance"
    create_server "${SMOKE_PREFIX}-instance" "${SMOKE_PREFIX}-image" "smoke-test-flavor" "${SMOKE_PREFIX}-network" >/dev/null 2>&1

    echo "Waiting for instance to become ACTIVE..."
    if ! wait_for_server_status "${SMOKE_PREFIX}-instance" "ACTIVE" 300; then
        echo "Instance did not become ACTIVE within timeout"
        os_cmd server show "${SMOKE_PREFIX}-instance" || true
        return 1
    fi

    local status=$(get_server_status "${SMOKE_PREFIX}-instance")
    echo "Instance is ${status}"
    return 0
}

# Test: Create volume
test_create_volume() {
    echo "Creating volume: ${SMOKE_PREFIX}-volume (1GB)"
    create_volume "${SMOKE_PREFIX}-volume" 1 >/dev/null 2>&1

    echo "Waiting for volume to become available..."
    if ! wait_for_volume_status "${SMOKE_PREFIX}-volume" "available" 120; then
        echo "Volume did not become available within timeout"
        os_cmd volume show "${SMOKE_PREFIX}-volume" || true
        return 1
    fi

    local status=$(get_volume_status "${SMOKE_PREFIX}-volume")
    echo "Volume is ${status}"
    return 0
}

# Test: Attach volume to instance
test_attach_volume() {
    echo "Attaching volume to instance..."
    attach_volume_to_server "${SMOKE_PREFIX}-instance" "${SMOKE_PREFIX}-volume" >/dev/null 2>&1

    # Wait a moment for attachment to complete
    sleep 5

    echo "Waiting for volume to be in-use..."
    if ! wait_for_volume_status "${SMOKE_PREFIX}-volume" "in-use" 60; then
        echo "Volume did not become in-use within timeout"
        os_cmd volume show "${SMOKE_PREFIX}-volume" || true
        return 1
    fi

    local status=$(get_volume_status "${SMOKE_PREFIX}-volume")
    echo "Volume is ${status}"
    return 0
}

# Main test execution
main() {
    TEST_SUITE_NAME="openstack-smoke-tests"
    init_tests "${TEST_SUITE_NAME}"

    echo ""
    echo "=========================================="
    echo "Running OpenStack End-to-End Smoke Tests"
    echo "=========================================="
    echo "Test prefix: ${SMOKE_PREFIX}"
    echo ""

    # Network infrastructure tests
    run_test "create_network" test_create_network
    run_test "create_subnet" test_create_subnet
    run_test "create_router" test_create_router
    run_test "router_add_subnet" test_router_add_subnet

    # Image and flavor setup
    run_test "upload_image" test_upload_image
    run_test "ensure_flavor" test_ensure_flavor

    # Compute tests
    run_test "create_instance" test_create_instance

    # Volume tests (if Cinder is available)
    if is_service_available cinderv3; then
        run_test "create_volume" test_create_volume
        run_test "attach_volume" test_attach_volume
    else
        skip_test "create_volume" "Cinder service not available"
        skip_test "attach_volume" "Cinder service not available"
    fi

    finalize_tests
}

# Run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
    exit_code=$?

    # Ensure cleanup runs
    cleanup_resources

    exit ${exit_code}
fi
