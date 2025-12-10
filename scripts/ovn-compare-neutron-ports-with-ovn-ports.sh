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

# SCRIPT FOCUS: Validate Neutron Ports against OVN Logical_Switch_Ports (LSPs).

KO_NBCTL_CMD="kubectl ko nbctl"

# --- Dependency Check ---
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "ERROR: DEPENDENCY MISSING: Bash version 4.0 or higher is required for mapfile/readarray support."
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
    echo "Compares standard Neutron Ports (excluding floating IPs) against OVN NBDB Logical_Switch_Ports (LSPs)."
    echo "Mapping is done by comparing Neutron Port UUIDs with the OVN LSP 'name' column."
    echo ""
    echo "Options:"
    echo "  --scan   Execute the comparison and diagnostic scan (read-only)."
    echo "  --fix    Execute the scan AND automatically deletes stale OVN LSPs from the OVN NBDB."
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
        echo "  WARNING: FIX MODE IS ACTIVE! Stale Logical Switch Ports will be DELETED."
        echo "=================================================================================="
        echo ""
    else
        echo "========================================================"
        echo "  SCAN MODE ACTIVE (Read-Only). Use --fix to apply changes."
        echo "========================================================"
        echo ""
    fi

    echo "## 1. Extracting Neutron Port IDs (Excluding Floating IPs)..."

    # Get Neutron Port UUIDs, explicitly excluding ports with device_owner=network:floatingip
    NEUTRON_ALL_PORTS_DATA=$(openstack port list --long -f value -c ID -c device_owner)

    NEUTRON_LSP_IDS=$(
        echo "$NEUTRON_ALL_PORTS_DATA" |
        grep -v "network:floatingip" |
        awk '{print $1}' |
        sort
    )

    NEUTRON_PORT_COUNT=$(echo "$NEUTRON_LSP_IDS" | wc -l)

    if [ $NEUTRON_PORT_COUNT -lt 1 ]; then
        echo "   [INFO] Found 0 Neutron Ports (excluding FIPs). Skipping comparison."
        exit 0
    fi
    echo "   -> Found $NEUTRON_PORT_COUNT Neutron Standard Ports (LSPs expected)."

    echo ""

    NEUTRON_LSP_ID_SET=" "
    for id in $NEUTRON_LSP_IDS; do
        NEUTRON_LSP_ID_SET="${NEUTRON_LSP_ID_SET}${id} "
    done

    echo "## 2. OVN Logical_Switch_Port Comparison"

    declare -A LSP_UUIDS_MAP
    STALE_LSP_UUIDS=()

    # Get LSP UUID and its name (which contains the Neutron Port UUID)
    OVN_LSP_DATA=$($KO_NBCTL_CMD --columns=_uuid,name --bare --format=csv find Logical_Switch_Port)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find Logical_Switch_Port' command."
        exit 2
    fi

    # LSP_UUIDS_MAP uses Neutron UUID (from LSP name) as key, OVN LSP UUID as value
    eval "$(
        echo "$OVN_LSP_DATA" |
        awk '
            BEGIN { FS="," }
            NF==2 {
                ovn_uuid = $1
                neutron_id = $2

                # Check for UUID format to identify Neutron ports
                if (neutron_id ~ /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/) {
                    # Output a Bash assignment statement for direct eval
                    print "LSP_UUIDS_MAP[\"" neutron_id "\"]=\"" ovn_uuid "\""
                }
            }
        '
    )"

    OVN_LSP_COUNT=${#LSP_UUIDS_MAP[@]}
    echo "   -> Mapped $OVN_LSP_COUNT unique OVN LSPs believed to be Neutron ports."
    echo ""

    echo "## 3. Comparison Report (Standard Ports)"
    echo "----------------------------------------"

    echo "### A. Missing Standard Ports (LSPs) in OVN NBDB"
    MISSING_PORTS=0

    for id in $NEUTRON_LSP_IDS; do
        # Check if the Neutron UUID exists as a key in our LSP map
        if [[ ! ${LSP_UUIDS_MAP["$id"]} ]]; then
            echo "   [MISSING] Neutron Port ID (LSP): $id"
            MISSING_PORTS=$((MISSING_PORTS + 1))
        fi
    done

    if [ $MISSING_PORTS -eq 0 ]; then
        echo "   [OK] All $NEUTRON_PORT_COUNT Neutron Standard Ports found as OVN LSPs."
    else
        echo "   [ERROR] Total Missing Standard Ports: $MISSING_PORTS"
    fi
    echo ""

    echo "### B. Stale Logical Switch Ports (LSPs) in OVN NBDB"
    STALE_PORTS=0

    for neutron_id in "${!LSP_UUIDS_MAP[@]}"; do
        ovn_uuid="${LSP_UUIDS_MAP["$neutron_id"]}"

        # Check if the Neutron UUID (from OVN LSP name) is NOT in the current Neutron LSP ID set
        if ! echo "$NEUTRON_LSP_ID_SET" | grep -q " ${neutron_id} "; then
            # If the ID is not in the Neutron set, the LSP is stale
            echo "   [STALE] Port ID (LSP): $neutron_id (OVN LSP UUID: $ovn_uuid)"
            STALE_LSP_UUIDS+=("$ovn_uuid")
            STALE_PORTS=$((STALE_PORTS + 1))
        fi
    done

    if [ $STALE_PORTS -eq 0 ]; then
        echo "   [OK] No stale Neutron-managed LSPs found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale Standard Ports: $STALE_PORTS"
        STALE_FOUND=1
    fi
    echo ""

    if [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 1 ]; then
        echo "## 4. Remediation: Deleting Stale Resources from OVN NBDB"

        LSP_CLEANUP_COUNT=0
        LSP_TOTAL_TO_CLEANUP=${#STALE_LSP_UUIDS[@]}
        for lsp_uuid in "${STALE_LSP_UUIDS[@]}"; do
            LSP_CLEANUP_COUNT=$((LSP_CLEANUP_COUNT + 1))
            echo "   -> [LSP $LSP_CLEANUP_COUNT/$LSP_TOTAL_TO_CLEANUP] Attempting to destroy STALE Logical_Switch_Port UUID: $lsp_uuid"
            $KO_NBCTL_CMD destroy Logical_Switch_Port "$lsp_uuid" || echo "   -> WARNING: Failed to destroy Logical_Switch_Port $lsp_uuid. May require manual cleanup."
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
