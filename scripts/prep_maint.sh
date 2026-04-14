i#!/bin/bash

# --- Configuration & Pre-flight ---
MAINT_NAME=$1
NS="openstack"

# Function to check for required binaries
check_dependencies() {
    local deps=("kubectl" "tmux" "sed" "grep" "base64")
    local missing=()
    for tool in "${deps[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo "ERROR: Missing required tools: ${missing[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
}

check_dependencies

if [ -z "$MAINT_NAME" ]; then
    echo "Usage: ./prep_maint.sh <maintenance_name>"
    exit 1
fi

# Timestamps & Directories
TS=$(date +%Y%m%d_%H%M%S)
PREP_TS=$(date +%Y%m%d-%H%M)
MAINT_DIR="/home/ubuntu/maintenances/${MAINT_NAME}_${TS}"

echo "### STARTING PREP ###"

# 1. Create maintenance directory
mkdir -p "$MAINT_DIR"
touch "$MAINT_DIR/PREP_IN_PROGRESS_${PREP_TS}"
echo "Prep started: $(date)" > "$MAINT_DIR/status.log"

# 2. MariaDB Backup (Saved directly to the maint directory)
echo "Taking MariaDB database dump..."
MARIADB_NAME=$(kubectl -n $NS get mariadbs.k8s.mariadb.com -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ROOT_PASSWORD=$(kubectl -n $NS get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d 2>/dev/null)
PRIMARY_POD=$(kubectl -n $NS get mariadb "$MARIADB_NAME" -o jsonpath="{.status.currentPrimary}" 2>/dev/null)

if [ -z "$PRIMARY_POD" ] || [ -z "$ROOT_PASSWORD" ]; then
    echo "ERROR: Could not retrieve MariaDB details. Check kubectl access/namespace."
    rm -rf "$MAINT_DIR" # Cleanup empty dir if we fail early
    exit 1
fi

DB_DUMP_FILE="${MAINT_DIR}/mariadb-backup-${TS}.sql"
kubectl -n $NS exec "$PRIMARY_POD" -- sh -c "exec mariadb-dump --all-databases --single-transaction --master-data=2 -uroot -p'${ROOT_PASSWORD}'" > "$DB_DUMP_FILE"

echo "Backup saved to: $DB_DUMP_FILE"
echo "Database Backup: $(basename "$DB_DUMP_FILE")" >> "$MAINT_DIR/status.log"

# 3. Configure tmux logging
sed -i '/pipe-pane -o/d' ~/.tmux.conf 2>/dev/null
cat << EOT >> ~/.tmux.conf
bind-key H pipe-pane -o "exec cat >>$MAINT_DIR/'#W-tmux.log'" \; display-message 'Logging to $MAINT_DIR/#W-tmux.log'
EOT

# 4. Disable HPA
echo "Locking HPA..."
cd "$MAINT_DIR" || exit
/opt/genestack/scripts/manage_hpa.sh lock --dry-run
/opt/genestack/scripts/manage_hpa.sh lock

# 5. Disable self-healing services
echo "Stopping Octavia self-healing..."
sudo systemctl disable --now check-octavia-ovn.timer
sudo systemctl stop check-octavia-ovn.service

ulimit -n 65535
export PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w $(date +'%s') \$ '

echo "------------------------------------------------"
echo "PREP COMPLETE."
echo "Directory: $MAINT_DIR"
echo "Inside tmux, press 'Ctrl+b' then 'H' to log."
echo "------------------------------------------------"

tmux new -s "$MAINT_NAME"
