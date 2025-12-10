#!/bin/bash
# OpenStack Infrastructure Tests for Genestack
# Validates OpenStack infrastructure components (MariaDB, RabbitMQ, Redis, etc.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/k8s.sh"

# Test: MariaDB Galera cluster is synced
test_mariadb_cluster() {
    check_kubectl || return 1

    # Check if MariaDB statefulset exists
    if ! kubectl -n openstack get statefulset mariadb-cluster-mariadb-galera >/dev/null 2>&1; then
        echo "MariaDB statefulset not found in openstack namespace"
        return 1
    fi

    # Get the number of ready replicas
    local ready_replicas=$(kubectl -n openstack get statefulset mariadb-cluster-mariadb-galera \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [ "${ready_replicas}" -lt 3 ]; then
        echo "MariaDB cluster does not have 3 ready replicas (found: ${ready_replicas})"
        kubectl -n openstack get statefulset mariadb-cluster-mariadb-galera
        return 1
    fi

    # Check cluster sync status from first pod
    local pod_name="mariadb-cluster-mariadb-galera-0"
    local cluster_size=$(kubectl -n openstack exec "${pod_name}" -c mariadb -- \
        mysql -uroot -p"$(kubectl -n openstack get secret mariadb-cluster-mariadb-galera -o jsonpath='{.data.mariadb-root-password}' | base64 -d)" \
        -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | grep wsrep_cluster_size | awk '{print $2}' || echo "0")

    if [ "${cluster_size}" != "3" ]; then
        echo "MariaDB Galera cluster size is ${cluster_size}, expected 3"
        return 1
    fi

    echo "MariaDB Galera cluster is healthy with ${ready_replicas} synced replicas"
    return 0
}

# Test: RabbitMQ cluster is healthy
test_rabbitmq_cluster() {
    check_kubectl || return 1

    # Check if RabbitMQ statefulset exists
    if ! kubectl -n openstack get statefulset rabbitmq-server >/dev/null 2>&1; then
        echo "RabbitMQ statefulset not found in openstack namespace"
        return 1
    fi

    # Get the first pod
    local pod_name="rabbitmq-server-0"

    # Check cluster status
    if ! kubectl -n openstack exec "${pod_name}" -- rabbitmqctl cluster_status 2>/dev/null | grep -q "running_nodes"; then
        echo "RabbitMQ cluster status check failed"
        return 1
    fi

    # Count running nodes
    local running_nodes=$(kubectl -n openstack exec "${pod_name}" -- \
        rabbitmqctl cluster_status 2>/dev/null | grep -A 10 "running_nodes" | grep -c "rabbit@" || echo "0")

    if [ "${running_nodes}" -eq 0 ]; then
        echo "No running RabbitMQ nodes found"
        return 1
    fi

    echo "RabbitMQ cluster is healthy with ${running_nodes} running node(s)"
    return 0
}

# Test: Memcached pods are running
test_memcached_running() {
    check_kubectl || return 1

    # Check if memcached pods exist
    local memcached_count=$(get_pod_count openstack "application=memcached" "Running")

    if [ "${memcached_count}" -eq 0 ]; then
        echo "No running Memcached pods found in openstack namespace"
        kubectl -n openstack get pods -l application=memcached
        return 1
    fi

    echo "Memcached is running with ${memcached_count} pod(s)"
    return 0
}

# Test: Redis Sentinel is responding
test_redis_sentinel() {
    check_kubectl || return 1

    # Check if Redis StatefulSet exists
    if ! kubectl -n openstack get statefulset redis-node >/dev/null 2>&1; then
        echo "Redis StatefulSet not found in openstack namespace"
        return 1
    fi

    # Get a Redis pod
    local redis_pod=$(get_first_pod_by_label openstack "app.kubernetes.io/component=node")

    if [ -z "${redis_pod}" ]; then
        echo "No Redis pods found"
        return 1
    fi

    # Test Redis connection with PING
    if ! kubectl -n openstack exec "${redis_pod}" -c redis -- redis-cli PING 2>/dev/null | grep -q "PONG"; then
        echo "Redis is not responding to PING"
        return 1
    fi

    echo "Redis Sentinel is healthy and responding"
    return 0
}

# Test: OVN Northbound database is reachable
test_ovn_northbound_db() {
    check_kubectl || return 1

    # Check if OVN pods exist
    if ! kubectl -n kube-system get daemonset ovs-ovn >/dev/null 2>&1; then
        echo "OVN DaemonSet not found in kube-system namespace"
        return 1
    fi

    # Get first OVN pod
    local ovn_pod=$(get_first_pod_by_label kube-system "app=ovs")

    if [ -z "${ovn_pod}" ]; then
        echo "No OVN pods found"
        return 1
    fi

    # Test OVN NB connection
    if ! kubectl -n kube-system exec "${ovn_pod}" -c openvswitch -- ovn-nbctl --timeout=3 show >/dev/null 2>&1; then
        echo "OVN Northbound database is not reachable"
        return 1
    fi

    echo "OVN Northbound database is reachable"
    return 0
}

# Test: OVN Southbound database is reachable
test_ovn_southbound_db() {
    check_kubectl || return 1

    # Check if OVN pods exist
    if ! kubectl -n kube-system get daemonset ovs-ovn >/dev/null 2>&1; then
        echo "OVN DaemonSet not found in kube-system namespace"
        return 1
    fi

    # Get first OVN pod
    local ovn_pod=$(get_first_pod_by_label kube-system "app=ovs")

    if [ -z "${ovn_pod}" ]; then
        echo "No OVN pods found"
        return 1
    fi

    # Test OVN SB connection
    if ! kubectl -n kube-system exec "${ovn_pod}" -c openvswitch -- ovn-sbctl --timeout=3 show >/dev/null 2>&1; then
        echo "OVN Southbound database is not reachable"
        return 1
    fi

    echo "OVN Southbound database is reachable"
    return 0
}

# Test: Required secrets exist
test_required_secrets() {
    check_kubectl || return 1

    local required_secrets=(
        "keystone-admin"
        "mariadb-cluster-mariadb-galera"
        "rabbitmq-default-user"
        "os-memcached"
    )

    local missing_secrets=()

    for secret in "${required_secrets[@]}"; do
        if ! secret_exists openstack "${secret}"; then
            missing_secrets+=("${secret}")
        fi
    done

    if [ ${#missing_secrets[@]} -gt 0 ]; then
        echo "Missing required secrets: ${missing_secrets[*]}"
        return 1
    fi

    echo "All required secrets exist (${#required_secrets[@]} secrets checked)"
    return 0
}

# Main test execution
main() {
    TEST_SUITE_NAME="openstack-infra-tests"
    init_tests "${TEST_SUITE_NAME}"

    echo ""
    echo "Running OpenStack Infrastructure Tests..."
    echo ""

    run_test "mariadb_cluster" test_mariadb_cluster
    run_test "rabbitmq_cluster" test_rabbitmq_cluster
    run_test "memcached_running" test_memcached_running
    run_test "redis_sentinel" test_redis_sentinel
    run_test "ovn_northbound_db" test_ovn_northbound_db
    run_test "ovn_southbound_db" test_ovn_southbound_db
    run_test "required_secrets" test_required_secrets

    finalize_tests
}

# Run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
    exit $?
fi
