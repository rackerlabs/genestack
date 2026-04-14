#!/bin/bash

# Find latest maint dir
LATEST_MAINT=$(ls -td /home/ubuntu/maintenances/*/ 2>/dev/null | head -n 1)

if [ -z "$LATEST_MAINT" ]; then
    echo "ERROR: No maintenance directory found."
    exit 1
fi

# Check for completion marker
if ls "${LATEST_MAINT}"POST_MAINT_COMPLETE_* 1> /dev/null 2>&1; then
    echo "SKIPPING: Cleanup already performed for $LATEST_MAINT"
    exit 0
fi

echo "### STARTING POST-MAINTENANCE CLEANUP ###"

# Unlock HPA
cd "$LATEST_MAINT" || exit
/opt/genestack/scripts/manage_hpa.sh unlock --dry-run
/opt/genestack/scripts/manage_hpa.sh unlock

# Re-enable self-healing
sudo systemctl enable --now check-octavia-ovn.timer
sudo systemctl start check-octavia-ovn.service

# Clean up tmux config
sed -i '/pipe-pane -o/d' ~/.tmux.conf 2>/dev/null

# Finalize Markers
POST_TS=$(date +%Y%m%d-%H%M)
rm -f "${LATEST_MAINT}"PREP_IN_PROGRESS_*
touch "${LATEST_MAINT}POST_MAINT_COMPLETE_${POST_TS}"
echo "Cleanup completed: $(date)" >> "${LATEST_MAINT}status.log"

# Locate backup for easy reference
BACKUP_FILE=$(ls "${LATEST_MAINT}"mariadb-backup-*.sql 2>/dev/null)

echo "### CLEANUP COMPLETE ###"
echo "------------------------------------------------"
echo "Active Backup found in: ${BACKUP_FILE:-None Found}"
echo "To restore if needed:"
echo "kubectl -n openstack exec -i <PRIMARY_POD> -- sh -c \"exec mariadb -uroot -p'\$PW'\" < $BACKUP_FILE"
