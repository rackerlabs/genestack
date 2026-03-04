#!/bin/bash
# common-functions.sh - Shared library for Genestack installation scripts
#
# Version: 2.0
# Description: This library provides common functionality for Genestack installation
#              scripts, including Helm management, secret handling, dependency checks,
#              parallel execution, and Kubernetes resource management.
# Documentation: See the Genestack documentation for detailed usage examples.
#
# Usage: Source this file in installation scripts:
#        source /opt/genestack/scripts/common-functions.sh

# --- Global Variables ---
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
HELM_TIMEOUT_DEFAULT="120m"

# Global arrays for parallel tracking
declare -A pids
declare -A pid_commands

# --- Environment & Dependency Checks ---

# check_dependencies - Verify required command-line tools are installed
#
# Usage: check_dependencies CMD1 CMD2 ...
# Parameters:
#   $@ - List of command names to check for availability
# Exits: 1 if any required command is not found
# Example:
#   check_dependencies "kubectl" "helm" "yq"
check_dependencies() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' not found. Please install it." >&2
            exit 1
        fi
    done
}

# check_cluster_connection - Verify connectivity to Kubernetes cluster
#
# Usage: check_cluster_connection
# Parameters: None
# Exits: 1 if unable to connect to Kubernetes cluster
# Example:
#   check_cluster_connection
check_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: Cannot connect to Kubernetes cluster. check your KUBECONFIG." >&2
        exit 1
    fi
}

# perform_preflight_checks - Run all preflight checks before installation
#
# Usage: perform_preflight_checks [--skip-base64]
# Parameters:
#   $1 - (Optional) --skip-base64 flag to exclude base64 from dependency checks
# Exits: 1 if any preflight check fails
# Example:
#   perform_preflight_checks
#   perform_preflight_checks --skip-base64
perform_preflight_checks() {
    local include_base64=true
    if [[ "$1" == "--skip-base64" ]]; then
        include_base64=false
    fi

    if [ "$include_base64" = true ]; then
        check_dependencies "kubectl" "helm" "yq" "jq" "base64" "sed" "grep"
    else
        check_dependencies "kubectl" "helm" "yq" "jq" "sed" "grep"
    fi
    check_cluster_connection
}

# init_service_directories - Initialize and export service directory paths
#
# Usage: init_service_directories SERVICE_NAME
# Parameters:
#   $1 - Service name for which to initialize directory paths
# Returns: Exports SERVICE_BASE_OVERRIDES, SERVICE_CUSTOM_OVERRIDES, and GLOBAL_OVERRIDES_DIR
# Example:
#   init_service_directories "keystone"
init_service_directories() {
    local service_name=$1

    # Export directory paths as global variables
    export SERVICE_BASE_OVERRIDES="${GENESTACK_BASE_DIR}/base-helm-configs/${service_name}"
    export SERVICE_CUSTOM_OVERRIDES="${GENESTACK_OVERRIDES_DIR}/helm-configs/${service_name}"
    export GLOBAL_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"
}

# --- Helm Management ---

# get_chart_version - Retrieve Helm chart version for a service
#
# Usage: get_chart_version SERVICE_NAME
# Parameters:
#   $1 - Service name to look up in helm-chart-versions.yaml
# Returns: Outputs the version string for the service
# Exits: 1 if version file not found or service version not found
# Example:
#   VERSION=$(get_chart_version "keystone")
get_chart_version() {
    local service=$1
    local version_file="${GENESTACK_OVERRIDES_DIR}/helm-chart-versions.yaml"

    if [ ! -f "$version_file" ]; then
        echo "Error: helm-chart-versions.yaml not found at $version_file" >&2
        exit 1
    fi

    local version=$(grep "^[[:space:]]*${service}:" "$version_file" | sed "s/.*${service}: *//")

    if [ -z "$version" ]; then
        echo "Error: Could not extract version for '$service' from $version_file" >&2
        exit 1
    fi

    echo "$version"
}

# update_helm_repo - Add or update a Helm repository
#
# Usage: update_helm_repo REPO_NAME REPO_URL
# Parameters:
#   $1 - Repository name
#   $2 - Repository URL
# Example:
#   update_helm_repo "openstack-helm" "https://registry.genestack.io/chartrepo/openstack-helm"
update_helm_repo() {
    local repo_name=$1
    local repo_url=$2
    echo "Updating Helm repository: $repo_name"
    helm repo add "$repo_name" "$repo_url" --force-update
    helm repo update "$repo_name"
}

# extract_chart_metadata - Extract chart metadata from YAML configuration files
#
# Usage: extract_chart_metadata CUSTOM_DIR REPO_URL_VAR REPO_NAME_VAR SERVICE_VAR DEFAULT_URL DEFAULT_REPO DEFAULT_SERVICE
# Parameters:
#   $1 - Custom overrides directory to search for YAML files
#   $2 - Name reference variable for repository URL (output)
#   $3 - Name reference variable for repository name (output)
#   $4 - Name reference variable for service name (output)
#   $5 - Default repository URL if not found in YAML
#   $6 - Default repository name if not found in YAML
#   $7 - Default service name if not found in YAML
# Returns: Populates the referenced variables with extracted or default values
# Example:
#   extract_chart_metadata "$SERVICE_CUSTOM_OVERRIDES" repo_url repo_name service_name \
#     "https://registry.genestack.io/chartrepo/openstack-helm" "openstack-helm" "keystone"
extract_chart_metadata() {
    local custom_overrides_dir=$1
    local -n repo_url_var=$2
    local -n repo_name_var=$3
    local -n service_name_var=$4
    local repo_url_default=$5
    local repo_name_default=$6
    local service_name_default=$7

    # Try to extract from custom YAML files
    for yaml_file in "${custom_overrides_dir}"/*.yaml; do
        if [ -f "$yaml_file" ]; then
            local extracted_url=$(yq eval '.chart.repo_url // ""' "$yaml_file")
            local extracted_name=$(yq eval '.chart.repo_name // ""' "$yaml_file")
            local extracted_service=$(yq eval '.chart.service_name // ""' "$yaml_file")

            [[ -n "$extracted_url" ]] && repo_url_var="$extracted_url"
            [[ -n "$extracted_name" ]] && repo_name_var="$extracted_name"
            [[ -n "$extracted_service" ]] && service_name_var="$extracted_service"
            break
        fi
    done

    # Set defaults if not extracted
    : "${repo_url_var:=$repo_url_default}"
    : "${repo_name_var:=$repo_name_default}"
    : "${service_name_var:=$service_name_default}"
}

# setup_helm_chart_path - Construct Helm chart path based on repository type
#
# Usage: setup_helm_chart_path REPO_URL REPO_NAME SERVICE_NAME
# Parameters:
#   $1 - Repository URL (may be OCI registry or HTTP)
#   $2 - Repository name
#   $3 - Service name
# Returns: Outputs the full chart path for use in helm commands
# Example:
#   CHART_PATH=$(setup_helm_chart_path "oci://ghcr.io" "openstack-helm" "keystone")
setup_helm_chart_path() {
    local repo_url=$1
    local repo_name=$2
    local service_name=$3

    if [[ "$repo_url" == oci://* ]]; then
        echo "$repo_url/$repo_name/$service_name"
    else
        update_helm_repo "$repo_name" "$repo_url"
        echo "$repo_name/$service_name"
    fi
}

# build_helm_command - Construct a complete Helm upgrade command array
#
# Usage: build_helm_command SERVICE_NAME CHART_PATH VERSION NAMESPACE SET_ARGS_REF OVERRIDES_REF HELM_CMD_REF
# Parameters:
#   $1 - Service name for the Helm release
#   $2 - Chart path (local or repository reference)
#   $3 - Chart version to install
#   $4 - Kubernetes namespace for installation
#   $5 - Name reference to array of --set arguments
#   $6 - Name reference to array of override file arguments
#   $7 - Name reference to output array for the complete Helm command
# Returns: Populates the referenced HELM_CMD_REF array with the complete command
# Example:
#   build_helm_command "keystone" "openstack-helm/keystone" "0.1.0" "openstack" set_args overrides helm_cmd
build_helm_command() {
    local service_name=$1
    local chart_path=$2
    local version=$3
    local namespace=$4
    local -n set_args_ref=$5
    local -n overrides_ref=$6
    local -n helm_cmd_ref=$7

    helm_cmd_ref=(
        helm upgrade --install "$service_name" "$chart_path"
        --version "$version"
        --namespace="$namespace"
        --timeout "${HELM_TIMEOUT:-$HELM_TIMEOUT_DEFAULT}"
        --create-namespace
        --atomic
        --cleanup-on-fail
        "${overrides_ref[@]}"
        "${set_args_ref[@]}"
        --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
        --post-renderer-args "$service_name/overlay"
    )
}

# execute_helm_upgrade - Execute a Helm upgrade command with passthrough arguments
#
# Usage: execute_helm_upgrade HELM_CMD_REF PASSTHROUGH_REF
# Parameters:
#   $1 - Name reference to array containing the Helm command
#   $2 - Name reference to array of additional passthrough arguments
# Returns: 0 on success, 1 on failure
# Example:
#   execute_helm_upgrade helm_cmd passthrough_args
execute_helm_upgrade() {
    local -n helm_command_ref=$1
    local -n passthrough_ref=$2

    echo "Executing Helm command:"
    printf '%q ' "${helm_command_ref[@]}" "${passthrough_ref[@]}"
    echo

    if "${helm_command_ref[@]}" "${passthrough_ref[@]}"; then
        return 0
    else
        echo "Error: Helm upgrade failed." >&2
        return 1
    fi
}

# parse_install_args - Parse installation script arguments for special flags
#
# Usage: parse_install_args ROTATE_VAR PASSTHROUGH_VAR [ARGS...]
# Parameters:
#   $1 - Name reference to boolean variable for rotate-secrets flag
#   $2 - Name reference to array for passthrough arguments
#   $@ - Remaining arguments to parse
# Returns: Populates referenced variables with parsed values
# Example:
#   parse_install_args rotate_secrets passthrough_args "$@"
parse_install_args() {
    local -n rotate_var=$1
    local -n passthrough_var=$2

    rotate_var=false
    passthrough_var=()

    while [[ "$#" -gt 1 ]]; do
        shift  # Skip the first argument (function name reference)
        case $1 in
            --rotate-secrets) rotate_var=true; shift ;;
            *) passthrough_var+=("$1"); shift ;;
        esac
    done
}

# process_overrides - Process Helm override files from a directory
#
# Usage: process_overrides DIRECTORY ARRAY_REF LABEL
# Parameters:
#   $1 - Directory path to scan for YAML override files
#   $2 - Name reference to array to append -f flags and file paths
#   $3 - Descriptive label for logging purposes
# Returns: Populates the referenced array with -f flags for each YAML file found
# Example:
#   process_overrides "$SERVICE_BASE_OVERRIDES" overrides_array "base overrides"
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

# collect_service_overrides - Collect all Helm override files for a service
#
# Usage: collect_service_overrides SERVICE_NAME OVERRIDES_ARRAY_REF
# Parameters:
#   $1 - Service name for which to collect overrides
#   $2 - Name reference to array to populate with override file flags
# Returns: Populates the referenced array with all applicable -f flags in precedence order
# Example:
#   collect_service_overrides "keystone" overrides_array
collect_service_overrides() {
    local service_name=$1
    local -n overrides_array=$2

    local service_base="${GENESTACK_BASE_DIR}/base-helm-configs/${service_name}"
    local service_custom="${GENESTACK_OVERRIDES_DIR}/helm-configs/${service_name}"
    local global_overrides="${GENESTACK_OVERRIDES_DIR}/helm-configs/global_overrides"

    overrides_array=()
    process_overrides "$service_base" overrides_array "base overrides"
    process_overrides "$global_overrides" overrides_array "global overrides"
    process_overrides "$service_custom" overrides_array "service config overrides"
}

# --- Secret Management ---

# get_or_create_secret - Retrieve or generate a Kubernetes secret value
#
# Usage: get_or_create_secret NAMESPACE SECRET_NAME KEY_NAME [LENGTH] [ROTATE]
# Parameters:
#   $1 - Kubernetes namespace
#   $2 - Secret name
#   $3 - Key name within the secret
#   $4 - (Optional) Length of generated secret (default: 32)
#   $5 - (Optional) Boolean to force rotation (default: false)
# Returns: Outputs the secret value
# Example:
#   PASSWORD=$(get_or_create_secret "openstack" "keystone-db-password" "password" 64 false)
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

# get_or_create_ssh_keypair - Retrieve or generate an SSH keypair in Kubernetes secret
#
# Usage: get_or_create_ssh_keypair NAMESPACE SECRET_NAME COMMENT ROTATE PRIV_KEY_VAR PUB_KEY_VAR
# Parameters:
#   $1 - Kubernetes namespace
#   $2 - Secret name
#   $3 - (Optional) SSH key comment (default: "genestack")
#   $4 - (Optional) Boolean to force rotation (default: false)
#   $5 - Name reference variable to store private key
#   $6 - Name reference variable to store public key
# Returns: Populates the referenced private and public key variables
# Example:
#   get_or_create_ssh_keypair "openstack" "nova-ssh-key" "nova@compute" false priv_key pub_key
get_or_create_ssh_keypair() {
    local namespace=$1
    local secret_name=$2
    local comment=${3:-"genestack"}
    local rotate=${4:-false}
    local -n priv_key_var=$5
    local -n pub_key_var=$6

    if ! kubectl -n "$namespace" get secret "$secret_name" >/dev/null 2>&1 || [ "$rotate" = true ]; then
        echo "Generating new SSH keypair for $secret_name..."
        local tmp_dir=$(mktemp -d)
        ssh-keygen -t rsa -b 4096 -N "" -f "$tmp_dir/id_rsa" -C "$comment"
        priv_key_var=$(cat "$tmp_dir/id_rsa")
        pub_key_var=$(cat "$tmp_dir/id_rsa.pub")

        kubectl -n "$namespace" create secret generic "$secret_name" \
            --from-literal=private_key="$priv_key_var" \
            --from-literal=public_key="$pub_key_var" \
            --dry-run=client -o yaml | kubectl apply -f -
        rm -rf "$tmp_dir"
    else
        priv_key_var=$(kubectl -n "$namespace" get secret "$secret_name" -o jsonpath='{.data.private_key}' | base64 -d)
        pub_key_var=$(kubectl -n "$namespace" get secret "$secret_name" -o jsonpath='{.data.public_key}' | base64 -d)
    fi
}

# wait_for_resource_ready - Wait for Kubernetes resources to become ready
#
# Usage: wait_for_resource_ready NAMESPACE RESOURCE_TYPE [TIMEOUT] RESOURCE1 [RESOURCE2...]
# Parameters:
#   $1 - Kubernetes namespace
#   $2 - Resource type (deployment, statefulset, or daemonset)
#   $3 - (Optional) Timeout in seconds (default: 300)
#   $@ - List of resource names to wait for
# Returns: 0 if all resources become ready, 1 on failure or timeout
# Example:
#   wait_for_resource_ready "openstack" "deployment" 600 "keystone-api" "keystone-worker"
wait_for_resource_ready() {
    local namespace=$1
    local resource_type=$2  # deployment, statefulset, daemonset
    local timeout=${3:-300}
    shift 3
    local resources=("$@")

    for resource in "${resources[@]}"; do
        if kubectl -n "$namespace" get "$resource_type" "$resource" >/dev/null 2>&1; then
            case "$resource_type" in
                deployment)
                    kubectl -n "$namespace" wait --for=condition=available --timeout="${timeout}s" \
                        "$resource_type/$resource" || return 1
                    ;;
                statefulset|daemonset)
                    kubectl -n "$namespace" rollout status "$resource_type/$resource" --timeout="${timeout}s" || return 1
                    ;;
                *)
                    echo "Error: Unsupported resource type '$resource_type'" >&2
                    return 1
                    ;;
            esac
        else
            echo "Warning: $resource_type/$resource not found, skipping wait" >&2
        fi
    done
    return 0
}

# discover_service_endpoint - Discover a Kubernetes service endpoint
#
# Usage: discover_service_endpoint NAMESPACE SERVICE_NAME PORT DEFAULT_VALUE
# Parameters:
#   $1 - Kubernetes namespace
#   $2 - Service name
#   $3 - Service port number
#   $4 - Default value to return if service not found
# Returns: Outputs the service endpoint (ClusterIP:Port) or default value
# Example:
#   ENDPOINT=$(discover_service_endpoint "openstack" "keystone-api" "5000" "keystone-api.openstack.svc.cluster.local:5000")
discover_service_endpoint() {
    local namespace=$1
    local service_name=$2
    local port=$3
    local default_value=$4

    local endpoint=$(kubectl -n "$namespace" get svc "$service_name" -o jsonpath="{.spec.clusterIP}:${port}" 2>/dev/null || echo "")

    if [[ -n "$endpoint" ]]; then
        echo "$endpoint"
    else
        echo "$default_value"
    fi
}

# --- Orchestration Engine ---

# is_enabled - Check if an OpenStack component is enabled in configuration
#
# Usage: is_enabled COMPONENT_NAME
# Parameters:
#   $1 - Component name to check in openstack-components.yaml
# Returns: 0 (true) if component is enabled, 1 (false) otherwise
# Example:
#   if is_enabled "cinder"; then
#     echo "Cinder is enabled"
#   fi
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

# run_parallel - Execute a command in the background and track its PID
#
# Usage: run_parallel "COMMAND"
# Parameters:
#   $1 - Command string to execute in the background
# Returns: Starts the command in background and tracks it in global pids array
# Example:
#   run_parallel "bash /opt/genestack/bin/install-keystone.sh"
run_parallel() {
    local cmd="${1}"
    eval "${cmd}" &
    local pid=$!
    pids[$pid]=1
    pid_commands[$pid]="${cmd}"
    echo "[PARALLEL] Started: ${cmd} (PID: ${pid})"
}

# wait_parallel - Wait for all background tasks to complete with timeout
#
# Usage: wait_parallel [TIMEOUT_MINUTES]
# Parameters:
#   $1 - (Optional) Timeout in minutes (default: 45)
# Exits: 1 if any background task fails or timeout is reached
# Example:
#   run_parallel "install-keystone.sh"
#   run_parallel "install-glance.sh"
#   wait_parallel 60
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
