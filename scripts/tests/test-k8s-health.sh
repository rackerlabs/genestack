#!/bin/bash
# Kubernetes Health Tests for Genestack
# Validates Kubernetes cluster health and core components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/k8s.sh"

# Test: All Kubernetes nodes are in Ready state
test_all_nodes_ready() {
    check_kubectl || return 1

    local not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l)

    if [ "${not_ready}" -gt 0 ]; then
        echo "Found ${not_ready} nodes that are not Ready"
        kubectl get nodes
        return 1
    fi

    local ready_count=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    echo "All ${ready_count} nodes are Ready"
    return 0
}

# Test: CoreDNS deployment is available
test_coredns_running() {
    check_kubectl || return 1

    if ! kubectl -n kube-system get deployment coredns >/dev/null 2>&1; then
        echo "CoreDNS deployment not found in kube-system namespace"
        return 1
    fi

    if ! wait_for_deployment kube-system coredns 30; then
        echo "CoreDNS deployment is not available"
        kubectl -n kube-system get deployment coredns
        return 1
    fi

    echo "CoreDNS is running and available"
    return 0
}

# Test: Kube-OVN controller is healthy
test_kube_ovn_controller() {
    check_kubectl || return 1

    if ! kubectl -n kube-system get deployment kube-ovn-controller >/dev/null 2>&1; then
        echo "Kube-OVN controller deployment not found"
        return 1
    fi

    if ! wait_for_deployment kube-system kube-ovn-controller 30; then
        echo "Kube-OVN controller is not available"
        kubectl -n kube-system get deployment kube-ovn-controller
        return 1
    fi

    echo "Kube-OVN controller is healthy"
    return 0
}

# Test: Longhorn storage class exists
test_longhorn_storage() {
    check_kubectl || return 1

    if ! storage_class_exists general; then
        echo "Storage class 'general' not found"
        kubectl get storageclass
        return 1
    fi

    echo "Longhorn storage class 'general' is available"
    return 0
}

# Test: MetalLB speakers are running
test_metallb_speakers() {
    check_kubectl || return 1

    if ! kubectl -n metallb-system get daemonset metallb-speaker >/dev/null 2>&1; then
        echo "MetalLB speaker daemonset not found"
        return 1
    fi

    local speakers=$(kubectl -n metallb-system get daemonset metallb-speaker \
        -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

    if [ "${speakers}" -eq 0 ]; then
        echo "No MetalLB speakers are ready"
        kubectl -n metallb-system get daemonset metallb-speaker
        return 1
    fi

    echo "MetalLB has ${speakers} speaker(s) ready"
    return 0
}

# Test: Envoy Gateway is available
test_envoy_gateway() {
    check_kubectl || return 1

    # Check if envoy-gateway namespace exists
    if ! namespace_exists envoyproxy-gateway-system; then
        echo "Envoy Gateway namespace not found, skipping test"
        return 0
    fi

    if ! kubectl -n envoyproxy-gateway-system get deployment envoy-gateway >/dev/null 2>&1; then
        echo "Envoy Gateway deployment not found"
        return 1
    fi

    if ! wait_for_deployment envoyproxy-gateway-system envoy-gateway 30; then
        echo "Envoy Gateway is not available"
        kubectl -n envoyproxy-gateway-system get deployment envoy-gateway
        return 1
    fi

    echo "Envoy Gateway is available"
    return 0
}

# Main test execution
main() {
    TEST_SUITE_NAME="k8s-health-tests"
    init_tests "${TEST_SUITE_NAME}"

    echo ""
    echo "Running Kubernetes Health Tests..."
    echo ""

    run_test "all_nodes_ready" test_all_nodes_ready
    run_test "coredns_running" test_coredns_running
    run_test "kube_ovn_controller" test_kube_ovn_controller
    run_test "longhorn_storage" test_longhorn_storage
    run_test "metallb_speakers" test_metallb_speakers
    run_test "envoy_gateway" test_envoy_gateway

    finalize_tests
}

# Run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
    exit $?
fi
