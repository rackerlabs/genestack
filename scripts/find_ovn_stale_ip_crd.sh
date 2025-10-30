#!/bin/bash

# Configuration Defaults
KUBECTL_OPTS="" # Add any kubectl options here
IP_CRD_KIND="ip" # The Kube-OVN IP CRD kind
DRY_RUN=true     # Default: True (safe mode)
TARGET_SUBNET="ovn-default" # Limit processing to this subnet

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        -r|--run) DRY_RUN=false; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done
# ------------------------

# Function to check if a Pod exists
check_pod_exists() {
    local namespace="$1"
    local pod_name="$2"
    kubectl ${KUBECTL_OPTS} get pod "${pod_name}" -n "${namespace}" --ignore-not-found --no-headers 2>/dev/null | grep -q "${pod_name}"
}

echo "Starting Kube-OVN Stale IP CRD Cleanup Script"

## Script Configuration and Status

echo "--------------------------------------------------------"
echo "TARGETING SUBNET: ${TARGET_SUBNET}"
if $DRY_RUN; then
    echo "MODE: DRY RUN (Safe Mode): No resources will be deleted. Delete commands are logged."
else
    echo "MODE: LIVE EXECUTION: Stale IP CRDs WILL BE DELETED."
fi
echo "--------------------------------------------------------"

ALL_IPS=$(kubectl ${KUBECTL_OPTS} get "${IP_CRD_KIND}" --all-namespaces -l ovn.kubernetes.io/subnet=${TARGET_SUBNET} -o json)

# Process each IP CRD
echo "${ALL_IPS}" | jq -c '.items[]' | while read -r IP_CRD; do
    IP_NAME=$(echo "${IP_CRD}" | jq -r '.metadata.name')

    # Extract Pod info
    POD_NAMESPACE=$(echo "${IP_CRD}" | jq -r '.spec.namespace' 2>/dev/null)
    POD_NAME=$(echo "${IP_CRD}" | jq -r '.spec.podName' 2>/dev/null) # Uses the corrected 'podName' field

    DELETE_COMMAND="kubectl ${KUBECTL_OPTS} delete ${IP_CRD_KIND} ${IP_NAME} -n ${POD_NAMESPACE}"

    if [[ -z "$POD_NAME" || "$POD_NAME" == "null" || -z "$POD_NAMESPACE" || "$POD_NAMESPACE" == "null" ]]; then
        # This catches resources where the spec fields are truly missing
        echo "MANUAL REVIEW REQUIRED: IP CRD ${IP_NAME} is missing Pod association fields."
        echo "   -> This likely refers to a non-Pod workload or a broken resource."
        echo "   -> MANUAL CHECK: Verify the status of the associated external workload."
        continue
    fi


    # Check if the associated pod exists
    if check_pod_exists "${POD_NAMESPACE}" "${POD_NAME}"; then
        echo "ACTIVE: IP ${POD_NAMESPACE}/${IP_NAME} (Associated Pod ${POD_NAMESPACE}/${POD_NAME} exists and is running)."
    else
        echo "STALE: IP ${POD_NAMESPACE}/${IP_NAME} (Associated Pod ${POD_NAMESPACE}/${POD_NAME} not found)."

        if ! $DRY_RUN; then
            echo "   -> Executing delete command: ${DELETE_COMMAND}"
            if eval "${DELETE_COMMAND}"; then
                echo "   -> Successfully deleted."
            else
                echo "   -> ERROR deleting IP CRD. Check finalizers or permissions."
            fi
        else
            echo "   -> DELETE CMD: ${DELETE_COMMAND}"
            echo "   -> (Dry Run: Would have deleted the stale IP CRD.)"
        fi
    fi
done

echo "--------------------------------------------------------"
echo "Script finished. Only IPs from ${TARGET_SUBNET} were inspected."
