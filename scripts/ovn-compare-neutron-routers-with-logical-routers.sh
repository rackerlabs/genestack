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

# SCRIPT FOCUS: Validate Neutron Routers and Router Ports against OVN Logical_Router and Logical_Router_Port.

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
    echo "Compares Neutron Routers and Router Ports with OVN NBDB Logical_Router and Logical_Router_Port."
    echo "Identifies missing or stale router and port entities managed by Neutron."
    echo ""
    echo "Options:"
    echo "  --scan   Execute the comparison and diagnostic scan (read-only)."
    echo "  --fix    Execute the scan AND automatically deletes stale OVN Routers and Router Ports."
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
        echo "  WARNING: FIX MODE IS ACTIVE! Stale Logical Routers/Router Ports will be DELETED."
        echo "=================================================================================="
        echo ""
    else
        echo "========================================================"
        echo "  SCAN MODE ACTIVE (Read-Only). Use --fix to apply changes."
        echo "========================================================"
        echo ""
    fi

    echo "## 1. Extracting Neutron Router and Router Port IDs..."

    NEUTRON_ROUTER_IDS=$(openstack router list -f value -c ID | awk '{print $1}' | sort)
    NEUTRON_ROUTER_COUNT=$(echo "$NEUTRON_ROUTER_IDS" | wc -l)
    echo "   -> Found $NEUTRON_ROUTER_COUNT Neutron Routers."

    NEUTRON_RPORT_DATA=$(
        openstack port list --device-owner network:router_interface --long -f value -c ID;
        openstack port list --device-owner network:router_gateway --long -f value -c ID
    )
    NEUTRON_RPORT_IDS=$(echo "$NEUTRON_RPORT_DATA" | awk '{print $1}' | sort | uniq)
    NEUTRON_RPORT_COUNT=$(echo "$NEUTRON_RPORT_IDS" | wc -l)
    echo "   -> Found $NEUTRON_RPORT_COUNT Neutron Router Ports (Interfaces/Gateways)."
    echo ""

    NEUTRON_ROUTER_SET=" "
    for id in $NEUTRON_ROUTER_IDS; do
        NEUTRON_ROUTER_SET="${NEUTRON_ROUTER_SET}${id} "
    done


    NEUTRON_RPORT_SET=" "
    for id in $NEUTRON_RPORT_IDS; do
        NEUTRON_RPORT_SET="${NEUTRON_RPORT_SET}${id} "
    done

    echo "## 2. OVN Logical_Router Comparison (Neutron Routers)"

    declare -A LR_UUIDS_MAP
    STALE_LR_UUIDS=()

    OVN_LR_DATA=$($KO_NBCTL_CMD --columns=_uuid,name --bare --format=csv find Logical_Router)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find Logical_Router' command."
        exit 2
    fi

    eval "$(
        echo "$OVN_LR_DATA" |
        awk '
            BEGIN { FS="," }
            NF==2 {
                ovn_uuid = $1
                if (match($2, /neutron-([a-f0-9-]+)/, arr)) {
                    neutron_id = arr[1]

                    gsub(/^[ \t]+|[ \t]+$/, "", neutron_id)

                    if (neutron_id ~ /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/) {
                        print "LR_UUIDS_MAP[\"" neutron_id "\"]=\"" ovn_uuid "\""
                    }
                }
            }
        '
    )"

    OVN_LR_COUNT=${#LR_UUIDS_MAP[@]}
    echo "   -> Successfully mapped $OVN_LR_COUNT unique Neutron Router IDs to OVN Logical_Routers."
    echo ""

    echo "## 3. OVN Logical_Router_Port Comparison (Neutron Router Ports)"

    declare -A LRP_UUIDS_MAP
    STALE_LRP_UUIDS=()

    OVN_LRP_DATA=$($KO_NBCTL_CMD --columns=_uuid,name --bare --format=csv find Logical_Router_Port)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find Logical_Router_Port' command."
        exit 2
    fi

    eval "$(
        echo "$OVN_LRP_DATA" |
        awk '
            BEGIN { FS="," }
            NF==2 {
                ovn_uuid = $1
                neutron_id = $2

                # Check for either 'UUID' or 'lrp-UUID' format. Capture group 2 is the UUID.
                if (match(neutron_id, /^(lrp-)?([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/, arr)) {
                    neutron_id = arr[2]

                    gsub(/^[ \t]+|[ \t]+$/, "", neutron_id)

                    if (neutron_id != "") {
                        print "LRP_UUIDS_MAP[\"" neutron_id "\"]=\"" ovn_uuid "\""
                    }
                }
            }
        '
    )"

    OVN_LRP_COUNT=${#LRP_UUIDS_MAP[@]}
    echo "   -> Successfully mapped $OVN_LRP_COUNT unique Neutron Router Port IDs to OVN Logical_Router_Ports."
    echo ""

    echo "## 4. Comparison Report"
    echo "------------------------------------------"

    echo "### A. Missing Logical Routers in OVN NBDB"
    MISSING_ROUTERS=0
    for id in $NEUTRON_ROUTER_IDS; do
        if [[ ! ${LR_UUIDS_MAP["$id"]} ]]; then
            echo "   [MISSING] Neutron Router ID: $id"
            MISSING_ROUTERS=$((MISSING_ROUTERS + 1))
        fi
    done
    if [ $MISSING_ROUTERS -eq 0 ]; then
        echo "   [OK] All $NEUTRON_ROUTER_COUNT Neutron Routers found as OVN Logical_Routers."
    else
        echo "   [ERROR] Total Missing Routers: $MISSING_ROUTERS"
    fi
    echo ""

    echo "### B. Stale Logical Routers in OVN NBDB"
    STALE_ROUTERS=0
    for neutron_id in "${!LR_UUIDS_MAP[@]}"; do
        if ! echo "$NEUTRON_ROUTER_SET" | grep -q " ${neutron_id} "; then
            ovn_uuid="${LR_UUIDS_MAP["$neutron_id"]}"
            echo "   [STALE] Router ID: $neutron_id (OVN LR UUID: $ovn_uuid)"
            STALE_LR_UUIDS+=("$ovn_uuid")
            STALE_ROUTERS=$((STALE_ROUTERS + 1))
        fi
    done

    if [ $STALE_ROUTERS -eq 0 ]; then
        echo "   [OK] No stale Logical_Routers found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale Logical_Routers: $STALE_ROUTERS"
        STALE_FOUND=1
    fi
    echo ""

    echo "### C. Missing Logical_Router_Ports in OVN NBDB"
    MISSING_RPORTS=0
    for id in $NEUTRON_RPORT_IDS; do
        if [[ ! ${LRP_UUIDS_MAP["$id"]} ]]; then
            echo "   [MISSING] Neutron Router Port ID: $id"
            MISSING_RPORTS=$((MISSING_RPORTS + 1))
        fi
    done
    if [ $MISSING_RPORTS -eq 0 ]; then
        echo "   [OK] All $NEUTRON_RPORT_COUNT Neutron Router Ports found as OVN Logical_Router_Ports."
    else
        echo "   [ERROR] Total Missing Router Ports: $MISSING_RPORTS"
    fi
    echo ""

    echo "### D. Stale Logical_Router_Ports in OVN NBDB"
    STALE_RPORTS=0
    for neutron_id in "${!LRP_UUIDS_MAP[@]}"; do
        if ! echo "$NEUTRON_RPORT_SET" | grep -q " ${neutron_id} "; then
            ovn_uuid="${LRP_UUIDS_MAP["$neutron_id"]}"
            echo "   [STALE] Router Port ID: $neutron_id (OVN LRP UUID: $ovn_uuid)"
            STALE_LRP_UUIDS+=("$ovn_uuid")
            STALE_RPORTS=$((STALE_RPORTS + 1))
        fi
    done

    if [ $STALE_RPORTS -eq 0 ]; then
        echo "   [OK] No stale Logical_Router_Ports found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale Logical_Router_Ports: $STALE_RPORTS"
        STALE_FOUND=1
    fi
    echo ""


    if [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 1 ]; then
        echo "## 5. Remediation: Deleting Stale Resources from OVN NBDB"

        LRP_CLEANUP_COUNT=0
        LRP_TOTAL_TO_CLEANUP=${#STALE_LRP_UUIDS[@]}
        for lrp_uuid in "${STALE_LRP_UUIDS[@]}"; do
            LRP_CLEANUP_COUNT=$((LRP_CLEANUP_COUNT + 1))
            echo "   -> [LRP $LRP_CLEANUP_COUNT/$LRP_TOTAL_TO_CLEANUP] Attempting to destroy STALE Logical_Router_Port UUID: $lrp_uuid"
            $KO_NBCTL_CMD destroy Logical_Router_Port "$lrp_uuid" || echo "   -> WARNING: Failed to destroy Logical_Router_Port $lrp_uuid. May require manual cleanup."
        done

        LR_CLEANUP_COUNT=0
        LR_TOTAL_TO_CLEANUP=${#STALE_LR_UUIDS[@]}
        for lr_uuid in "${STALE_LR_UUIDS[@]}"; do
            LR_CLEANUP_COUNT=$((LR_CLEANUP_COUNT + 1))
            echo "   -> [LR $LR_CLEANUP_COUNT/$LR_TOTAL_TO_CLEANUP] Attempting to destroy STALE Logical_Router UUID: $lr_uuid"
            $KO_NBCTL_CMD destroy Logical_Router "$lr_uuid" || echo "   -> WARNING: Failed to destroy Logical_Router $lr_uuid. May require manual cleanup."
        done

        echo "   [COMPLETE] Remediation attempt finished."
        exit 0
    elif [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 0 ]; then
        echo "## 5. Remediation"
        echo "   [SKIP] Fix mode enabled, but no stale resources found to delete."
        exit 0
    fi

    exit "$STALE_FOUND"

fi
