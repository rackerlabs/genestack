#!/bin/bash
# test-trove.sh — Exercise and validate every OpenStack Trove (DBaaS) feature.
#
# USAGE:
#   test-trove.sh [OPTIONS]
#
# OPTIONS:
#   -h, --help            Show this help
#   --os-cloud            Cloud config name
#   --no-cleanup          Keep all test resources after the run
#   --datastore DS        Datastore type to test against (default: mysql)
#   --ds-version VER      Datastore version number     (default: 8.4)
#   --flavor FLAVOR       Nova flavor for instances    (default: m1.small)
#   --volume-size GB      Instance volume size in GB   (default: 5)
#   --timeout SECS        Max seconds to wait for ACTIVE (default: 600)
#
# ENV:
#   OS_CLOUD              os-cloud name (default: default)
#   TEST_RESULTS_DIR      JUnit output directory (default: /tmp/test-results)
#
# EXIT CODES:
#   0  all tests passed
#   1  one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/openstack.sh"

# ── defaults ──────────────────────────────────────────────────────────────────
INSTANCE=""
DATASTORE="mysql"
DS_VERSION="8.4"
FLAVOR="m1.small"
VOL_SIZE="10"
INSTANCE_TIMEOUT=1200
CLEANUP="skip_net"
OS_CLOUD="${OS_CLOUD:-default}"
CUSTOMER_DIR="/home/ubuntu/customers"

RESIZE_FLAVOR=m1.medium

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)        sed -n '/^# USAGE:/,/^# EXIT CODES:/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        --os-cloud)       OS_CLOUD="${2:?}"; shift 2 ;;
        --cleanup)        CLEANUP="${2:?}"; shift 2 ;;
        --instance)       INSTANCE="${2:?}"; shift 2 ;;
        --datastore)      DATASTORE="${2:?}"; shift 2 ;;
        --ds-version)     DS_VERSION="${2:?}"; shift 2 ;;
        --flavor)         FLAVOR="${2:?}"; shift 2 ;;
        --resize-flavor)  RESIZE_FLAVOR="${2:?}"; shift 2 ;;
        --volume-size)    VOL_SIZE="${2:?}"; shift 2 ;;
        --timeout)        INSTANCE_TIMEOUT="${2:?}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── resource naming ───────────────────────────────────────────────────────────
TS="$(date +%s)"
PFX="test-trove-${TS}"

INST_PRIMARY="${PFX}-primary"
INST_REPLICA="${PFX}-replica"
INST_RESTORE="${PFX}-restore"
BACKUP_NAME="${PFX}-backup"
BACKUP_NAME_INCR="${BACKUP_NAME}-incr"
CONFIG_GROUP="${PFX}-config"
USER_NAME="test_user"
DB_NAME="testdb"
ROOT_PASS="root_pwd"
USER_PASS="test_pwd"
NET_NAME="${OS_CLOUD}-net"
SUBNET_NAME="${OS_CLOUD}-subnet"

CLEANUP_DONE=0

# ── helpers ───────────────────────────────────────────────────────────────────
db() { cd $CUSTOMER_DIR; openstack --os-cloud "$OS_CLOUD" database "$@" 2>&1; }
os() { cd $CUSTOMER_DIR; openstack --os-cloud "$OS_CLOUD" "$@" 2>&1; }

instance_status() { db instance show "$1" -f value -c status 2>/dev/null || echo "ERROR"; }
backup_status()   { db backup show   "$1" -f value -c status 2>/dev/null || echo "ERROR"; }

wait_for_instance() {
    # wait_for_instance <name_or_id> [timeout]
    local inst="$1" timeout="${2:-$INSTANCE_TIMEOUT}" elapsed=0
    while (( elapsed < timeout )); do
        local s; s=$(instance_status "$inst")
        case "$s" in
            ACTIVE)  echo "Instance $inst is ACTIVE after $elapsed seconds." >&2;
                     # wait for Operating Status to be HEALTHY
                     while (( elapsed < timeout )); do
                         local operating_status=$(db instance show "$inst" -f value -c "operating status")
                         if [[ "$operating_status" == "HEALTHY" ]]; then
                             echo "Instance $inst is HEALTHY after $elapsed seconds." >&2
                             return 0
                         fi
                         sleep 10; (( elapsed += 10 ));
                     done
                     ;;
            ERROR)   echo "Instance $inst entered ERROR state." >&2; return 1 ;;
            *)       sleep 10; (( elapsed += 10 )) ;;
        esac
    done
    echo "Timeout waiting $timeout seconds for instance $inst to become ACTIVE/HEALTHY." >&2
    return 1
}

wait_for_backup() {
    local bk="$1" timeout="${2:-300}" elapsed=0
    while (( elapsed < timeout )); do
        local s; s=$(backup_status "$bk")
        case "$s" in
            COMPLETED) echo "Backup $bk COMPLETED." >&2; return 0 ;;
            FAILED)    echo "Backup $bk FAILED." >&2; return 1 ;;
            *)         sleep 10; (( elapsed += 10 )) ;;
        esac
    done
    echo "Timeout waiting for backup $bk." >&2
    return 1
}

instance_id() { db instance show "$1" -f value -c id 2>/dev/null || true; }
backup_id()   { db backup show   "$1" -f value -c id 2>/dev/null || true; }
config_id()   { db configuration show "$1" -f value -c id 2>/dev/null || true; }

# ── cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    [[ "$CLEANUP_DONE" -eq 1 || "$CLEANUP" == "none" ]] && return
    echo ""
    echo "══ Cleaning up test resources ══"

    for inst in "$INST_RESTORE" "$INST_REPLICA" "$INST_PRIMARY"; do
        if [[ -n "$(instance_id "$inst")" ]]; then
            echo "  Deleting instance $inst ..."
            db instance delete "$inst" 2>&1 || true
        fi
    done

    # Wait for instances to disappear before deleting the backup
    local elapsed=0
    for inst in "$INST_RESTORE" "$INST_REPLICA" "$INST_PRIMARY"; do
        while [[ -n "$(instance_id "$inst")" ]] && (( elapsed < 120 )); do
            sleep 5; (( elapsed += 5 ))
        done
    done

    if [[ -n "$(backup_id "$BACKUP_NAME")" ]]; then
        echo "  Deleting backup $BACKUP_NAME ..."
        db backup delete "$BACKUP_NAME" 2>&1 || true
    fi

    if [[ -n "$(config_id "$CONFIG_GROUP")" ]]; then
        echo "  Deleting configuration group $CONFIG_GROUP ..."
        db configuration delete "$CONFIG_GROUP" 2>&1 || true
    fi

    echo "  Cleanup complete."
    CLEANUP_DONE=1
}

trap cleanup EXIT

# ════════════════════════════════════════════════════════════════════════════
# TEST FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

# ── prerequisite checks ───────────────────────────────────────────────────────
test_trove_service_available() {
    os catalog show database 2>&1 \
        || { echo "Trove (database) service not in catalog."; return 1; }
    echo "Trove service endpoint found in catalog."
}

test_trove_cli_available() {
    db instance list 2>&1 \
        || { echo "Trove CLI commands not functional."; return 1; }
    echo "Trove CLI is functional."
}

# ── datastore / version discovery ────────────────────────────────────────────
test_datastore_list() {
    local out; out=$(os datastore list -f value -c name)
    [[ -n "$out" ]] || { echo "No datastores found."; return 1; }
    echo "Available datastores:"
    echo "$out" | sed 's/^/  /'
}

test_datastore_version_list() {
    local out; out=$(os datastore version list "$DATASTORE" -f value -c name 2>&1)
    echo "$out" | grep -q "^${DS_VERSION}$" \
        || echo "Note: version ${DS_VERSION} not listed (may still be valid)."
    echo "Versions for $DATASTORE:"
    echo "$out" | sed 's/^/  /'
}

test_flavor_list() {
    local out; out=$(db flavor list -f value -c name 2>&1)
    [[ -n "$out" ]] || { echo "No Trove flavors found."; return 1; }
    echo "Trove flavors available:"
    echo "$out" | sed 's/^/  /'
}

test_flavor_show() {
    local out; out=$(db flavor show ${FLAVOR} 2>&1)
    echo "$out" | grep -vq "^No flavor" \
        || { echo "Flavor ${FLAVOR} not found."; return 1; }
    echo "Flavor ${FLAVOR} details:"
    echo "$out" | sed 's/^/  /'
}

test_limit_list() {
    local out; out=$(db limit list 2>&1)
    [[ -n "$out" ]] || { echo "No Trove limits found."; return 1; }
    echo "Trove limits:"
    echo "$out" | sed 's/^/  /'
}

test_quota_show() {
    local out; out=$(db quota show ${OS_CLOUD} 2>&1)
    [[ -n "$out" ]] || { echo "Quotas not found."; return 1; }
    echo "Quotas:"
    echo "$out" | sed 's/^/  /'
}

test_quota_update() {
    local out; out=$(db quota update ${OS_CLOUD} instances 20 2>&1)
    echo "$out" | grep -q "instance.*20" \
        || { echo "Quota not updated."; return 1; }
    echo "Quota details:"
    echo "$out" | sed 's/^/  /'
}

# ── instance lifecycle ────────────────────────────────────────────────────────
test_create_instance() {
    if [[ -n "${INSTANCE}" ]]; then
      echo "Using existing primary instance: $INST_PRIMARY ..."
    else
      echo "Creating primary instance: $INST_PRIMARY ..."
      db instance create "$INST_PRIMARY" \
          --flavor "$FLAVOR" \
          --size "$VOL_SIZE" \
          --volume-type Standard \
          --datastore "$DATASTORE" \
          --datastore-version-number "$DS_VERSION" \
          --databases "$DB_NAME" \
          --users "${USER_NAME}:${USER_PASS}" \
          --nic net-id=${NET_ID} \
          --allowed-cidr ${ALLOWED_CIDR} \
          || { echo "Failed to issue create command for $INST_PRIMARY."; return 1; }
    fi
    echo "Waiting for $INST_PRIMARY to become ACTIVE (timeout=${INSTANCE_TIMEOUT}s) ..."
    wait_for_instance "$INST_PRIMARY"
    echo "Instance $INST_PRIMARY is ACTIVE."
}

test_instance_list() {
    local out; out=$(db instance list -f value -c name)
    echo "$out" | grep -qF "$INST_PRIMARY" \
        || { echo "$INST_PRIMARY not found in instance list."; return 1; }
    echo "Instance list includes $INST_PRIMARY."
}

test_instance_show() {
    local out; out=$(db instance show "$INST_PRIMARY" -f value -c status)
    [[ "$out" == "ACTIVE" ]] \
        || { echo "Expected ACTIVE, got: $out"; return 1; }
    echo "Instance $INST_PRIMARY shows status ACTIVE."
}

test_resize_instance() {
    echo "Resizing instance $INST_PRIMARY flavor to $RESIZE_FLAVOR ..."
    db instance resize flavor "$INST_PRIMARY" "$RESIZE_FLAVOR" 2>&1 \
        || { echo "Resize flavor command failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Resize to $RESIZE_FLAVOR completed."
}

test_resize_volume() {
    local new_size=$(( VOL_SIZE + 1 ))
    echo "Resizing instance $INST_PRIMARY volume to ${new_size}GB ..."
    db instance resize volume "$INST_PRIMARY" "$new_size" 2>&1 \
        || { echo "Resize volume command failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Volume resize to ${new_size}GB completed."
}

# ── database & user management ────────────────────────────────────────────────
test_database_create() {
    local extra_db="${DB_NAME}2"
    echo "Creating database $extra_db on $INST_PRIMARY ..."
    db db create "$INST_PRIMARY" "$extra_db" 2>&1 \
        || { echo "Failed to create database $extra_db."; return 1; }
    echo "Database $extra_db created."
}

test_database_list() {
    local out; out=$(db db list "$INST_PRIMARY" -f value -c Name 2>&1)
    echo "$out" | grep -qF "$DB_NAME" \
        || { echo "$DB_NAME not found in database list."; return 1; }
    echo "Database list on $INST_PRIMARY:"
    echo "$out" | sed 's/^/  /'
}

test_database_delete() {
    local extra_db="${DB_NAME}2"
    echo "Deleting database $extra_db ..."
    db db delete "$INST_PRIMARY" "$extra_db" 2>&1 \
        || { echo "Failed to delete database $extra_db."; return 1; }
    echo "Database $extra_db deleted."
}

test_user_create() {
    local extra_user="${USER_NAME}2"
    echo "Creating user $extra_user on $INST_PRIMARY ..."
    db user create "$INST_PRIMARY" "$extra_user" "$USER_PASS" \
        --databases "$DB_NAME" 2>&1 \
        || { echo "Failed to create user $extra_user."; return 1; }
    echo "User $extra_user created."
}

test_user_list() {
    local out; out=$(db user list "$INST_PRIMARY" -f value -c Name 2>&1)
    echo "$out" | grep -qF "$USER_NAME" \
        || { echo "$USER_NAME not found in user list."; return 1; }
    echo "User list on $INST_PRIMARY:"
    echo "$out" | sed 's/^/  /'
}

test_user_show() {
    local out; out=$(db user show "$INST_PRIMARY" "$USER_NAME" 2>&1)
    echo "$out" | grep -qF "$USER_NAME" \
        || { echo "$USER_NAME not found in user details."; return 1; }
    echo "User details on $INST_PRIMARY:"
    echo "$out" | sed 's/^/  /'
}

test_user_update_attributes() {
    openstack database user update attributes $(instance_id "$INST_PRIMARY") "$USER_NAME" --new_name "${USER_NAME}_new"
    local out; out=$(db user list "$INST_PRIMARY" 2>&1)
    echo "$out" | grep -qF "${USER_NAME}_new" \
        || { echo "User attributes not updated."; return 1; }
    echo "User list on $INST_PRIMARY:"
    echo "$out" | sed 's/^/  /'
}

test_user_show_access() {
    local out; out=$(db user show access "$INST_PRIMARY" "$USER_NAME" 2>&1)
    echo "Access for $USER_NAME: $out"
}

test_user_grant_access() {
    local extra_db="${DB_NAME}2_access_test"
    db db create "$INST_PRIMARY" "$extra_db" 2>&1 2>&1 || true
    db user grant access "$INST_PRIMARY" "$USER_NAME" "$extra_db" 2>&1 \
        || { echo "Failed to grant access."; return 1; }
    echo "Grant access succeeded."
}

test_user_revoke_access() {
    local extra_db="${DB_NAME}2_access_test"
    db user revoke access "$INST_PRIMARY" "$USER_NAME" "$extra_db" 2>&1 \
        || { echo "Failed to revoke access."; return 1; }
    db db delete "$INST_PRIMARY" "$extra_db" 2>&1 2>&1 || true
    echo "Revoke access succeeded."
}

test_user_delete() {
    local extra_user="${USER_NAME}2"
    db user delete "$INST_PRIMARY" "$extra_user" 2>&1 \
        || { echo "Failed to delete user $extra_user."; return 1; }
    echo "User $extra_user deleted."
}

test_root_show() {
    local out; out=$(db root show "$INST_PRIMARY" 2>&1)
    echo "Root status: $out"
}

test_root_enable() {
    local out; out=$(db root enable "$INST_PRIMARY" 2>&1)
    echo "$out" | grep -qi "password\|root" \
        || { echo "Unexpected root enable output: $out"; return 1; }
    echo "Root access enabled on $INST_PRIMARY."
    echo "root enable output:\n${out}"
}

test_root_disable() {
    db root disable "$INST_PRIMARY" 2>&1
    local out; out=$(db root show "$INST_PRIMARY" 2>&1)
    echo "$out" | grep -q "is_root_enabled.*False" \
        || { echo "Unexpected root disable output: $out"; return 1; }
    echo "Root access disabled on $INST_PRIMARY."
    echo "root disable output:\n${out}"

}

# ── backup & restore ──────────────────────────────────────────────────────────
test_backup_create() {
    echo "Creating backup $BACKUP_NAME from $INST_PRIMARY ..."
    db backup create "$BACKUP_NAME" \
        --instance "$INST_PRIMARY" \
        --description "Trove feature test backup" 2>&1 \
        || { echo "Backup create command failed."; return 1; }
    echo "Waiting for backup $BACKUP_NAME to complete ..."
    wait_for_backup "$BACKUP_NAME"
}

test_backup_list() {
    local out; out=$(db backup list -f value -c name 2>&1)
    echo "$out" | grep -qF "$BACKUP_NAME" \
        || { echo "$BACKUP_NAME not found in backup list."; return 1; }
    echo "Backup list includes $BACKUP_NAME."
}

test_backup_list_instance() {
    local out; out=$(db backup list instance "$INST_PRIMARY" -f value -c name 2>&1)
    echo "$out" | grep -qF "$BACKUP_NAME" \
        || { echo "$BACKUP_NAME not found in backup list for instance."; return 1; }
    echo "Backup list for instance includes $BACKUP_NAME."
}

test_backup_show() {
    local status; status=$(backup_status "$BACKUP_NAME")
    [[ "$status" == "COMPLETED" ]] \
        || { echo "Expected COMPLETED, got: $status"; return 1; }
    echo "Backup $BACKUP_NAME shows status COMPLETED."
}

test_restore_from_backup() {
    echo "Creating restore instance $INST_RESTORE from backup $BACKUP_NAME ..."
    local bk_id; bk_id=$(backup_id "$BACKUP_NAME")
    [[ -n "$bk_id" ]] || { echo "Backup ID not found."; return 1; }
    db instance create "$INST_RESTORE" \
        --flavor "$FLAVOR" \
        --size "$VOL_SIZE" \
        --volume-type Standard \
        --datastore "$DATASTORE" \
        --datastore-version-number "$DS_VERSION" \
        --backup "$bk_id" \
        --nic net-id=${NET_ID} \
        --allowed-cidr ${ALLOWED_CIDR} \
        2>&1 \
        || { echo "Restore instance create command failed."; return 1; }
    echo "Waiting for $INST_RESTORE to become ACTIVE ..."
    wait_for_instance "$INST_RESTORE"
}

test_incremental_backup_create() {
    local bk_id; bk_id=$(backup_id "$BACKUP_NAME")
    echo "Creating incremental backup ${BACKUP_NAME_INCR} ..."
    db backup create "${BACKUP_NAME_INCR}" \
        --instance "$INST_PRIMARY" \
        --parent "$bk_id" \
        --description "Incremental backup test" 2>&1 \
        || { echo "Incremental backup create failed."; return 1; }
    wait_for_backup "${BACKUP_NAME_INCR}"
}

# ── configuration groups ──────────────────────────────────────────────────────
test_configuration_create() {
    echo "Creating configuration group $CONFIG_GROUP ..."
    db configuration create "$CONFIG_GROUP" \
        '{"max_connections": 100}' \
        --datastore "$DATASTORE" \
        --datastore-version "$DS_VERSION" \
        --description "Trove feature test config group" \
        2>&1 \
        || { echo "Configuration group create failed."; return 1; }
    echo "Configuration group $CONFIG_GROUP created."
}

test_configuration_list() {
    local out; out=$(db configuration list -f value -c name 2>&1)
    echo "$out" | grep -qF "$CONFIG_GROUP" \
        || { echo "$CONFIG_GROUP not found in configuration list."; return 1; }
    echo "Configuration list includes $CONFIG_GROUP."
}

test_configuration_show() {
    local out; out=$(db configuration show "$CONFIG_GROUP" 2>&1)
    echo "$out" | grep -qi "max_connections" \
        || { echo "Expected max_connections in config show output."; return 1; }
    echo "Configuration $CONFIG_GROUP shows expected parameter."
}

test_configuration_attach() {
    echo "Attaching configuration group $CONFIG_GROUP to $INST_PRIMARY ..."
    db configuration attach "$INST_PRIMARY" "$CONFIG_GROUP" 2>&1 \
        || { echo "Configuration attach failed."; return 1; }
    echo "Configuration group attached."
}

test_configuration_detach() {
    echo "Detaching configuration group from $INST_PRIMARY ..."
    db configuration detach "$INST_PRIMARY" 2>&1 \
        || { echo "Configuration detach failed."; return 1; }
    echo "Configuration group detached."
}

test_configuration_parameter_list() {
    local out; out=$(db configuration parameter list $DS_VERSION --datastore $DATASTORE 2>&1)
    [[ -n "$out" ]] \
        || { echo "No configuration default returned."; return 1; }
    echo "Configuration parameter list available (showing first 5):"
    echo "$out" | head -5 | sed 's/^/  /'
}

test_configuration_default() {
    local out; out=$(db configuration default $INST_PRIMARY 2>&1)
    [[ -n "$out" ]] \
        || { echo "No configuration default returned."; return 1; }
    echo "Configuration default available (showing first 5):"
    echo "$out" | head -5 | sed 's/^/  /'
}

test_configuration_instances() {
    local out; out=$(db configuration instances $CONFIG_GROUP 2>&1)
    [[ -n "$out" ]] \
        || { echo "No instances with $CONFIG_GROUP attached."; return 1; }
    echo "Instances w/ configuration $CONFIG_GROUP attached:"
    echo "$out" | head -5 | sed 's/^/  /'
}

test_configuration_parameter_set() {
    echo "Setting parameters for configuration group $CONFIG_GROUP ..."
    db configuration parameter set $(config_id "$CONFIG_GROUP") \
        '{"max_connections": 200}' \
        2>&1 \
        || { echo "Configuration group parameter set failed."; return 1; }
    echo "Configuration group $CONFIG_GROUP updated."
}

test_configuration_parameter_show() {
    local out; out=$(db configuration parameter show "$DS_VERSION" max_connections --datastore "$DATASTORE" 2>&1)
    [[ -n "$out" ]] \
        || { echo "Configuration parameter show failed."; return 1; }
    echo "Configuration parameter details:"
    echo "$out" | head -5 | sed 's/^/  /'
}

test_configuration_set() {
    echo "Setting configuration group $CONFIG_GROUP ..."
    db configuration set $(config_id "$CONFIG_GROUP") \
        '{"max_connections": 200}' \
        --name "${CONFIG_GROUP}_new"\
        --description "Trove feature test config group (new)" \
        2>&1 \
        || { echo "Configuration group parameter set failed."; return 1; }
    local out; out=$(db configuration show "${CONFIG_GROUP}_new" 2>&1)
    echo "$out" | grep -q "description.*Trove feature test config group (new)" \
        || { echo "Expected description not found for configuration."; return 1; }
    echo "Configuration details:"
    echo "$out" | head -5 | sed 's/^/  /'
}

# ── replication ───────────────────────────────────────────────────────────────
test_create_replica() {
    local primary_id; primary_id=$(instance_id "$INST_PRIMARY")
    [[ -n "$primary_id" ]] || { echo "Primary instance ID not found."; return 1; }
    echo "Creating replica $INST_REPLICA from $INST_PRIMARY ..."
    db instance create "$INST_REPLICA" \
        --replica-of "$primary_id" \
        --nic net-id=${NET_ID} \
        --allowed-cidr ${ALLOWED_CIDR} \
        2>&1 \
        || { echo "Replica create command failed."; return 1; }
    echo "Waiting for $INST_REPLICA to become ACTIVE ..."
    wait_for_instance "$INST_REPLICA"
}

test_replica_list() {
    local out; out=$(db instance list -f value -c name -c replica_of 2>&1)
    echo "$out" | grep -qF "$INST_REPLICA" \
        || { echo "$INST_REPLICA not found in instance list."; return 1; }
    echo "Replica $INST_REPLICA found in instance list."
}

test_promote_to_replica_source() {
    echo "Promoting $INST_REPLICA to replica source ..."
    db instance promote "$INST_REPLICA" 2>&1 \
        || { echo "Promote-to-replica-source failed."; return 1; }
    wait_for_instance "$INST_REPLICA"
    echo "Promotion of $INST_REPLICA complete."
}

test_eject_replica_source() {
    echo "Ejecting replica source from $INST_PRIMARY ..."
    db instance eject "$INST_PRIMARY" 2>&1 \
        || { echo "Eject-replica-source failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Replica source ejected from $INST_PRIMARY."
}

# ── instance actions ──────────────────────────────────────────────────────────
test_instance_reboot() {
    echo "Rebooting instance $INST_PRIMARY ..."
    local primary_id; primary_id=$(instance_id "$INST_PRIMARY")
    db instance reboot "$primary_id" 2>&1 \
        || { echo "Instance reboot failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Instance $INST_PRIMARY rebooted successfully."
}

test_instance_restart() {
    echo "Restarting instance $INST_PRIMARY ..."
    db instance restart "$INST_PRIMARY" 2>&1 \
        || { echo "Instance restart failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Instance $INST_PRIMARY restarted successfully."
}

test_instance_reset_status() {
    echo "Resetting instance $INST_PRIMARY status ..."
    db instance reset status "$INST_PRIMARY" 2>&1 \
        || { echo "Resetting instance status failed."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Instance $INST_PRIMARY status reset successfully."
}

test_instance_update() {
    echo "Updating instance  $INST_PRIMARY ..."
    db instance update $INST_PRIMARY \
        --allowed-cidr ${ALLOWED_CIDR} \
        --allowed-cidr "1.2.3.4/5" \
        2>&1 \
        || { echo "Updating instance failed."; return 1; }
    local out; out=$(db instance show "$INST_PRIMARY" -f value -c allowed_cidrs 2>&1)
    echo "$out" | grep -q "1.2.3.4/5" \
        || { echo "Expected allowed cidr not found for instance."; return 1; }
    echo "Instance details:"
    echo "$out" | head -5 | sed 's/^/  /'
}

test_log_list() {
    local out; out=$(db log list "$INST_PRIMARY" -f value -c name 2>&1)
    [[ -n "$out" ]] \
        || { echo "No logs returned from instance $INST_PRIMARY."; return 1; }
    echo "Available logs on $INST_PRIMARY:"
    echo "$out" | sed 's/^/  /'
}

test_log_enable_disable() {
    local first_log; first_log=$(db log list "$INST_PRIMARY" -f value -c name 2>/dev/null | head -1)
    [[ -n "$first_log" ]] || { echo "No logs available to enable/disable."; return 1; }
    echo "Enabling log $first_log on $INST_PRIMARY ..."
    db log set --enable "$INST_PRIMARY" "$first_log" 2>&1 \
        || { echo "Log enable failed (may require guest agent support)."; return 1; }
    echo "Disabling log $first_log on $INST_PRIMARY ..."
    db log set --disable "$INST_PRIMARY" "$first_log" 2>&1 \
        || { echo "Log disable failed."; return 1; }
    echo "Log enable/disable succeeded for $first_log."
}

test_instance_upgrade() {
    # Attempt an upgrade to the same version (safe no-op in most environments)
    echo "Testing instance upgrade API on $INST_PRIMARY ..."
    db instance upgrade "$INST_PRIMARY" "$DS_VERSION" 2>&1 \
        || { echo "Upgrade command returned non-zero (may not be supported for this version)."; return 1; }
    wait_for_instance "$INST_PRIMARY"
    echo "Instance upgrade API call succeeded."
}

test_detach_instance() {
    echo "Detaching replica $INST_REPLICA from primary ..."
    db instance detach "$INST_REPLICA" 2>&1 \
        || { echo "Detach instance failed."; return 1; }
    wait_for_instance "$INST_REPLICA"
    echo "Replica $INST_REPLICA detached."
}

# ── deletion ──────────────────────────────────────────────────────────────────
test_delete_restore_instance() {
    [[ -n $(db instance list 2>/dev/null | grep $INST_RESTORE) ]] \
        || { echo "$INST_RESTORE not found, skipping."; return 0; }
    echo "Deleting restore instance $INST_RESTORE ..."
    db instance delete "$INST_RESTORE" 2>&1 \
        || { echo "Failed to delete $INST_RESTORE."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_RESTORE) ]] && (( elapsed < 120 )); do
        echo sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    echo "Instance $INST_RESTORE deleted."
}

test_delete_replica_instance() {
    [[ -n $(db instance list 2>/dev/null | grep $INST_REPLICA) ]] \
        || { echo "$INST_REPLICA not found, skipping."; return 0; }
    echo "Deleting replica instance $INST_REPLICA ..."
    db instance delete "$INST_REPLICA" 2>&1 \
        || { echo "Failed to delete $INST_REPLICA."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_REPLICA) ]] && (( elapsed < 120 )); do
        echo sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    echo "Instance $INST_REPLICA deleted."
}

test_delete_backups() {
    [[ -n "$(backup_id "$BACKUP_NAME_INCR")" ]] \
        || { echo "$BACKUP_NAME_INCR not found, skipping."; return 0; }
    echo "Deleting backup $BACKUP_NAME_INCR ..."
    db backup delete "$BACKUP_NAME_INCR" 2>&1 \
        || { echo "Failed to delete backup $BACKUP_NAME_INCR."; return 1; }
    echo "Backup $BACKUP_NAME_INCR deleted."
    [[ -n "$(backup_id "$BACKUP_NAME")" ]] \
        || { echo "$BACKUP_NAME not found, skipping."; return 0; }
    echo "Deleting backup $BACKUP_NAME ..."
    db backup delete "$BACKUP_NAME" 2>&1 \
        || { echo "Failed to delete backup $BACKUP_NAME."; return 1; }
    echo "Backup $BACKUP_NAME deleted."
}

test_delete_configuration() {
    [[ -n "$(config_id "$CONFIG_GROUP")" ]] \
        || { echo "$CONFIG_GROUP not found, skipping."; return 0; }
    echo "Deleting configuration group $CONFIG_GROUP ..."
    db configuration delete "$CONFIG_GROUP" 2>&1 \
        || { echo "Failed to delete configuration group $CONFIG_GROUP."; return 1; }
    echo "Configuration group $CONFIG_GROUP deleted."
}

test_force_delete_primary_instance() {
    [[ -n $(db instance list 2>/dev/null | grep $INST_PRIMARY) ]] \
        || { echo "$INST_PRIMARY not found, skipping."; return 0; }
    echo "Deleting primary instance $INST_PRIMARY ..."
    db instance force delete "$INST_PRIMARY" 2>&1 \
        || { echo "Failed to delete $INST_PRIMARY."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_PRIMARY) ]] && (( elapsed < 180 )); do
        echo sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    echo "Instance $INST_PRIMARY deleted."
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════
main() {
    TEST_SUITE_NAME="trove-feature-tests"
    init_tests "${TEST_SUITE_NAME}"

    if ! source_credentials; then
        echo "ERROR: Failed to source OpenStack credentials"
        exit 1
    fi

    # ── customer network setup
    /opt/genestack/scripts/tests/lib/manage-test-tenants.sh create

    if [[ -n "${INSTANCE}" ]]; then
        openstack --os-cloud "$OS_CLOUD" database instance show ${INSTANCE} -f value -c name
        INST_NAME=$(cd $CUSTOMER_DIR; openstack --os-cloud "$OS_CLOUD" database instance show ${INSTANCE} -f value -c name 2>/dev/null || true)
        if [[ -z "$INST_NAME" ]]; then
            echo "===> ERROR: $INSTANCE not found" && exit 99
        else
            export INST_PRIMARY=$INST_NAME
            echo "INST_PRIMARY: $INST_PRIMARY"
        fi
    fi

    echo ""
    echo "════════════════════════════════════════════════════"
    echo "  Trove Feature Validation Suite"
    echo "════════════════════════════════════════════════════"
    echo "  Datastore:   $DATASTORE $DS_VERSION"
    echo "  Flavor:      $FLAVOR"
    echo "  Volume:      ${VOL_SIZE}GB"
    echo "  Network:     ${NET_NAME}"
    echo "  Prefix:      $PFX"
    echo "  Cleanup:     ${CLEANUP}"
    echo "════════════════════════════════════════════════════"
    echo ""

    export NET_ID=$(os network show ${NET_NAME} -f value -c id)
    export ALLOWED_CIDR=$(os subnet show ${SUBNET_NAME} -f value -c cidr)

    # ── prerequisites
    run_test "trove_service_available"      test_trove_service_available
    run_test "trove_cli_available"          test_trove_cli_available

    # ── discovery
    run_test "datastore_list"               test_datastore_list
    run_test "datastore_version_list"       test_datastore_version_list
    run_test "flavor_list"                  test_flavor_list
    run_test "flavor_show"                  test_flavor_show
    run_test "limit_list"                   test_limit_list
    run_test "quota_show"                   test_quota_show
    run_test "quota_update"                 test_quota_update

    # ── primary instance lifecycle
    run_test "create_instance"              test_create_instance
    run_test "instance_list"                test_instance_list
    run_test "instance_show"                test_instance_show

    # ── database & user management (requires ACTIVE instance)
    run_test "database_create"              test_database_create
    run_test "database_list"                test_database_list
    run_test "database_delete"              test_database_delete
    run_test "user_create"                  test_user_create
    run_test "user_list"                    test_user_list
    run_test "user_show"                    test_user_show
    run_test "user_show_access"             test_user_show_access
    run_test "user_grant_access"            test_user_grant_access
    run_test "user_revoke_access"           test_user_revoke_access
    run_test "user_update_attributes"       test_user_update_attributes
    run_test "user_delete"                  test_user_delete
    run_test "root_show"                    test_root_show
    run_test "root_enable"                  test_root_enable
    run_test "root_disable"                 test_root_disable

    # ── configuration groups
    run_test "configuration_parameter_list"   test_configuration_parameter_list
    run_test "configuration_default"          test_configuration_default
    run_test "configuration_create"           test_configuration_create
    run_test "configuration_list"             test_configuration_list
    run_test "configuration_show"             test_configuration_show
    run_test "configuration_attach"           test_configuration_attach
    run_test "configuration_instances"        test_configuration_instances
    run_test "configuration_detach"           test_configuration_detach
    run_test "configuration_default"          test_configuration_default
    run_test "configuration_parameter_set"    test_configuration_parameter_set
    run_test "configuration_parameter_show"   test_configuration_parameter_show
    run_test "configuration_set"              test_configuration_set

    # ── instance actions
    run_test "instance_reboot"              test_instance_reboot
    run_test "instance_restart"             test_instance_restart
    run_test "instance_update"              test_instance_update
    run_test "instance_reset_status"        test_instance_reset_status
    run_test "resize_instance"              test_resize_instance
    run_test "resize_volume"                test_resize_volume
#    run_test "log_list"                     test_log_list
#    run_test "log_enable_disable"           test_log_enable_disable

    # ── backup & restore
    run_test "backup_create"                test_backup_create
    run_test "backup_list"                  test_backup_list
    run_test "backup_list_instance"         test_backup_list_instance
    run_test "backup_show"                  test_backup_show
    run_test "incremental_backup_create"    test_incremental_backup_create
    run_test "restore_from_backup"          test_restore_from_backup

    # ── replication
    run_test "create_replica"               test_create_replica
    run_test "replica_list"                 test_replica_list
    run_test "detach_instance"              test_detach_instance

    # ── deletion (ordered: restore → replica → backup → config → primary)
    if [[ "$CLEANUP" != "none" ]]; then
        run_test "delete_restore_instance"      test_delete_restore_instance
        run_test "delete_replica_instance"      test_delete_replica_instance
        run_test "delete_backups"               test_delete_backups
        run_test "delete_configuration"         test_delete_configuration
        run_test "delete_primary_instance"      test_force_delete_primary_instance
    fi

    CLEANUP_DONE=1   # All resources explicitly deleted above
    finalize_tests

    # ── customer network teardown
    if [[ "$CLEANUP" != "none" && "$CLEANUP" != "skip_net" ]]; then
        /opt/genestack/scripts/tests/lib/manage-test-tenants.sh destroy
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
