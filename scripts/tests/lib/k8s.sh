#!/bin/bash
# Kubernetes helper functions for Genestack testing
# Provides common kubectl operations and health checks

set -eo pipefail

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "ERROR: kubectl command not found"
        return 1
    fi
}

# Get all nodes and check if they're ready
check_nodes_ready() {
    local not_ready_count
    not_ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l)
    return $not_ready_count
}

# Get node count
get_node_count() {
    kubectl get nodes --no-headers 2>/dev/null | wc -l
}

# Wait for deployment to be available
# Arguments:
#   $1 - Namespace
#   $2 - Deployment name
#   $3 - Timeout in seconds (default: 60)
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-60}"

    kubectl -n "${namespace}" wait --timeout="${timeout}s" \
        deployment/"${deployment}" --for=condition=available 2>&1
}

# Wait for daemonset to be ready
# Arguments:
#   $1 - Namespace
#   $2 - DaemonSet name
#   $3 - Timeout in seconds (default: 60)
wait_for_daemonset() {
    local namespace="$1"
    local daemonset="$2"
    local timeout="${3:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local desired=$(kubectl -n "${namespace}" get daemonset "${daemonset}" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        local ready=$(kubectl -n "${namespace}" get daemonset "${daemonset}" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

        if [ "${desired}" -gt 0 ] && [ "${desired}" -eq "${ready}" ]; then
            return 0
        fi

        sleep 2
        ((elapsed+=2))
    done

    echo "Timeout waiting for daemonset ${namespace}/${daemonset}"
    return 1
}

# Check if a deployment exists and is available
# Arguments:
#   $1 - Namespace
#   $2 - Deployment name
is_deployment_available() {
    local namespace="$1"
    local deployment="$2"

    local available=$(kubectl -n "${namespace}" get deployment "${deployment}" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")

    [ "${available}" = "True" ]
}

# Check if a daemonset is ready
# Arguments:
#   $1 - Namespace
#   $2 - DaemonSet name
is_daemonset_ready() {
    local namespace="$1"
    local daemonset="$2"

    local desired=$(kubectl -n "${namespace}" get daemonset "${daemonset}" \
        -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    local ready=$(kubectl -n "${namespace}" get daemonset "${daemonset}" \
        -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

    [ "${desired}" -gt 0 ] && [ "${desired}" -eq "${ready}" ]
}

# Get pod count by label
# Arguments:
#   $1 - Namespace
#   $2 - Label selector
#   $3 - Phase filter (optional, e.g., "Running")
get_pod_count() {
    local namespace="$1"
    local label="$2"
    local phase="${3:-}"

    if [ -n "${phase}" ]; then
        kubectl -n "${namespace}" get pods -l "${label}" \
            --field-selector=status.phase="${phase}" --no-headers 2>/dev/null | wc -l
    else
        kubectl -n "${namespace}" get pods -l "${label}" --no-headers 2>/dev/null | wc -l
    fi
}

# Check if pods are running by label
# Arguments:
#   $1 - Namespace
#   $2 - Label selector
#   $3 - Minimum expected count (optional, default: 1)
are_pods_running() {
    local namespace="$1"
    local label="$2"
    local min_count="${3:-1}"

    local running_count=$(get_pod_count "${namespace}" "${label}" "Running")
    [ "${running_count}" -ge "${min_count}" ]
}

# Get all pods in a namespace
# Arguments:
#   $1 - Namespace
get_pods_in_namespace() {
    local namespace="$1"
    kubectl -n "${namespace}" get pods --no-headers 2>/dev/null
}

# Check if a storage class exists
# Arguments:
#   $1 - Storage class name
storage_class_exists() {
    local sc_name="$1"
    kubectl get storageclass "${sc_name}" -o name >/dev/null 2>&1
}

# Check if a secret exists
# Arguments:
#   $1 - Namespace
#   $2 - Secret name
secret_exists() {
    local namespace="$1"
    local secret_name="$2"

    kubectl -n "${namespace}" get secret "${secret_name}" -o name >/dev/null 2>&1
}

# Execute command in pod
# Arguments:
#   $1 - Namespace
#   $2 - Pod name
#   $3... - Command to execute
exec_in_pod() {
    local namespace="$1"
    local pod="$2"
    shift 2
    local cmd="$@"

    kubectl -n "${namespace}" exec "${pod}" -- ${cmd}
}

# Get first pod by label
# Arguments:
#   $1 - Namespace
#   $2 - Label selector
get_first_pod_by_label() {
    local namespace="$1"
    local label="$2"

    kubectl -n "${namespace}" get pods -l "${label}" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -n1
}

# Check if namespace exists
# Arguments:
#   $1 - Namespace name
namespace_exists() {
    local namespace="$1"
    kubectl get namespace "${namespace}" -o name >/dev/null 2>&1
}

# Get deployment replica count
# Arguments:
#   $1 - Namespace
#   $2 - Deployment name
get_deployment_replicas() {
    local namespace="$1"
    local deployment="$2"

    kubectl -n "${namespace}" get deployment "${deployment}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Check if StatefulSet is ready
# Arguments:
#   $1 - Namespace
#   $2 - StatefulSet name
is_statefulset_ready() {
    local namespace="$1"
    local statefulset="$2"

    local desired=$(kubectl -n "${namespace}" get statefulset "${statefulset}" \
        -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    local ready=$(kubectl -n "${namespace}" get statefulset "${statefulset}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    [ "${desired}" -gt 0 ] && [ "${desired}" -eq "${ready}" ]
}

# Get service endpoint
# Arguments:
#   $1 - Namespace
#   $2 - Service name
get_service_endpoint() {
    local namespace="$1"
    local service="$2"

    kubectl -n "${namespace}" get service "${service}" \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}
