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

# SCRIPT FOCUS: Validate Neutron Security Groups (SG) and Rules against OVN Port_Groups and ACLs.

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
    echo "Compares Neutron Security Groups and Rules with OVN NBDB Port_Groups and ACLs."
    echo "Identifies missing or stale security entities managed by Neutron."
    echo ""
    echo "Options:"
    echo "  --scan   Execute the comparison and diagnostic scan (read-only)."
    echo "  --fix    Execute the scan AND automatically deletes stale OVN ACLs and Port_Groups from the OVN NBDB."
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
        echo "=========================================================================="
        echo "  WARNING: FIX MODE IS ACTIVE! Stale ACLs and Port_Groups will be DELETED."
        echo "=========================================================================="
        echo ""
    else
        echo "========================================================"
        echo "  SCAN MODE ACTIVE (Read-Only). Use --fix to apply changes."
        echo "========================================================"
        echo ""
    fi

    echo "## 1. Extracting Neutron Security Group and Rule IDs..."

    # Extract Neutron Rules
    NEUTRON_RULES_DATA=$(openstack security group rule list -f value)
    NEUTRON_RULES_IDS=$(echo "$NEUTRON_RULES_DATA" | awk '{print $1}' | sort)
    NEUTRON_RULE_COUNT=$(echo "$NEUTRON_RULES_IDS" | wc -l)
    echo "   -> Found $NEUTRON_RULE_COUNT Neutron Security Group Rules."

    # Extract Neutron Security Groups
    NEUTRON_SG_DATA=$(openstack security group list -f value)
    NEUTRON_SG_IDS=$(echo "$NEUTRON_SG_DATA" | awk '{print $1}' | sort)
    NEUTRON_SG_COUNT=$(echo "$NEUTRON_SG_IDS" | wc -l)
    echo "   -> Found $NEUTRON_SG_COUNT Neutron Security Groups."

    echo ""

    # Build Sets for fast comparison
    NEUTRON_RULE_SET=" "
    for id in $NEUTRON_RULES_IDS; do
        NEUTRON_RULE_SET="${NEUTRON_RULE_SET}${id} "
    done

    NEUTRON_SG_SET=" "
    for id in $NEUTRON_SG_IDS; do
        NEUTRON_SG_SET="${NEUTRON_SG_SET}${id} "
    done

    echo "## 2. OVN ACL Comparison (Policy Rules)"

    declare -A ACL_UUIDS_MAP
    STALE_ACL_UUIDS=()

    OVN_ACL_DATA=$($KO_NBCTL_CMD --columns=_uuid,external_ids --bare --format=csv find ACL)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find ACL' command."
        exit 2
    fi

    # ACL_UUIDS_MAP uses Neutron Rule ID (Key) to OVN ACL UUID (Value)
    eval "$(
        echo "$OVN_ACL_DATA" |
        awk '
            BEGIN { FS="," }
            NF==2 {
                ovn_uuid = $1
                external_ids = $2

                if (external_ids ~ /neutron:security_group_rule_id=/) {
                    if (match(external_ids, /neutron:security_group_rule_id=([a-f0-9-]+)/, arr)) {
                        neutron_id = arr[1]
                        if (neutron_id != "") {
                            # Output a Bash assignment statement for direct eval
                            print "ACL_UUIDS_MAP[\"" neutron_id "\"]=\"" ovn_uuid "\""
                        }
                    }
                }
            }
        '
    )"

    OVN_RULE_COUNT=${#ACL_UUIDS_MAP[@]}
    echo "   -> Successfully mapped $OVN_RULE_COUNT unique Neutron Rule IDs to OVN ACLs."
    echo ""

    echo "## 3. OVN Port_Group Comparison (Security Groups)"

    declare -A PG_UUIDS_MAP
    STALE_PG_UUIDS=()

    OVN_PG_DATA=$($KO_NBCTL_CMD --columns=_uuid,external_ids --bare --format=csv find Port_Group)

    if [ $? -ne 0 ]; then
        echo "   [FATAL ERROR] Failed to execute 'ovn-nbctl find Port_Group' command."
        exit 2
    fi

    # PG_UUIDS_MAP uses Neutron SG ID (Key) to OVN Port_Group UUID (Value)
    eval "$(
        echo "$OVN_PG_DATA" |
        awk '
            BEGIN { FS="," }
            NF==2 {
                ovn_uuid = $1
                external_ids = $2

                if (external_ids ~ /neutron:security_group_id=/) {
                    if (match(external_ids, /neutron:security_group_id=([a-f0-9-]+)/, arr)) {
                        neutron_id = arr[1]
                        if (neutron_id != "") {
                            # Output a Bash assignment statement for direct eval
                            print "PG_UUIDS_MAP[\"" neutron_id "\"]=\"" ovn_uuid "\""
                        }
                    }
                }
            }
        '
    )"

    OVN_PG_COUNT=${#PG_UUIDS_MAP[@]}
    echo "   -> Successfully mapped $OVN_PG_COUNT unique Neutron SG IDs to OVN Port_Groups."
    echo ""

    echo "## 4. Comparison Report (Neutron Resources)"
    echo "------------------------------------------"

    echo "### A. Policy Rules (ACLs) - Neutron Rules vs OVN ACLs"
    MISSING_RULES=0
    for id in $NEUTRON_RULES_IDS; do
        if [[ ! ${ACL_UUIDS_MAP["$id"]} ]]; then
            echo "   [MISSING] Neutron SG Rule ID: $id"
            MISSING_RULES=$((MISSING_RULES + 1))
        fi
    done
    if [ $MISSING_RULES -eq 0 ]; then
        echo "   [OK] All $NEUTRON_RULE_COUNT Neutron SG Rules found in OVN NBDB."
    else
        echo "   [ERROR] Total Missing Rules: $MISSING_RULES"
    fi
    echo ""

    echo "### B. Stale Policy Rules (ACLs) in OVN NBDB"
    STALE_RULES=0
    for neutron_id in "${!ACL_UUIDS_MAP[@]}"; do
        if ! echo "$NEUTRON_RULE_SET" | grep -q " ${neutron_id} "; then
            ovn_uuid="${ACL_UUIDS_MAP["$neutron_id"]}"
            echo "   [STALE] Rule ID: $neutron_id (OVN ACL UUID: $ovn_uuid)"
            STALE_ACL_UUIDS+=("$ovn_uuid")
            STALE_RULES=$((STALE_RULES + 1))
        fi
    done

    if [ $STALE_RULES -eq 0 ]; then
        echo "   [OK] No stale Neutron-managed ACLs found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale Rules: $STALE_RULES"
        STALE_FOUND=1
    fi
    echo ""

    echo "### C. Security Groups (Port_Groups) - Neutron SGs vs OVN Port_Groups"
    MISSING_SGS=0
    for id in $NEUTRON_SG_IDS; do
        if [[ ! ${PG_UUIDS_MAP["$id"]} ]]; then
            echo "   [MISSING] Neutron SG ID: $id"
            MISSING_SGS=$((MISSING_SGS + 1))
        fi
    done
    if [ $MISSING_SGS -eq 0 ]; then
        echo "   [OK] All $NEUTRON_SG_COUNT Neutron SGs found as OVN Port_Groups."
    else
        echo "   [ERROR] Total Missing SGs: $MISSING_SGS"
    fi
    echo ""

    echo "### D. Stale Port_Groups in OVN NBDB"
    STALE_SGS=0
    for neutron_id in "${!PG_UUIDS_MAP[@]}"; do
        if ! echo "$NEUTRON_SG_SET" | grep -q " ${neutron_id} "; then
            ovn_uuid="${PG_UUIDS_MAP["$neutron_id"]}"
            echo "   [STALE] SG ID: $neutron_id (OVN Port_Group UUID: $ovn_uuid)"
            STALE_PG_UUIDS+=("$ovn_uuid")
            STALE_SGS=$((STALE_SGS + 1))
        fi
    done

    if [ $STALE_SGS -eq 0 ]; then
        echo "   [OK] No stale Neutron-managed Port_Groups found in OVN NBDB."
    else
        echo "   [CLEANUP NEEDED] Total Stale Port_Groups: $STALE_SGS"
        STALE_FOUND=1
    fi
    echo ""

    if [ "$FIX_MODE" = true ] && [ "$STALE_FOUND" -eq 1 ]; then
        echo "## 5. Remediation: Deleting Stale Resources from OVN NBDB"

        ACL_CLEANUP_COUNT=0
        ACL_TOTAL_TO_CLEANUP=${#STALE_ACL_UUIDS[@]}
        for acl_uuid in "${STALE_ACL_UUIDS[@]}"; do
            ACL_CLEANUP_COUNT=$((ACL_CLEANUP_COUNT + 1))
            echo "   -> [ACL $ACL_CLEANUP_COUNT/$ACL_TOTAL_TO_CLEANUP] Attempting to destroy STALE ACL UUID: $acl_uuid"
            $KO_NBCTL_CMD destroy ACL "$acl_uuid" || echo "   -> WARNING: Failed to destroy ACL $acl_uuid. May require manual cleanup."
        done

        PG_CLEANUP_COUNT=0
        PG_TOTAL_TO_CLEANUP=${#STALE_PG_UUIDS[@]}
        for pg_uuid in "${STALE_PG_UUIDS[@]}"; do
            PG_CLEANUP_COUNT=$((PG_CLEANUP_COUNT + 1))
            echo "   -> [PG $PG_CLEANUP_COUNT/$PG_TOTAL_TO_CLEANUP] Attempting to destroy STALE Port_Group UUID: $pg_uuid"
            $KO_NBCTL_CMD destroy Port_Group "$pg_uuid" || echo "   -> WARNING: Failed to destroy Port_Group $pg_uuid. May require manual cleanup."
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
