#!/bin/bash

# --- Configuration ---
# Default file to store the original HPA settings for reversal
DEFAULT_HPA_CONFIG_FILE="hpa_originals.json"
# Name of the temporary patch file
PATCH_FILE="hpa-patch.json"

# --- Global Parameter ---
DRY_RUN=false

# --- Functions ---

# Function to safely exit on error and cleanup
function safe_exit {
    echo "ERROR: $1" >&2
    if [ -f "$PATCH_FILE" ]; then
        rm -f "$PATCH_FILE"
    fi
    exit 1
}

# Function to execute kubectl patch based on DRY_RUN mode
function execute_patch {
    local NAME="$1"
    local NAMESPACE="$2"
    local PATCH_TYPE="$3"
    local PATCH_FILE_NAME="$4"
    local ACTION_DESC="$5"

    if $DRY_RUN; then
        echo "  [DRY-RUN] Would have executed: kubectl patch hpa $NAME -n $NAMESPACE --type=$PATCH_TYPE --patch-file=$PATCH_FILE_NAME"
        echo "  [DRY-RUN] Patch Content:"
        cat "$PATCH_FILE_NAME" | sed 's/^/    /' 
        echo "  [DRY-RUN] Action: $ACTION_DESC"
        return 0
    else
        echo "  -> Applying patch: $ACTION_DESC"
        if kubectl patch hpa "$NAME" -n "$NAMESPACE" --type="$PATCH_TYPE" --patch-file="$PATCH_FILE_NAME"; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to display current HPA state (used in dry-run)
function display_current_hpa_state {
    echo "--- CURRENT LIVE HPA STATE ---"
    
    # Check for the lock file status
    if [ -f "$1" ]; then
        echo "Lock Status: LOCKED (Config file $1 EXISTS)"
    else
        echo "Lock Status: UNLOCKED (Config file $1 does NOT exist)"
    fi
    
    # Display the current HPA table
    kubectl get hpa --all-namespaces --no-headers -o=custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,REPLICAS:.status.currentReplicas,MIN_REPLICAS:.spec.minReplicas,MAX_REPLICAS:.spec.maxReplicas' | awk '
    BEGIN {
        printf "%-20s %-30s %-10s %-12s %-12s\n", "NAMESPACE", "NAME", "CURRENT", "MIN_LIVE", "MAX_LIVE"
        print "-------------------- ------------------------------ ---------- ------------ ------------"
    }
    { printf "%-20s %-30s %-10s %-12s %-12s\n", $1, $2, $3, $4, $5 }
    '
    echo "----------------------------------------------------------------------------------------"
}


# --- LOCK MODE: Save and Set MaxReplicas = MinReplicas ---
function lock_hpas {
    local HPA_CONFIG_FILE="$1"
    
    if $DRY_RUN; then
        display_current_hpa_state "$HPA_CONFIG_FILE"
    fi

    if [ -f "$HPA_CONFIG_FILE" ] && ! $DRY_RUN; then
        safe_exit "The lock file ($HPA_CONFIG_FILE) already exists. Run 'unlock' first, or delete the file manually if the operation was interrupted."
    fi

    echo "--- HPA LOCK MODE: Disabling Scaling ---"
    echo "Using config file: $HPA_CONFIG_FILE"
    
    echo "1. Retrieving current HPA configurations..."
    HPA_DATA=$(kubectl get hpa --all-namespaces -o json || safe_exit "Failed to retrieve HPA configs. Check kubectl access.")

    HPA_ORIGINALS=$(echo "$HPA_DATA" | jq '[
        .items[] | select(.spec.minReplicas and .spec.maxReplicas) | {
            namespace: .metadata.namespace, 
            name: .metadata.name, 
            original_min: .spec.minReplicas, 
            original_max: .spec.maxReplicas
        }
    ]')

    if [ "$(echo "$HPA_ORIGINALS" | jq '. | length')" -eq 0 ]; then
        echo "No HPA resources found to process. Exiting."
        exit 0
    fi

    if ! $DRY_RUN; then
        echo "$HPA_ORIGINALS" > "$HPA_CONFIG_FILE"
        echo "2. Successfully saved original settings to: $HPA_CONFIG_FILE"
    else
        echo "2. [DRY-RUN] Would have saved original settings to: $HPA_CONFIG_FILE"
    fi

    echo "3. Patching HPAs to lock scaling (maxReplicas = minReplicas)..."
    
    echo "$HPA_ORIGINALS" | jq -c '.[]' | while read -r HPA_ITEM; do
        NAMESPACE=$(echo "$HPA_ITEM" | jq -r '.namespace')
        NAME=$(echo "$HPA_ITEM" | jq -r '.name')
        MIN_REPLICAS=$(echo "$HPA_ITEM" | jq -r '.original_min')
        ORIGINAL_MAX=$(echo "$HPA_ITEM" | jq -r '.original_max')
        
        ACTION_DESC="Setting maxReplicas from $ORIGINAL_MAX to $MIN_REPLICAS"

        PATCH_CONTENT=$(cat <<EOF
[
  { "op": "replace", "path": "/spec/maxReplicas", "value": $MIN_REPLICAS }
]
EOF
        )
        echo "$PATCH_CONTENT" > "$PATCH_FILE"

        if ! execute_patch "$NAME" "$NAMESPACE" "json" "$PATCH_FILE" "$ACTION_DESC"; then
            safe_exit "Failed to patch HPA $NAME in namespace $NAMESPACE."
        fi
        rm -f "$PATCH_FILE"
    done
    
    echo "---"
    if $DRY_RUN; then
        echo "HPA Lock Dry Run Complete. NO changes were applied to the cluster."
    else
        echo "HPA Lock Complete. The cluster is ready for maintenance."
    fi
}

# --- UNLOCK MODE: Restore Original MaxReplicas ---
function unlock_hpas {
    local HPA_CONFIG_FILE="$1"
    
    if $DRY_RUN; then
        display_current_hpa_state "$HPA_CONFIG_FILE"
    fi
    
    echo "--- HPA UNLOCK MODE: Restoring Scaling ---"
    echo "Using config file: $HPA_CONFIG_FILE"
    
    if [ ! -f "$HPA_CONFIG_FILE" ]; then
        safe_exit "Original config file $HPA_CONFIG_FILE not found. Cannot proceed with unlock. Did you run 'lock' first?"
    fi

    echo "1. Reading original settings from $HPA_CONFIG_FILE"
    HPA_ORIGINALS=$(cat "$HPA_CONFIG_FILE")

    echo "2. Patching HPAs to restore original maxReplicas..."
    
    echo "$HPA_ORIGINALS" | jq -c '.[]' | while read -r HPA_ITEM; do
        NAMESPACE=$(echo "$HPA_ITEM" | jq -r '.namespace')
        NAME=$(echo "$HPA_ITEM" | jq -r '.name')
        ORIGINAL_MAX=$(echo "$HPA_ITEM" | jq -r '.original_max')
        ORIGINAL_MIN=$(echo "$HPA_ITEM" | jq -r '.original_min')
        
        ACTION_DESC="Setting maxReplicas from $ORIGINAL_MIN to $ORIGINAL_MAX (Restoring HPA)"

        PATCH_CONTENT=$(cat <<EOF
[
  { "op": "replace", "path": "/spec/maxReplicas", "value": $ORIGINAL_MAX }
]
EOF
        )
        echo "$PATCH_CONTENT" > "$PATCH_FILE"

        if ! execute_patch "$NAME" "$NAMESPACE" "json" "$PATCH_FILE" "$ACTION_DESC"; then
            safe_exit "Failed to restore HPA $NAME in namespace $NAMESPACE."
        fi
        rm -f "$PATCH_FILE"
    done

    if ! $DRY_RUN; then
        rm -f "$HPA_CONFIG_FILE"
        echo "3. Successfully removed the original config file: $HPA_CONFIG_FILE"
    else
        echo "3. [DRY-RUN] Would have removed the original config file: $HPA_CONFIG_FILE"
    fi
    
    echo "---"
    if $DRY_RUN; then
        echo "HPA Unlock Dry Run Complete. NO changes were applied to the cluster."
    else
        echo "HPA Unlock Complete. Scaling is re-enabled."
    fi
}

# --- Script Execution and Parameter Handling ---

ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--dry-run" ]; then
        DRY_RUN=true
        echo "========================================="
        echo "!!! DRY RUN MODE ENABLED - NO CHANGES WILL BE APPLIED !!!"
        echo "========================================="
    else
        ARGS+=("$arg")
    fi
done

if [ "${#ARGS[@]}" -lt 1 ] || [ "${#ARGS[@]}" -gt 2 ]; then
    echo "Usage: $0 {lock|unlock} [OPTIONAL_CONFIG_FILE] [--dry-run]"
    echo "  {lock|unlock}: The operation mode."
    echo "  [OPTIONAL_CONFIG_FILE]: The file to store/read HPA settings (defaults to $DEFAULT_HPA_CONFIG_FILE)."
    echo "  [--dry-run]: Optional flag to simulate changes without execution."
    exit 1
fi

MODE="${ARGS[0]}"

if [ "${#ARGS[@]}" -eq 2 ]; then
    HPA_CONFIG_FILE="${ARGS[1]}"
else
    HPA_CONFIG_FILE="$DEFAULT_HPA_CONFIG_FILE"
fi

case "$MODE" in
    lock)
        lock_hpas "$HPA_CONFIG_FILE"
        ;;
    unlock)
        unlock_hpas "$HPA_CONFIG_FILE"
        ;;
    *)
        echo "Invalid argument: $MODE"
        echo "Usage: $0 {lock|unlock} [OPTIONAL_CONFIG_FILE] [--dry-run]"
        exit 1
        ;;
esac
