#!/bin/bash

# Script to use 'kubectl get ip' to list all Kube-OVN allocated IP records
# and check for duplicates. It also checks if the referenced Pod still exists.

echo "--- Fetching all Kube-OVN IP records (ips.kubeovn.io) across all namespaces..."
echo "Note: This command relies on the Kube-OVN 'IP' Custom Resource Definition (CRD)."

# 1. Fetch all IP records using the custom resource 'ip'
# The output format for each record is: <IP_ADDRESS> <NAMESPACE> <POD_NAME>
# The 'kubectl get ip -A' output columns are NAME, NAMESPACE, IPADDRESS, MACADDRESS, SUBNET, NODE, PODNAME
IP_DATA=$(kubectl get ip -A -o custom-columns=IPADDRESS:.spec.ipAddress,NAMESPACE:.spec.namespace,PODNAME:.spec.podName --no-headers 2>/dev/null)

if [ -z "$IP_DATA" ]; then
    echo "ERROR: No Kube-OVN 'IP' records found. Ensure Kube-OVN is running correctly." >&2
    exit 1
fi

ALL_IPS=$(echo "$IP_DATA" | awk '{print $1}')

# sort | uniq -c: counts unique lines (IPs)
# awk '$1 > 1': filters for IPs that appeared more than once
DUPLICATE_IPS=$(echo "$ALL_IPS" | sort | uniq -c | awk '$1 > 1 {print $2}')

# --- Function to Check Pod Existence ---
# Checks if the pod exists in the given namespace and returns a status string.
check_pod_status() {
    local ns="$1"
    local pod="$2"
    # Try to get the pod, suppressing errors, and check the exit code
    if kubectl get pod "$pod" -n "$ns" --no-headers &>/dev/null; then
        echo "Active"
    else
        echo "Missing"
    fi
}
export -f check_pod_status

# --- Output Results ---

if [ -z "$DUPLICATE_IPS" ]; then
    echo ""
    echo "*** Success: No duplicate Kube-OVN IP addresses found across the cluster."
else
    echo ""
    echo "*** Duplicate IP Addresses Found! ATTENTION"
    echo "-------------------------------------"

    echo "$DUPLICATE_IPS" | while read DUP_IP; do
        echo "IP: ${DUP_IP} is used by:"
        # Use grep to filter the original data for the duplicate IP
        # Then iterate over the resulting lines
        echo "$IP_DATA" | grep "^${DUP_IP}\s" | while read -r IP NS POD; do
            POD_STATUS=$(check_pod_status "$NS" "$POD")

            # The name of the IP CRD is always <podName>.<namespace>
            IP_CRD_NAME="${POD}.${NS}"

            # Use '\t' (tab) for indentation
            if [[ "$POD_STATUS" == "Active" ]]; then
                echo -e "\t- namespace: ${NS} podname: ${POD} | Status: ${POD_STATUS}"
            else
                echo -e "\t- *** namespace: ${NS} podname: ${POD} | Status: ${POD_STATUS} (Stale CRD?)"
                echo -e "\t= *** Resolution: kubectl delete ip ${IP_CRD_NAME}"
            fi
        done
    done
    echo "-------------------------------------"
    echo "Action Required: Investigate the pods and the kube-ovn-controller logs."
    echo "Duplicate IPs and 'Missing' Pods often indicate stale IP records (CRDs) that need cleanup."
fi
