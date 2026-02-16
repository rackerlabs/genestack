# -----------------------------------------------
#                             _             _
#                            | |           | |
#   __ _  ___ _ __   ___  ___| |_ __ _  ___| | __
#  / _` |/ _ \ '_ \ / _ \/ __| __/ _` |/ __| |/ /
# | (_| |  __/ | | |  __/\__ \ || (_| | (__|   <
#  \__, |\___|_| |_|\___||___/\__\__,_|\___|_|\_\
#   __/ |           ops scripts
#  |___/
# -----------------------------------------------
#!/bin/bash

# SCRIPT FOCUS: Validate Neutron Floating IPs (FIPs) against OVN Logical_Router NAT rules.
# This check ensures that all active FIPs have a corresponding dnat_and_snat rule in OVN.

KO_NBCTL_CMD="kubectl ko nbctl"

# --- Dependency Check ---
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "ERROR: DEPENDENCY MISSING: Bash version 4.0 or higher is required for associative array support."
    echo "Current version: $BASH_VERSION"
    exit 2
fi

if ! command -v openstack &> /dev/null; then
    echo "ERROR: DEPENDENCY MISSING: 'openstack' client command not found."
    echo "Please ensure the OpenStack CLI is installed and configured correctly (source openrc)."
    exit 2
fi

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: DEPENDENCY MISSING: 'kubectl' command not found."
    echo "Please ensure kubectl is installed and in your PATH."
    exit 2
fi

if ! command -v awk &> /dev/null; then
    echo "ERROR: DEPENDENCY MISSING: 'awk' command not found. This is needed for data parsing."
    exit 2
fi

if ! command -v grep &> /dev/null; then
    echo "ERROR: DEPENDENCY MISSING: 'grep' command not found. This is needed for filtering and comparison."
    exit 2
fi

if ! $KO_NBCTL_CMD show &> /dev/null; then
    echo "ERROR: FAILED CONNECTION: Failed to connect to OVN NBDB using '$KO_NBCTL_CMD show'."
    echo "Please check your 'kubectl ko' configuration/alias and OVN controller status."
    exit 2
fi
# --- End Dependency Check ---

FIX_MODE=false
SCAN_MODE=false
HELP_MODE=false
STALE_FOUND=0

for arg in "$@"; do
    case "$arg" in
        --scan)
            SCAN_MODE=true
            ;;
        --fix)
            FIX_MODE=true
            SCAN_MODE=true
            ;;
        --help)
            HELP_MODE=true
            ;;
        *)
            if [[ "$arg" != "--scan" && "$arg" != "--fix" ]]; then
                HELP_MODE=true
            fi
            ;;
    esac
done

show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Compares Neutron Floating IPs (FIPs) with OVN Logical_Router NAT rules."
    echo "Identifies missing or stale FIP-related NAT entries."
    echo ""
    echo "Options:"
    echo "  --scan   Execute the comparison and diagnostic scan (read-only)."
    echo "  --fix    Execute the scan AND automatically deletes stale OVN NAT rules associated with FIPs."
    echo "  --help   Display this help message and exit."
    echo ""
    echo "Exit Codes for Automation (CronJobs):"
    echo "  0: Script completed successfully (Fix mode) OR Scan mode found no stale resources."
    echo "  1: Scan mode found stale resources (Signals a cleanup action is required)."
    echo "  2: Fatal error during dependency check or OVN DB query."
    echo ""
}

if [ "$#" -eq 0 ] || [ "$HELP_MODE" = true ]; then
    show_help
    exit 0
fi

if [ "$SCAN_MODE" = true ]; then

    if [ "$FIX_MODE" = true ]; then
        echo "=================================================================================="
        echo "  WARNING: FIX MODE IS ACTIVE! Stale FIP NAT rules will be DELETED."
        echo "=================================================================================="
        echo ""
    else
        echo "========================================================"
        echo "  SCAN MODE ACTIVE (Read-Only). Use --fix to apply changes."
        echo "========================================================"
        echo ""
    fi

    echo "## 1. Extracting Neutron Floating IP IDs and their associated OVN keys..."

    # Extract ID, FIP Address, and Fixed IP Address (for filtering unassigned)
    NEUTRON_FIP_DATA=$(
        openstack floating ip list -f value -c ID -c "Floating IP Address" -c "Fixed IP Address"
    )

    declare -A NEUTRON_FIP_MAP
    NEUTRON_FIP_SET=" "

    # Neutron FIP Map: Key=FIP_IP_Address, Value=Neutron_FIP_UUID
    while read -r id fip_ip fixed_ip; do
        if [[ -n "$id" && -n "$fip_ip" && "$fixed_ip" != "None" ]]; then
            NEUTRON_FIP_MAP["$fip_ip"]="$id"
            NEUTRON_FIP_SET="${NEUTRON_FIP_SET}${fip_ip} "
        fi
    done <<< "$NEUTRON_FIP_DATA"

    NEUTRON_FIP_COUNT=${#NEUTRON_FIP_MAP[@]}
    echo "   -> Found $NEUTRON_FIP_COUNT ASSIGNED Neutron Floating IPs to check."
    echo ""

    echo "## 2. OVN Logical_Router NAT Comparison"

    declare -A NAT_RULE_MAP
    STALE_NAT_UUIDS=()

    # Get NAT rules that are of type dnat_and_snat, which is used for FIPs
    # Columns: _uuid, type, external_ip, external_ids
    # Note: We query all LRs to get all NAT rules managed by OVN.
    OVN_NAT_DATA=$($KO_NBCTL_CMD --columns=_uuid,type,external_ip,external_ids --bare --format=csv find NAT type=dnat_and_snat)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find NAT' command."
        exit 2
    fi

    # NAT_RULE_MAP uses Floating IP Address (Key) to OVN NAT UUID (Value)
    eval "$(
        echo "$OVN_NAT_DATA" |
        awk '
            BEGIN { FS="," }
            NF>=3 {
                ovn_uuid = $1
                nat_type = $2
                # The external_ip is the Floating IP Address
                fip_ip = $3

                # Strip all whitespace from the IP address
                gsub(/^[ \t]+|[ \t]+$/, "", fip_ip)

                # Check for a valid IP format and ensure it is the correct type
                if (nat_type == "dnat_and_snat" && fip_ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    # Output a Bash assignment statement for direct eval
                    print "NAT_RULE_MAP[\"" fip_ip "\"]=\"" ovn_uuid "\""
                }
            }
        '
    )"

    OVN_NAT_COUNT=${#NAT_RULE_MAP[@]}
    echo "   -> Successfully mapped $OVN_NAT_COUNT unique FIP addresses to OVN NAT Rules."
    echo ""

    echo "## 3. Comparison Report"
    echo "------------------------------------------"

    echo "### A. Missing FIP NAT Rules in OVN NBDB (FIP Provisioning Failure)"
    MISSING_FIPS=0
    for fip_ip in "${!NEUTRON_FIP_MAP[@]}"; do
        if [[ ! ${NAT_RULE_MAP["$fip_ip"]} ]]; then
            fip_id="${NEUTRON_FIP_MAP["$fip_ip"]}"
            echo "   [MISSING] Neutron FIP ID: $fip_id (FIP Address: $fip_ip)"
            MISSING_FIPS=$((MISSING_FIPS + 1))
        fi
    done
    if [ $MISSING_FIPS -eq 0 ]; then
        echo "   [OK] All $NEUTRON_FIP_COUNT Neutron FIPs found as OVN NAT rules."
    else
        echo "   [ERROR] Total Missing FIP NAT Rules: $MISSING_FIPS"
    fi
    echo ""

    echo "### B. Stale FIP NAT Rules in OVN NBDB (FIP Cleanup Failure)"
    STALE_NAT_RULES=0
    for fip_ip in "${!NAT_RULE_MAP[@]}"; do
        if ! echo "$NEUTRON_FIP_SET" | grep -q " ${fip_ip} "; then
            ovn_uuid="${NAT_RULE_MAP["$fip_ip"]}"
            echo "   [STALE] FIP Address: $fip_ip (OVN NAT UUID: $ovn_uuid)"
            STALE_NAT_UUIDS+=("$ovn_uuid")
            STALE_NAT_RULES=$((STALE_NAT_RULES + 1))
        fi
    done

    if [ $STALE_NAT_RULES -eq 0 ]; then
        echo "   [OK] No stale FIP-related NAT rules found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale FIP NAT Rules: $STALE_NAT_RULES"
        STALE_FOUND=1
    fi
    echo ""

    if [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 1 ]; then
        echo "## 4. Remediation: Deleting Stale NAT Rules from OVN NBDB"

        NAT_CLEANUP_COUNT=0
        NAT_TOTAL_TO_CLEANUP=${#STALE_NAT_UUIDS[@]}
        for nat_uuid in "${STALE_NAT_UUIDS[@]}"; do
            NAT_CLEANUP_COUNT=$((NAT_CLEANUP_COUNT + 1))
            echo "   -> [NAT $NAT_CLEANUP_COUNT/$NAT_TOTAL_TO_CLEANUP] Attempting to destroy STALE NAT UUID: $nat_uuid"
            $KO_NBCTL_CMD destroy NAT "$nat_uuid" || echo "   -> WARNING: Failed to destroy NAT $nat_uuid. May require manual cleanup."
        done

        echo "   [COMPLETE] Remediation attempt finished."
        exit 0
    elif [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 0 ]; then
        echo "## 4. Remediation"
        echo "   [SKIP] Fix mode enabled, but no stale resources found to delete."
        exit 0
    fi

    exit "$STALE_FOUND"

fi
