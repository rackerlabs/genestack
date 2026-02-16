#!/usr/bin/env bash

set -e

# --- Configuration Variables with Defaults ---
DEFAULT_GENESTACK_DIR="/opt/genestack"
DEFAULT_INVENTORY_FILE="/etc/genestack/inventory/inventory.yaml"
DEFAULT_KUBESPRAY_DIR="${DEFAULT_GENESTACK_DIR}/submodules/kubespray"

GENESTACK_DIR="$DEFAULT_GENESTACK_DIR"
INVENTORY_FILE="$DEFAULT_INVENTORY_FILE"
KUBESPRAY_DIR_ARG=""
DRY_RUN=false

# --- Temporary Directory Setup and Cleanup Trap ---
TEMP_DIR_BASE=$(mktemp -d -t kubespray_upgrade.XXXXXX)
EPOCH=$(date +%s)
NEW_GS_TEMP_DIR="${TEMP_DIR_BASE}_${EPOCH}"
mv "$TEMP_DIR_BASE" "$NEW_GS_TEMP_DIR"
GS_TEMP_DIR="$NEW_GS_TEMP_DIR"

function cleanup() {
    echo ""
    echo "--- Cleaning up temporary files and directories... ---"
    if [ -d "$GS_TEMP_DIR" ]; then
        rm -rf "$GS_TEMP_DIR"
        echo "Successfully removed temporary directory: $GS_TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

# --- Help Function ---
function displayHelp() {
    echo "Kubernetes Cluster Upgrade Script"
    echo "--------------------------------------------------------------------------------"
    echo "This script orchestrates a phased upgrade of a Kubernetes cluster managed by Kubespray"
    echo "within the Genestack environment. It includes mandatory preflight checks to ensure"
    echo "all necessary commands, directories, and inventory groups exist and are correctly configured."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --genestack-dir=PATH    Specify the root directory of the Genestack repository."
    echo "                              (Default: ${DEFAULT_GENESTACK_DIR})"
    echo "  -i, --inventory-file=PATH   Specify the Ansible inventory YAML file to use for the upgrade."
    echo "                              (Default: ${DEFAULT_INVENTORY_FILE})"
    echo "  -k, --kubespray-dir=PATH    Specify the Kubespray directory, overriding the calculated"
    echo "                              default relative path."
    echo "                              (Calculated Default if -d is not used: ${DEFAULT_KUBESPRAY_DIR})"
    echo "  --dry-run                   Perform all checks and output the commands that would be executed,"
    echo "                              but do NOT run any Ansible playbooks or modify the inventory file."
    echo "  -h, --help                  Display this help message and exit."
    echo ""
    echo "Required Preflight Checks:"
    echo "  - Commands: kubectl, ansible-playbook, yq"
    echo "  - Directories: \$GENESTACK_DIR and \$KUBESPRAY_DIR"
    echo "  - Files: \$GENESTACK_DIR/scripts/genestack.rc (Environment configuration)"
    echo "  - Inventory Groups (must exist in the inventory file, every host must belong to one of these groups):"
    echo "    kube_control_plane, etcd, genestack_worker_nodes, genestack_network_nodes,"
    echo "    genestack_compute_nodes, genestack_storage_nodes, genestack_excluded_nodes"
    exit 0
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            displayHelp
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -d|--genestack-dir)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                GENESTACK_DIR="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing." >&2
                exit 1
            fi
            ;;
        --genestack-dir=*)
            GENESTACK_DIR="${1#*=}"
            shift
            ;;
        -i|--inventory-file)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                INVENTORY_FILE="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing." >&2
                exit 1
            fi
            ;;
        --inventory-file=*)
            INVENTORY_FILE="${1#*=}"
            shift
            ;;
        -k|--kubespray-dir)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                KUBESPRAY_DIR_ARG="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing." >&2
                exit 1
            fi
            ;;
        --kubespray-dir=*)
            KUBESPRAY_DIR_ARG="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$KUBESPRAY_DIR_ARG" ]; then
    KUBESPRAY_DIR="$KUBESPRAY_DIR_ARG"
else
    KUBESPRAY_DIR="${GENESTACK_DIR}/submodules/kubespray"
fi

# --- Utility Function ---
function gitRepoVersion() {
    echo "$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match 2>/dev/null || git rev-parse HEAD)"
}

# --- Preflight Check Function ---
function preflightCheck() {
    local type=$1
    local target=$2
    local message=$3

    case "$type" in
        "command")
            if ! command -v "$target" &>/dev/null; then
                echo "Preflight Check Failed: ${target} command not found."
                echo "${message}"
                exit 1
            fi
            echo "Preflight Check Passed: ${target} command found."
            ;;
        "directory")
            if [[ ! -d "$target" ]]; then
                echo "Preflight Check Failed: Directory not found at ${target}"
                echo "${message}"
                exit 1
            fi
            echo "Preflight Check Passed: Directory found at ${target}."
            ;;
        "file")
            if [[ ! -f "$target" ]]; then
                echo "Preflight Check Failed: File not found at ${target}"
                echo "${message}"
                exit 1
            fi
            echo "Preflight Check Passed: File found at ${target}."
            ;;
        *)
            echo "Internal error: Unknown check type: $type"
            exit 1
            ;;
    esac
}

# --- Node Coverage Check ---
function checkAllNodesCovered() {
    local INVENTORY_FILE=$1
    shift
    local UPGRADE_GROUPS=("$@")
    local EXCLUDED_GROUP="genestack_excluded_nodes"

    echo "--- Checking Node Coverage: Ensuring all nodes are accounted for ---"

    local ALL_NODES_TEMP="${GS_TEMP_DIR}/all_nodes.tmp"

    # Try method 1: Use ansible-inventory to parse all hosts with ansible_host set
    ansible-inventory -i "$INVENTORY_FILE" --list 2>/dev/null | grep -oP '(?<="ansible_host": ").*?(?=",)' | sort -u > "$ALL_NODES_TEMP"

    # If method 1 fails (e.g., ansible-inventory issue), try method 2: use yq to pull all hosts from all children groups
    if [ ! -s "$ALL_NODES_TEMP" ]; then
        yq '.all.children.*.hosts | keys | .[]' "$INVENTORY_FILE" | grep -v '^$' | sort -u > "$ALL_NODES_TEMP"
    fi

    if [ ! -s "$ALL_NODES_TEMP" ]; then
        echo "Node Coverage Check Failed: Found no nodes in the inventory file. Please check the structure."
        exit 1
    fi

    local COVERED_NODES_TEMP="${GS_TEMP_DIR}/covered_nodes.tmp"

    local ALL_COVERAGE_GROUPS=("${UPGRADE_GROUPS[@]}" "$EXCLUDED_GROUP")
    local GROUP_LIMIT=$(IFS=:; echo "${ALL_COVERAGE_GROUPS[*]}")

    # Try method 1: Use ansible-inventory to parse hosts covered by the required groups
    ansible-inventory -i "$INVENTORY_FILE" --host "$GROUP_LIMIT" 2>/dev/null | \
      grep -oP '(?<="ansible_host": ").*?(?=",)' | sort -u > "$COVERED_NODES_TEMP"

    # If method 1 fails, try method 2: use yq to pull all hosts from the required groups
    if [ ! -s "$COVERED_NODES_TEMP" ]; then
        local HOSTS_QUERY=""
        for group in "${ALL_COVERAGE_GROUPS[@]}"; do
            HOSTS_QUERY="${HOSTS_QUERY} .all.children.${group}.hosts | keys | .[]"
        done
        yq "${HOSTS_QUERY}" "$INVENTORY_FILE" | grep -v '^$' | sort -u | uniq > "$COVERED_NODES_TEMP"
    fi

    local UNCOVERED_NODES=$(comm -23 "$ALL_NODES_TEMP" "$COVERED_NODES_TEMP" | grep -v '^localhost$' | sort -u)

    if [ -n "$UNCOVERED_NODES" ]; then
        echo "Node Coverage Check Failed: The following node(s) are defined in inventory but NOT included in an UPGRADE group or the '${EXCLUDED_GROUP}' group:"
        echo "--------------------------------------------------------"
        echo "${UNCOVERED_NODES}"
        echo "--------------------------------------------------------"
        echo "Please update your inventory to ensure every node is accounted for."
        exit 1
    fi

    echo "Node Coverage Check Passed: All nodes defined in the inventory are accounted for."
}


# --- Inventory Validation Function ---
function checkInventoryGroups() {
    local INVENTORY_FILE=$1
    local REQUIRED_GROUPS=(
        "kube_control_plane"
        "etcd"
        "genestack_worker_nodes"
        "genestack_network_nodes"
        "genestack_compute_nodes"
        "genestack_storage_nodes"
        "genestack_excluded_nodes"
    )

    echo "--- Checking required host groups in ${INVENTORY_FILE} ---"

    for group in "${REQUIRED_GROUPS[@]}"; do
        if ! yq ".all.children.${group}" "$INVENTORY_FILE" &>/dev/null; then
            echo "Inventory Check Failed: Host group '${group}' not found or incorrectly structured in ${INVENTORY_FILE}."
            echo "This group is required for the upgrade playbooks to limit correctly."
            exit 1
        fi
    done
    echo "Inventory Check Passed: All required host groups found."

    local UPGRADE_GROUPS=(
        "kube_control_plane"
        "etcd"
        "genestack_worker_nodes"
        "genestack_network_nodes"
        "genestack_compute_nodes"
        "genestack_storage_nodes"
    )
    checkAllNodesCovered "$INVENTORY_FILE" "${UPGRADE_GROUPS[@]}"
}


# --- Main Script Execution ---
echo "--- Kubernetes Cluster Upgrade Script ---"
if $DRY_RUN; then
    echo "!!! Running in DRY-RUN mode. No changes will be made to the system or files. !!!"
fi
echo "Genestack Directory: ${GENESTACK_DIR}"
echo "Kubespray Directory: ${KUBESPRAY_DIR}"
echo "Inventory File: ${INVENTORY_FILE}"
echo "Temporary Directory: ${GS_TEMP_DIR}"

echo "--- Running Preflight Checks ---"

preflightCheck "command" "kubectl" "You need kubectl installed and available in your PATH to manage the cluster."
preflightCheck "command" "ansible-playbook" "You need ansible-playbook installed and available in your PATH to run the upgrade."
preflightCheck "command" "yq" "The 'yq' tool is required for inventory validation and automatically updating the Kubernetes version variable. Please install it."

preflightCheck "directory" "$GENESTACK_DIR" "The Genestack repository is expected at this location to check its version."
preflightCheck "directory" "$KUBESPRAY_DIR" "The Kubespray directory is required for the upgrade playbooks."

preflightCheck "file" "$INVENTORY_FILE" "The Ansible inventory file is expected at this location."
checkInventoryGroups "$INVENTORY_FILE"

GENESTACK_RC_FILE="${GENESTACK_DIR}/scripts/genestack.rc"
preflightCheck "file" "$GENESTACK_RC_FILE" "The Genestack environment configuration file is critical for setting up Ansible paths and must exist at $GENESTACK_RC_FILE."

echo "--- Preflight Checks Complete ---"
echo ""

echo "This script will help you upgrade your Kubernetes cluster managed by Kubespray."

read -p "Enter the target Kubernetes version number (e.g., 1.34.0): " VERSION_NUMBER

echo "You have entered Kubernetes version number: ${VERSION_NUMBER}"

echo "Your current setup is as follows:"
pushd "$GENESTACK_DIR" &>/dev/null
    echo "Current Genestack version: $(gitRepoVersion) (SHA:$(git rev-parse HEAD))"
popd &>/dev/null

pushd "$KUBESPRAY_DIR" &>/dev/null
    echo "Current Kubespray version: $(gitRepoVersion) (SHA:$(git rev-parse HEAD))"
popd &>/dev/null

if $DRY_RUN; then
    echo "--- Skipping confirmation in DRY-RUN mode. ---"
else
    read -p "Is all of this correct? If yes type \`DOTHETHINGNOW\`: " CONFIRMATION

    if [[ "$CONFIRMATION" != "DOTHETHINGNOW" ]]; then
        echo "Aborting. Please run the script again and enter the correct version number and confirmation."
        exit 1
    fi
fi

set -v

# Source the environment file
if $DRY_RUN; then
    echo "DRY-RUN: . \"$GENESTACK_RC_FILE\" (Sourcing environment config)"
else
    . "$GENESTACK_RC_FILE"
fi

pushd "$KUBESPRAY_DIR" &>/dev/null
    echo "Gathering cluster facts"
    # Kubespray fact gathering is usually safe to run, even in a dry run, but for purity, we will echo it.
    ANSIBLE_CMD="ansible-playbook -i \"$INVENTORY_FILE\" playbooks/facts.yml --become"
    if $DRY_RUN; then
        echo "DRY-RUN: $ANSIBLE_CMD"
    else
        $ANSIBLE_CMD
    fi

    echo "--- Initiating Phased Cluster Upgrade to Kubernetes version ${VERSION_NUMBER} ---"

    # Define common playbook command structure
    UPGRADE_BASE_CMD="ansible-playbook -i \"$INVENTORY_FILE\" cluster.yml -e upgrade_cluster_setup=true -e kube_version=\"${VERSION_NUMBER}\" --become"

    # Upgrade control plane and etcd nodes
    echo "Upgrading control plane and etcd nodes to Kubernetes version ${VERSION_NUMBER}"
    ANSIBLE_CMD="${UPGRADE_BASE_CMD} --limit \"kube_control_plane:etcd\""
    if $DRY_RUN; then
        echo "DRY-RUN: $ANSIBLE_CMD"
    else
        $ANSIBLE_CMD
    fi

    # Upgrade worker and network nodes
    echo "Upgrading general worker and network nodes to Kubernetes version ${VERSION_NUMBER}"
    ANSIBLE_CMD="${UPGRADE_BASE_CMD} --limit \"genestack_worker_nodes:genestack_network_nodes\""
    if $DRY_RUN; then
        echo "DRY-RUN: $ANSIBLE_CMD"
    else
        $ANSIBLE_CMD
    fi

    # Upgrade compute nodes
    echo "Upgrading compute nodes (genestack_compute_nodes) to Kubernetes version ${VERSION_NUMBER}"
    ANSIBLE_CMD="${UPGRADE_BASE_CMD} --limit \"genestack_compute_nodes\""
    if $DRY_RUN; then
        echo "DRY-RUN: $ANSIBLE_CMD"
    else
        $ANSIBLE_CMD
    fi

    # Upgrade storage nodes
    echo "Upgrading storage nodes (genestack_storage_nodes) to Kubernetes version ${VERSION_NUMBER}"
    ANSIBLE_CMD="${UPGRADE_BASE_CMD} --limit \"genestack_storage_nodes\""
    if $DRY_RUN; then
        echo "DRY-RUN: $ANSIBLE_CMD"
    else
        $ANSIBLE_CMD
    fi

popd &>/dev/null

if $DRY_RUN; then
    echo "DRY-RUN: Kubernetes cluster upgrade to version ${VERSION_NUMBER} would have been completed."
else
    echo "Kubernetes cluster upgrade to version ${VERSION_NUMBER} completed successfully."
fi

echo "Updating Kubernetes version in inventory files"
YQ_CMD="yq -i \".kube_version = \"${VERSION_NUMBER}\"\" \"${GENESTACK_DIR}/inventory/group_vars/k8s_cluster/k8s-cluster.yml\""
if $DRY_RUN; then
    echo "DRY-RUN: $YQ_CMD (This command would update the version in the inventory file.)"
else
    if $YQ_CMD; then
        echo "Successfully updated kube_version to ${VERSION_NUMBER} in inventory."
    else
        echo "Error: Failed to update Kubernetes version using yq. Aborting." >&2
        exit 1
    fi
fi
