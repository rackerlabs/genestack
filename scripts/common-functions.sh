#!/bin/bash
# common-functions.sh - Shared library for Genestack installation scripts

# --- Global Variables ---
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
HELM_TIMEOUT_DEFAULT="120m"

# Global arrays for parallel tracking
declare -A pids
declare -A pid_commands

# --- Environment & Dependency Checks ---

check_dependencies() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' not found. Please install it." >&2
            exit 1
        fi
    done
}

check_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: Cannot connect to Kubernetes cluster. check your KUBECONFIG." >&2
        exit 1
    fi
}

# --- Helm Management ---

update_helm_repo() {
    local repo_name=$1
    local repo_url=$2
    echo "Updating Helm repository: $repo_name"
    helm repo add "$repo_name" "$repo_url" --force-update
    helm repo update "$repo_name"
}

process_overrides() {
    local dir=$1
    local -n arr=$2
    local label=$3

    if [[ -d "$dir" ]]; then
        echo "Including $label from: $dir"
        for file in "$dir"/*.yaml; do
            if [[ -e "$file" ]]; then
                echo "  - $(basename "$file")"
                arr+=("-f" "$file")
            fi
        done
    else
        echo "Note: $label directory not found ($dir). Skipping."
    fi
}

# --- Secret Management ---

get_or_create_secret() {
    local namespace=$1
    local secret_name=$2
    local key_name=$3
    local length=${4:-32}
    local rotate=${5:-false}

    local secret_val=""

    if [[ "$rotate" == "false" ]]; then
        secret_val=$(kubectl -n "$namespace" get secret "$secret_name" -o jsonpath="{.data.$key_name}" 2>/dev/null | base64 -d)
    fi

    if [[ -z "$secret_val" ]]; then
        echo "Generating/Rotating secret: $secret_name (key: $key_name)"
        secret_val=$(openssl rand -base64 512 | tr -dc 'a-zA-Z0-9' | head -c "$length")
        
        kubectl create secret generic "$secret_name" \
            --namespace "$namespace" \
            --from-literal="$key_name"="$secret_val" \
            --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    fi

    echo "$secret_val"
}

# --- Orchestration Engine ---

is_enabled() {
    local component=$1
    local config_file="${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml"
    if [[ -f "$config_file" ]]; then
        grep -qi "^[[:space:]]*${component}:[[:space:]]*true" "$config_file"
    else
        # Default to false if config is missing
        return 1
    fi
}

run_parallel() {
    local cmd="${1}"
    eval "${cmd}" &
    local pid=$!
    pids[$pid]=1
    pid_commands[$pid]="${cmd}"
    echo "[PARALLEL] Started: ${cmd} (PID: ${pid})"
}

wait_parallel() {
    local timeout_minutes="${1:-45}"
    local start_time=$(date +%s)
    local timeout_seconds=$((timeout_minutes * 60))

    while [ ${#pids[@]} -gt 0 ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout_seconds ]; then
            echo "==== ERROR: TIMEOUT ======================================"
            echo "Parallel tasks timed out after ${timeout_minutes}m."
            for pid in "${!pids[@]}"; do
                echo "  Terminating PID ${pid}: ${pid_commands[$pid]}"
                kill ${pid} 2>/dev/null || true
            done
            exit 1
        fi

        for pid in "${!pids[@]}"; do
            if ! kill -0 ${pid} 2>/dev/null; then
                wait ${pid} || local exit_code=$?
                exit_code=${exit_code:-0}

                if [ $exit_code -ne 0 ]; then
                    echo "==== ERROR: PROCESS FAILED ==============================="
                    echo "Command: ${pid_commands[$pid]}"
                    echo "Exit Code: ${exit_code}"
                    echo "=========================================================="
                    exit 1
                fi
                unset "pids[$pid]"
            fi
        done
        sleep 2
    done
    echo "[PARALLEL] All background tasks completed successfully."
}
