#!/bin/bash
# test-trove.sh — Exercise and validate every OpenStack Trove (DBaaS) feature.
#
# USAGE:
#   test-trove.sh [OPTIONS]
#
# OPTIONS:
#   -h, --help              Show this help
#   --os-cloud              Cloud config name (default: acme-corp)
#   --cleanup               Cleanup test resources after the run
#                               all      - cleanup DB resources and network setup
#                               skip_net - cleanup only DB resources (default)
#                               none     - do not cleanup any DB resources or network setup
#   --instance              ID of DB instance to use for primary test instance
#   --datastore DS          Datastore type to test against (default: mysql)
#   --ds-version VER        Datastore version number     (default: 8.4)
#   --flavor FLAVOR         Nova flavor for instances    (default: db.2.2)
#   --resize-flavor FLAVOR  Nova flavor for instance resize    (default: m1.medium)
#   --volume-size GB        Instance volume size in GB   (default: 10)
#   --timeout SECS          Max seconds to wait for ACTIVE (default: 600)
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
FLAVOR="db.2.2"
VOL_SIZE="10"
INSTANCE_TIMEOUT=600
CLEANUP="skip_net"
OS_CLOUD="${OS_CLOUD:-acme-corp}"
CUSTOMER_DIR="/home/ubuntu/customers"

RESIZE_FLAVOR=db.4.4

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
        *) echo -e "\033[31m ERROR: unknown argument: $1 \033[0m" >&2; sed -n '/^# USAGE:/,/^# EXIT CODES:/p' "$0" | sed 's/^# \?//'; exit 1 ;;
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

HEADER='\033[95m'
BLUE='\033[94m'
INFO='\033[96m'
SUCCESS='\033[92m'
WARN='\033[93m'
FAIL='\033[31m'
ENDC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

log_msg() {
    color=$1
    msg=$2
    add_timestamp="${3:-true}"

    # during the test run, messages to stdout are only captured in the test results file, whereas
    # messages to stderr are printed to the screen. The test results file has it's own color-coding
    # so escape sequences are not processed and clutter the content. So, only include escape
    # sequences for stderr output.

    local stdout_msg=""
    if [[ -n "$add_timestamp" && "$add_timestamp" == "true" ]]; then
        stdout_msg+="[$(date "+%Y-%m-%d %H:%M:%S")] "
    fi
    stdout_msg+=$msg

    local stderr_msg=$color
    stderr_msg+=$stdout_msg
    stderr_msg+=$ENDC

    echo -e "$stdout_msg"
    echo -e "$stderr_msg" >&2
}

# ── helpers ───────────────────────────────────────────────────────────────────
db() { cd $CUSTOMER_DIR; openstack --os-cloud "$OS_CLOUD" database "$@" 2>&1; }
os() { cd $CUSTOMER_DIR; openstack --os-cloud "$OS_CLOUD" "$@" 2>&1; }

instance_status() { db instance show "$1" -f value -c status 2>/dev/null; }
backup_status()   { db backup show   "$1" -f value -c status 2>/dev/null; }

wait_for_instance() {
    # wait_for_instance <name_or_id> [timeout]
    local inst="$1" timeout="${2:-$INSTANCE_TIMEOUT}" elapsed=0
    while (( elapsed < timeout )); do
        local s; s=$(instance_status "$inst")
        case "$s" in
            ACTIVE)  log_msg "$INFO" "$s" ; log_msg "$INFO" "Instance $inst is ACTIVE after $elapsed seconds.";
                     # wait for Operating Status to be HEALTHY
                     while (( elapsed < timeout )); do
                         local operating_status=$(db instance show "$inst" -f value -c "operating status")
                         if [[ "$operating_status" == "HEALTHY" ]]; then
                             log_msg "$INFO" "$s/$operating_status" ; log_msg "$INFO" "Instance $inst is HEALTHY after $elapsed seconds."
                             return 0
                         fi
                         log_msg "$INFO" "$s/$operating_status ..." ; sleep 10; (( elapsed += 10 ));
                     done
                     ;;
            ERROR)   log_msg "$FAIL" "$s" ; log_msg "$FAIL" "Instance $inst entered ERROR state."; return 1 ;;
            *)       log_msg "$INFO" "$s ..." ; sleep 10; (( elapsed += 10 )) ;;
        esac
    done
    log_msg "$FAIL" "Timeout waiting $timeout seconds for instance $inst to become ACTIVE/HEALTHY."
    return 1
}

wait_for_backup() {
    local bk="$1" timeout="${2:-300}" elapsed=0
    while (( elapsed < timeout )); do
        local s; s=$(backup_status "$bk")
        case "$s" in
            COMPLETED) log_msg "$INFO" "$s" ; log_msg "$INFO" "Backup $bk COMPLETED."; return 0 ;;
            FAILED)    log_msg "$INFO" "$s" ; log_msg "$FAIL" "Backup $bk FAILED."; return 1 ;;
            *)         log_msg "$INFO" "$s ..." ; sleep 10; (( elapsed += 10 )) ;;
        esac
    done
    log_msg "$FAIL" "Timeout waiting for backup $bk."
    return 1
}

instance_id() { db instance show "$1" -f value -c id 2>/dev/null || true; }
backup_id()   { db backup show   "$1" -f value -c id 2>/dev/null || true; }
config_id()   { db configuration show "$1" -f value -c id 2>/dev/null || true; }

# ── cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    # dump test results if they haven't been dumped already
    [[ "$CLEANUP_DONE" -eq 1 || "$CLEANUP" == "none" ]] && return

    log_msg "$INFO" ""
    log_msg "$HEADER" "══ Cleaning up test resources ══"

    for inst in "$INST_RESTORE" "$INST_REPLICA" "$INST_PRIMARY"; do
        if [[ -n "$(instance_id "$inst")" ]]; then
            log_msg "$INFO" "  Deleting instance $inst ..."
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
        log_msg "$INFO" "  Deleting backup $BACKUP_NAME ..."
        db backup delete "$BACKUP_NAME" 2>&1 || true
    fi

    if [[ -n "$(config_id "$CONFIG_GROUP")" ]]; then
        log_msg "$INFO" "  Deleting configuration group $CONFIG_GROUP ..."
        db configuration delete "$CONFIG_GROUP" 2>&1 || true
    fi

    log_msg "$SUCCESS" "  Cleanup complete."
    CLEANUP_DONE=1
}

trap cleanup EXIT

# ════════════════════════════════════════════════════════════════════════════
# TEST FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

# ── prerequisite checks ───────────────────────────────────────────────────────
test_trove_service_available() {
    log_msg "$INFO" "" false
    os catalog show database 2>&1 \
        || { log_msg "$FAIL" "Trove (database) service not in catalog."; return 1; }
    log_msg "$INFO" "Trove service endpoint found in catalog."
}

test_trove_cli_available() {
    log_msg "$INFO" "" false
    db instance list 2>&1 \
        || { log_msg "$FAIL" "Trove CLI commands not functional."; return 1; }
    log_msg "$INFO" "Trove CLI is functional."
}

# ── datastore / version discovery ────────────────────────────────────────────
test_datastore_list() {
    log_msg "$INFO" "" false
    local out; out=$(os datastore list -f value -c name)
    log_msg "$INFO" "Available datastores:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    [[ -n "$out" ]] || { log_msg "$FAIL" "No datastores found."; return 1; }
}

test_datastore_version_list() {
    log_msg "$INFO" "" false
    local out; out=$(os datastore version list "$DATASTORE" -f value -c name 2>&1)
    log_msg "$INFO" "Versions for $DATASTORE:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -q "^${DS_VERSION}$" \
        || log_msg "$WARN" "Note: version ${DS_VERSION} not listed (may still be valid)."
}

test_flavor_list() {
    log_msg "$INFO" "" false
    local out; out=$(db flavor list -f value -c name 2>&1)
    log_msg "$INFO" "Trove flavors available:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    [[ -n "$out" ]] || { log_msg "$FAIL" "No Trove flavors found."; return 1; }
}

test_flavor_show() {
    log_msg "$INFO" "" false
    local out; out=$(db flavor show ${FLAVOR} 2>&1)
    log_msg "$INFO" "Flavor ${FLAVOR} details:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -vq "^No flavor" \
        || { log_msg "$FAIL" "Flavor ${FLAVOR} not found."; return 1; }
}

test_limit_list() {
    log_msg "$INFO" "" false
    local out; out=$(db limit list 2>&1)
    log_msg "$INFO" "Trove limits:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    [[ -n "$out" ]] || { log_msg "$FAIL" "No Trove limits found."; return 1; }
}

test_quota_show() {
    log_msg "$INFO" "" false
    local out; out=$(db quota show ${OS_CLOUD} 2>&1)
    log_msg "$INFO" "Quotas:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    [[ -n "$out" ]] || { log_msg "$FAIL" "Quotas not found."; return 1; }
}

test_quota_update() {
    log_msg "$INFO" "" false
    local out; out=$(db quota update ${OS_CLOUD} instances 20 2>&1)
    log_msg "$INFO" "Quota details:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -q "instance.*20" \
        || { log_msg "$FAIL" "Quota not updated."; return 1; }
}

# ── instance lifecycle ────────────────────────────────────────────────────────
test_create_instance() {
    log_msg "$INFO" "" false
    if [[ -n "${INSTANCE}" ]]; then
      log_msg "$INFO" "Using existing primary instance: $INST_PRIMARY ..."
    else
      log_msg "$INFO" "Creating primary instance: $INST_PRIMARY ..."
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
          || { log_msg "$FAIL" "Failed to issue create command for $INST_PRIMARY."; return 1; }
    fi
    log_msg "$INFO" "Waiting for $INST_PRIMARY to be ready (timeout=${INSTANCE_TIMEOUT}s) ..."
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY is ready."
}

test_instance_list() {
    log_msg "$INFO" "" false
    local out; out=$(db instance list -f value -c name)
    log_msg "$INFO" "Instance list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$INST_PRIMARY" \
        || { log_msg "$FAIL" "$INST_PRIMARY not found in instance list."; return 1; }
    log_msg "$INFO" "Instance list includes $INST_PRIMARY."
}

test_instance_show() {
    log_msg "$INFO" "" false
    local out; out=$(db instance show "$INST_PRIMARY" -f value -c status)
    [[ "$out" == "ACTIVE" ]] \
        || { log_msg "$FAIL" "Expected ACTIVE, got: $out"; return 1; }
    log_msg "$INFO" "Instance $INST_PRIMARY shows status ACTIVE."
}

test_resize_instance() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Resizing instance $INST_PRIMARY flavor to $RESIZE_FLAVOR ..."
    db instance resize flavor "$INST_PRIMARY" "$RESIZE_FLAVOR" 2>&1 \
        || { log_msg "$FAIL" "Resize flavor command failed."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Resize to $RESIZE_FLAVOR completed."
}

test_resize_volume() {
    log_msg "$INFO" "" false
    local new_size=$(( VOL_SIZE + 1 ))
    log_msg "$INFO" "Resizing instance $INST_PRIMARY volume to ${new_size}GB ..."
    db instance resize volume "$INST_PRIMARY" "$new_size" 2>&1 \
        || { log_msg "$FAIL" "Resize volume command failed."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Volume resize to ${new_size}GB completed."
}

# ── database & user management ────────────────────────────────────────────────
test_database_create() {
    log_msg "$INFO" "" false
    local extra_db="${DB_NAME}2"
    log_msg "$INFO" "Creating database $extra_db on $INST_PRIMARY ..."
    db db create "$INST_PRIMARY" "$extra_db" 2>&1 \
        || { log_msg "$FAIL" "Failed to create database $extra_db."; return 1; }
    log_msg "$INFO" "Database $extra_db created."
}

test_database_list() {
    log_msg "$INFO" "" false
    local out; out=$(db db list "$INST_PRIMARY" -f value -c Name 2>&1)
    log_msg "$INFO" "Database list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$DB_NAME" \
        || { log_msg "$FAIL" "$DB_NAME not found in database list."; return 1; }
}

test_database_delete() {
    log_msg "$INFO" "" false
    local extra_db="${DB_NAME}2"
    log_msg "$INFO" "Deleting database $extra_db ..."
    db db delete "$INST_PRIMARY" "$extra_db" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete database $extra_db."; return 1; }
    log_msg "$INFO" "Database $extra_db deleted."
}

test_user_create() {
    log_msg "$INFO" "" false
    local extra_user="${USER_NAME}2"
    log_msg "$INFO" "Creating user $extra_user on $INST_PRIMARY ..."
    db user create "$INST_PRIMARY" "$extra_user" "$USER_PASS" \
        --databases "$DB_NAME" 2>&1 \
        || { log_msg "$FOLD $FAIL" "Failed to create user $extra_user."; return 1; }
    log_msg "$INFO" "User $extra_user created."
}

test_user_list() {
    log_msg "$INFO" "" false
    local out; out=$(db user list "$INST_PRIMARY" -f value -c Name 2>&1)
    log_msg "$INFO" "User list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$USER_NAME" \
        || { log_msg "$FAIL" "$USER_NAME not found in user list."; return 1; }
}

test_user_show() {
    log_msg "$INFO" "" false
    local out; out=$(db user show "$INST_PRIMARY" "$USER_NAME" 2>&1)
    log_msg "$INFO" "User details on $INST_PRIMARY:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$USER_NAME" \
        || { log_msg "$FAIL" "$USER_NAME not found in user details."; return 1; }
}

test_user_update_attributes() {
    log_msg "$INFO" "" false
    openstack database user update attributes $(instance_id "$INST_PRIMARY") "$USER_NAME" --new_name "${USER_NAME}_new"
    local out; out=$(db user list "$INST_PRIMARY" 2>&1)
    log_msg "$INFO" "User list on $INST_PRIMARY:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "${USER_NAME}_new" \
        || { echo "User attributes not updated."; return 1; }
}

test_user_show_access() {
    log_msg "$INFO" "" false
    local out; out=$(db user show access "$INST_PRIMARY" "$USER_NAME" 2>&1)
    log_msg "$INFO" "Access for $USER_NAME: $out"
}

test_user_grant_access() {
    log_msg "$INFO" "" false
    local extra_db="${DB_NAME}2_access_test"
    log_msg "$INFO" "Granting access to $extra_db for $USER_NAME on $INST_PRIMARY"
    db db create "$INST_PRIMARY" "$extra_db" 2>&1 2>&1 || true
    db user grant access "$INST_PRIMARY" "$USER_NAME" "$extra_db" 2>&1 \
        || { log_msg "$FAIL" "Failed to grant access."; return 1; }
}

test_user_revoke_access() {
    log_msg "$INFO" "" false
    local extra_db="${DB_NAME}2_access_test"
    log_msg "$INFO" "Revoking access to $extra_db for $USER_NAME on $INST_PRIMARY"
    db user revoke access "$INST_PRIMARY" "$USER_NAME" "$extra_db" 2>&1 \
        || { log_msg "$FAIL" "Failed to revoke access."; return 1; }
    db db delete "$INST_PRIMARY" "$extra_db" 2>&1 2>&1 || true
}

test_user_delete() {
    log_msg "$INFO" "" false
    local extra_user="${USER_NAME}2"
    log_msg "$INFO" "Deleting user $extra_user"
    db user delete "$INST_PRIMARY" "$extra_user" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete user $extra_user."; return 1; }
}

test_root_show() {
    log_msg "$INFO" "" false
    local out; out=$(db root show "$INST_PRIMARY" 2>&1)
    log_msg "$INFO" "Root status: $out"
}

test_root_enable() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Enabling root access on $INST_PRIMARY."
    local out; out=$(db root enable "$INST_PRIMARY" 2>&1)
    log_msg "$INFO" "root enable output:"
    log_msg "$INFO" "${out}"
    echo "$out" | grep -qi "password\|root" \
        || { log_msg "$FAIL" "Unexpected root enable output: $out"; return 1; }
}

test_root_disable() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Disabling root access on $INST_PRIMARY."
    db root disable "$INST_PRIMARY" 2>&1
    local out; out=$(db root show "$INST_PRIMARY" 2>&1)
    log_msg "$INFO" "root disable output:"
    log_msg "$INFO" "${out}"
    echo "$out" | grep -q "is_root_enabled.*False" \
        || { log_msg "$FAIL" "Unexpected root disable output: $out"; return 1; }

}

# ── backup & restore ──────────────────────────────────────────────────────────
test_backup_execution_delete() {
    log_msg "$INFO" "" false
    log_msg "$WARN" "NOT IMPLEMENTED"
}

test_backup_strategy_create() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Creating backup strategy for $INST_PRIMARY ..."
    db backup strategy create \
        --instance "$(instance_id "$INST_PRIMARY")" \
        --swift-container "BACKUPS" 2>&1 \
        || { log_msg "$FAIL" "Backup strategy create command failed."; return 1; }
}

test_backup_strategy_list() {
    log_msg "$INFO" "" false
    local primary_id=$(instance_id "$INST_PRIMARY")
    log_msg "$INFO" "Listing backup strategy for $INST_PRIMARY ($primary_id) ..."
    local out; out=$(db backup strategy list --instance-id $primary_id 2>&1)
    log_msg "$INFO" "Backup Strategy list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF $primary_id \
        || { log_msg "$FAIL" "$INST_PRIMARY ($primary_id) not found in backup strategy list."; return 1; }
    log_msg "$INFO" "Backup Strategy list includes $INST_PRIMARY."
}

test_backup_strategy_delete() {
    log_msg "$INFO" "" false
    local primary_id=$(instance_id "$INST_PRIMARY")
    log_msg "$INFO" "Deleting backup strategy for instance $INST_PRIMARY ($primary_id) ..."
    db backup strategy delete --instance-id $primary_id 2>&1 \
        || { log_msg "$FAIL" "Failed to delete backup strategy for instance $INST_PRIMARY ($primary_id); command failed"; return 1; }
    local out; out=$(db backup strategy list --instance-id $primary_id 2>&1)
    [[ -z "$out" ]] \
        || { log_msg "$FAIL" "Failed to delete backup strategy for instance $INST_PRIMARY ($primary_id); backup strategy list not empty"; return 1; }
}

test_backup_create() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Creating backup $BACKUP_NAME from $INST_PRIMARY ..."
    db backup create "$BACKUP_NAME" \
        --instance "$INST_PRIMARY" \
        --description "Trove feature test backup" 2>&1 \
        || { log_msg "$FAIL" "Backup create command failed."; return 1; }
    log_msg "$INFO" "Waiting for backup $BACKUP_NAME to complete ..."
    wait_for_backup "$BACKUP_NAME" || return 1
    log_msg "$INFO" "Backup $BACKUP_NAME completed."
}

test_backup_list() {
    log_msg "$INFO" "" false
    local out; out=$(db backup list -f value -c name 2>&1)
    log_msg "$INFO" "Backup list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$BACKUP_NAME" \
        || { log_msg "$FAIL" "$BACKUP_NAME not found in backup list."; return 1; }
    log_msg "$INFO" "Backup list includes $BACKUP_NAME."
}

test_backup_list_instance() {
    log_msg "$INFO" "" false
    local out; out=$(db backup list instance "$INST_PRIMARY" -f value -c name 2>&1)
    log_msg "$INFO" "Backup list for instance $INST_PRIMARY:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$BACKUP_NAME" \
        || { log_msg "$FAIL" "$BACKUP_NAME not found in backup list for instance."; return 1; }
    log_msg "$INFO" "Backup list for instance includes $BACKUP_NAME."
}

test_backup_show() {
    log_msg "$INFO" "" false
    local status; status=$(backup_status "$BACKUP_NAME")
    log_msg "$INFO" "Showing backup status for $BACKUP_NAME"
    [[ "$status" == "COMPLETED" ]] \
        || { log_msg "$FAIL" "Expected COMPLETED, got: $status"; return 1; }
    log_msg "$INFO" "Backup $BACKUP_NAME shows status COMPLETED."
}

test_restore_from_backup() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Creating restore instance $INST_RESTORE from backup $BACKUP_NAME ..."
    local bk_id; bk_id=$(backup_id "$BACKUP_NAME")
    [[ -n "$bk_id" ]] || { log_msg "$FAIL" "Backup ID not found."; return 1; }
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
        || { log_msg "$FAIL" "Restore instance create command failed."; return 1; }
    log_msg "$INFO" "Waiting for $INST_RESTORE to be ready ..."
    wait_for_instance "$INST_RESTORE" || return 1
    log_msg "$INFO" "Instance $INST_RESTORE is ready."
}

test_incremental_backup_create() {
    log_msg "$INFO" "" false
    local bk_id; bk_id=$(backup_id "$BACKUP_NAME")
    log_msg "$INFO" "Creating incremental backup ${BACKUP_NAME_INCR} ..."
    db backup create "${BACKUP_NAME_INCR}" \
        --instance "$INST_PRIMARY" \
        --parent "$bk_id" \
        --description "Incremental backup test" 2>&1 \
        || { log_msg "$FAIL" "Incremental backup create failed."; return 1; }
    log_msg "$INFO" "Waiting for backup $BACKUP_NAME_INCR to complete ..."
    wait_for_backup "${BACKUP_NAME_INCR}" || return 1
    log_msg "$INFO" "Backup ${BACKUP_NAME_INCR} completed."
}

# ── configuration groups ──────────────────────────────────────────────────────
test_configuration_create() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Creating configuration group $CONFIG_GROUP ..."
    db configuration create "$CONFIG_GROUP" \
        '{"max_connections": 100}' \
        --datastore "$DATASTORE" \
        --datastore-version "$DS_VERSION" \
        --description "Trove feature test config group" \
        2>&1 \
        || { log_msg "$FAIL" "Configuration group create failed."; return 1; }
}

test_configuration_list() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration list -f value -c name 2>&1)
    log_msg "$INFO" "Configuration list:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    echo "$out" | grep -qF "$CONFIG_GROUP" \
        || { log_msg "$FAIL" "$CONFIG_GROUP not found in configuration list."; return 1; }
    log_msg "$INFO" "Configuration list includes $CONFIG_GROUP."
}

test_configuration_show() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration show "$CONFIG_GROUP" 2>&1)
    log_msg "$INFO" "Configuration details:"
    log_msg "$INFO" "$out"
    echo "$out" | grep -qi "max_connections" \
        || { log_msg "$FAIL" "Expected max_connections in config show output."; return 1; }
    log_msg "$INFO" "Configuration $CONFIG_GROUP shows expected parameter."
}

test_configuration_attach() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Attaching configuration group $CONFIG_GROUP to $INST_PRIMARY ..."
    db configuration attach "$INST_PRIMARY" "$CONFIG_GROUP" 2>&1 \
        || { log_msg "$FAIL" "Configuration attach failed."; return 1; }
}

test_configuration_detach() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Detaching configuration group from $INST_PRIMARY ..."
    db configuration detach "$INST_PRIMARY" 2>&1 \
        || { log_msg "$FAIL" "Configuration detach failed."; return 1; }
}

test_configuration_parameter_list() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration parameter list $DS_VERSION --datastore $DATASTORE 2>&1)
    log_msg "$INFO" "Configuration parameter list available (showing first 5):"
    log_msg "$INFO" "$out" | head -5 | sed 's/^/  /'
    [[ -n "$out" ]] \
        || { log_msg "$FAIL" "No configuration default returned."; return 1; }
}

test_configuration_default() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration default $INST_PRIMARY 2>&1)
    log_msg "$INFO" "Configuration default available (showing first 5):"
    log_msg "$INFO" "$out" | head -5 | sed 's/^/  /'
    [[ -n "$out" ]] \
        || { log_msg "$FAIL" "No configuration default returned."; return 1; }
}

test_configuration_instances() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration instances $CONFIG_GROUP 2>&1)
    log_msg "$INFO" "Instances w/ configuration $CONFIG_GROUP attached:"
    log_msg "$INFO" "$out" | head -5 | sed 's/^/  /'
    [[ -n "$out" ]] \
        || { log_msg "$FAIL" "No instances with $CONFIG_GROUP attached."; return 1; }
}

test_configuration_parameter_set() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Setting parameters for configuration group $CONFIG_GROUP ..."
    db configuration parameter set $(config_id "$CONFIG_GROUP") \
        '{"max_connections": 200}' \
        2>&1 \
        || { log_msg "$FAIL" "Configuration group parameter set failed."; return 1; }
}

test_configuration_parameter_show() {
    log_msg "$INFO" "" false
    local out; out=$(db configuration parameter show "$DS_VERSION" max_connections --datastore "$DATASTORE" 2>&1)
    log_msg "$INFO" "Configuration parameter details:"
    log_msg "$INFO" "$out" | head -5 | sed 's/^/  /'
    [[ -n "$out" ]] \
        || { log_msg "$FAIL" "Configuration parameter show failed."; return 1; }
}

test_configuration_set() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Setting configuration group $CONFIG_GROUP ..."
    db configuration set $(config_id "$CONFIG_GROUP") \
        '{"max_connections": 200}' \
        --name "${CONFIG_GROUP}_new"\
        --description "Trove feature test config group (new)" \
        2>&1 \
        || { log_msg "$FAIL" "Configuration group set failed."; return 1; }
    local out; out=$(db configuration show "${CONFIG_GROUP}_new" 2>&1)
    echo "$out" | grep -q "description.*Trove feature test config group (new)" \
        || { log_msg "$FAIL" "Expected description not found for configuration."; return 1; }
    log_msg "$INFO" "Configuration details:"
    log_msg "$INFO" "$out" | sed 's/^/  /'

    # Undo name change
    db configuration set $(config_id "${CONFIG_GROUP}_new") \
        '{"max_connections": 200}' \
        --name "${CONFIG_GROUP}"\
        2>&1 \
        || { log_msg "$FAIL" "Configuration group set to undo name change failed."; return 1; }
}

# ── replication ───────────────────────────────────────────────────────────────
test_create_replica() {
    log_msg "$INFO" "" false
    local primary_id; primary_id=$(instance_id "$INST_PRIMARY")
    [[ -n "$primary_id" ]] || { log_msg "$FAIL" "Primary instance ID not found."; return 1; }
    log_msg "$INFO" "Creating replica $INST_REPLICA from $INST_PRIMARY ..."
    db instance create "$INST_REPLICA" \
        --replica-of "$primary_id" \
        --nic net-id=${NET_ID} \
        --allowed-cidr ${ALLOWED_CIDR} \
        2>&1 \
        || { log_msg "$FAIL" "Replica create command failed."; return 1; }
    log_msg "$INFO" "Waiting for $INST_REPLICA to be ready ..."
    wait_for_instance "$INST_REPLICA" || return 1
    log_msg "$INFO" "Instance $INST_REPLICA is ready."
}

test_replica_list() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Checking to see if replica $INST_REPLICA found in instance list."
    local out; out=$(db instance list -f value -c name -c replica_of 2>&1)
    echo "$out" | grep -qF "$INST_REPLICA" \
        || { log_msg "$FAIL" "$INST_REPLICA not found in instance list."; return 1; }
}

# ── instance actions ──────────────────────────────────────────────────────────
test_instance_rebuild() {
    # Attempt a rebuild of the database instance's nova server
    log_msg "$INFO" "" false
    log_msg "$INFO" "Rebuilding nova server for instance $INST_PRIMARY ..."
    local tags=$(openstack datastore version show $DS_VERSION --datastore $DATASTORE -f value -c image_tags)
    tags=$(echo "$tags" | tr -d "[]'," )
    tag_args=()
    for tag in $tags; do
        tag_args+=" --tag $tag"
    done
    local image_id=$(openstack image list $tag_args -f value -c ID)
    db instance rebuild $(instance_id "$INST_PRIMARY") "$image_id" 2>&1 \
        || { log_msg "$FAIL" "Rebuild command returned non-zero."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY rebuilt successfully."
}

test_instance_upgrade() {
    # Attempt an upgrade to the same version (safe no-op in most environments)
    log_msg "$INFO" "" false
    log_msg "$INFO" "Testing instance upgrade API on $INST_PRIMARY ..."
    db instance upgrade "$INST_PRIMARY" "$DS_VERSION" 2>&1 \
        || { log_msg "$FAIL" "Upgrade command returned non-zero."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY upgraded successfully."
}

test_instance_reboot() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Rebooting instance $INST_PRIMARY ..."
    local primary_id; primary_id=$(instance_id "$INST_PRIMARY")
    db instance reboot "$primary_id" 2>&1 \
        || { log_msg "$FAIL" "Instance reboot failed."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY rebooted successfully."
}

test_instance_restart() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Restarting instance $INST_PRIMARY ..."
    db instance restart "$INST_PRIMARY" 2>&1 \
        || { log_msg "$FAIL" "Instance restart failed."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY restarted successfully."
}

test_instance_reset_status() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Resetting instance $INST_PRIMARY status ..."
    db instance reset status "$INST_PRIMARY" 2>&1 \
        || { log_msg "$FAIL" "Resetting instance status failed."; return 1; }
    wait_for_instance "$INST_PRIMARY" || return 1
    log_msg "$INFO" "Instance $INST_PRIMARY status reset successfully."
}

test_instance_update() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Updating instance  $INST_PRIMARY ..."
    db instance update $INST_PRIMARY \
        --allowed-cidr ${ALLOWED_CIDR} \
        --allowed-cidr "1.2.3.4/5" \
        2>&1 \
        || { log_msg "$FAIL" "Updating instance failed."; return 1; }
    local out
    local retry_cnt=0
    while (( retry_cnt < 5 )); do
          out=$(db instance show "$INST_PRIMARY" -f value -c allowed_cidrs 2>&1)
          log_msg "$INFO" "Instance details:"
          log_msg "$INFO" "$out" | head -5 | sed 's/^/  /'
          if echo "$out" | grep -q "1.2.3.4/5"; then
              return 0;
          else
              retry_cnt+=1
              sleep 1
          fi
    done
    log_msg "$FAIL" "Expected allowed cidr not found for instance."
    return 1
}

test_log_list() {
    log_msg "$INFO" "" false
    local out; out=$(db log list "$INST_PRIMARY" -f value -c name 2>&1)
    log_msg "$INFO" "Available logs on $INST_PRIMARY:"
    log_msg "$INFO" "$out" | sed 's/^/  /'
    [[ -n "$out" ]] \
        || { log_msg "$FAIL" "No logs returned from instance $INST_PRIMARY."; return 1; }
}

test_log_enable_disable() {
    log_msg "$INFO" "" false
    local first_log; first_log=$(db log list "$INST_PRIMARY" -f value -c name 2>/dev/null | head -1)
    [[ -n "$first_log" ]] || { log_msg "$FAIL" "No logs available to enable/disable."; return 1; }
    log_msg "$INFO" "Enabling $first_log log on instance $INST_PRIMARY ..."
    db log set --enable "$INST_PRIMARY" "$first_log" 2>&1 \
        || { log_msg "$FAIL" "Log enable failed."; return 1; }
    log_msg "$INFO" "Disabling $first_log log on instance $INST_PRIMARY ..."
    db log set --disable "$INST_PRIMARY" "$first_log" 2>&1 \
        || { log_msg "$FAIL" "Log disable failed."; return 1; }
}

test_log_show() {
    log_msg "$INFO" "" false
    local log_name=general
    log_msg "$INFO" "Showing $log_name log on instance $INST_PRIMARY ..."
    db log set --enable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log enable for $log_name log failed."; return 1; }
    local out; out=$(db log show "$INST_PRIMARY" "$log_name" 2>&1)
    log_msg "$INFO" "Log details:"
    log_msg "$INFO" "$out"
    [[ -n "$out" ]] || { log_msg "$FAIL" "Log show failed."; return 1; }
    db log set --disable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log disable for $log_name log failed."; return 1; }
}

test_log_save() {
    log_msg "$INFO" "" false
    local log_name=general
    local saved_log="/tmp/${INST_PRIMARY}_${log_name}.log"
    log_msg "$INFO" "Saving $log_name log on instance $INST_PRIMARY ..."
    db log set --enable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log enable for $log_name log failed."; return 1; }
    db log set --publish "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log publish for $log_name log failed."; return 1; }
    rm -f $saved_log
    db log save --file $saved_log "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log save failed; command failed."; return 1; }
    ls -alh $saved_log 1>/dev/null 2>&1 || { log_msg "$FAIL" "Log save failed; saved log not found"; return 1; }
    log_msg "$INFO" "Log contents:"
    log_contents=$(cat $saved_log)
    log_msg "$INFO" "$log_contents"
    db log set --disable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log disable for $log_name log failed."; return 1; }
}

test_log_tail() {
    log_msg "$INFO" "" false
    local log_name=general
    log_msg "$INFO" "Tailing $log_name log on instance $INST_PRIMARY ..."
    db log set --enable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log enable for $log_name log failed."; return 1; }
    db log set --publish "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log publish for $log_name log failed."; return 1; }
    local out; out=$(db log tail "$INST_PRIMARY" "$log_name" 2>&1)
    log_msg "$INFO" "Log contents:"
    log_msg "$INFO" "$out"
    [[ -n "$out" ]] || { log_msg "$FAIL" "Log tail failed."; return 1; }
    db log set --disable "$INST_PRIMARY" "$log_name" 2>&1 \
        || { log_msg "$FAIL" "Log disable for $log_name log failed."; return 1; }
}

test_detach_instance() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Detaching replica $INST_REPLICA from primary ..."
    db instance detach "$INST_REPLICA" 2>&1 \
        || { log_msg "$FAIL" "Detach instance failed."; return 1; }
    wait_for_instance "$INST_REPLICA" || return 1
    log_msg "$INFO" "Replica $INST_REPLICA detached."
}

test_instance_promote_eject() {
    log_msg "$INFO" "" false
    log_msg "$INFO" "Testing promote ..."
    local primary_name="test-trove-promote-eject-test-0"
    local replica1_name="test-trove-promote-eject-test-1"
    local replica2_name="test-trove-promote-eject-test-2"
    db instance create "$primary_name" \
        --flavor "$FLAVOR" \
        --size "$VOL_SIZE" \
        --volume-type Standard \
        --datastore "$DATASTORE" \
        --datastore-version-number "$DS_VERSION" \
        --databases "$DB_NAME" \
        --users "${USER_NAME}:${USER_PASS}" \
        --nic net-id="${NET_ID}" \
        --allowed-cidr "${ALLOWED_CIDR}" \
        || { log_msg "$FAIL" "Failed to issue create command for $primary_name"; return 1; }
    log_msg "$INFO" "Waiting for $primary_name to be ready ..."
    wait_for_instance "$primary_name" || return 1
    log_msg "$INFO" "Instance $primary_name is ready."

    local primary_id; primary_id=$(instance_id "$primary_name")
    db instance create "$replica1_name" \
        --replica-of "$primary_id" \
        --nic net-id="${NET_ID}" \
        --allowed-cidr "${ALLOWED_CIDR}" \
        || { log_msg "$FAIL" "Replica 1 create command failed."; return 1; }
    log_msg "$INFO" "Waiting for $replica1_name to be ready ..."
    wait_for_instance "$replica1_name" || return 1
    log_msg "$INFO" "Instance $replica1_name is ready."

    local replica1_id; replica1_id=$(instance_id "$replica1_name")
    db instance create "$replica2_name" \
        --replica-of "$primary_id" \
        --nic net-id="${NET_ID}" \
        --allowed-cidr "${ALLOWED_CIDR}" \
        || { log_msg "$FAIL" "Replica 2 create command failed."; return 1; }
    log_msg "$INFO" "Waiting for $replica2_name to be ready ..."
    wait_for_instance "$replica2_name" || return 1
    log_msg "$INFO" "Instance $replica2_name is ready."

    log_msg "$INFO" "Promoting replica $replica2_name ..."
    local replica2_id; replica2_id=$(instance_id "$replica2_name")
    db instance promote "$replica2_id" \
        || { log_msg "$FAIL" "Failed to promote $replica2_name."; return 1; }

    # wait for promote process to complete on all instances
    log_msg "$INFO" "Waiting for $primary_name to be ready ..."
    wait_for_instance "$primary_name" || return 1
    log_msg "$INFO" "Waiting for $replica1_name to be ready ..."
    wait_for_instance "$replica1_name" || return 1
    log_msg "$INFO" "Waiting for $replica2_name to be ready ..."
    wait_for_instance "$replica2_name" || return 1

    # check original primary doesn't show replicas and is now a replica (this is expected because the original primary was ACTIVE/HEALTHY)
    log_msg "$INFO" "Checking primary $primary_name doesn't show replicas and is now a replica ..."
    db instance show "$primary_name" -f value -c replicas 1>/dev/null 2>&1 && { log_msg "$FAIL" "Promote test failed; primary still showing replicas"; return 1; }
    { db instance show "$primary_name" -f value -c replica_of | grep -q "$replica2_id"; } || { log_msg "$FAIL" "Promote test failed; original primary not showing as replica of promoted replica"; return 1; }
    # check promoted replica doesn't show as replica and has the other replicas attached
    log_msg "$INFO" "Checking promoted replica $replica2_name doesn't show as a replica and has other replicas attached ..."
    db instance show "$replica2_name" -f value -c replica_of 1>/dev/null 2>&1 && { log_msg "$FAIL" "Promote test failed; promoted replica still showing as replica"; return 1; }
    { db instance show "$replica2_name" -f value -c replicas | grep -q "$primary_id"; } || { log_msg "$FAIL" "Promote test failed; promoted replica does not show original primary attached as replica"; return 1; }
    { db instance show "$replica2_name" -f value -c replicas | grep -q "$replica1_id"; } || { log_msg "$FAIL" "Promote test failed; promoted replica does not show other replica attached as replica"; return 1; }
    # check other replica is still replica but attached to promoted replica
    log_msg "$INFO" "Checking other replica $replica1_name is still a replica but attached to promoted replica ..."
    { db instance show "$replica1_name" -f value -c replica_of | grep -q "$replica2_id"; } || { log_msg "$FAIL" "Promote test failed; unpromoted replica not showing as replica of promoted replica"; return 1; }

    log_msg "$INFO" "Promote test succeeded."

    log_msg "$INFO" "Testing eject ..."
    # After promote, replica2 is the new primary and the old primary is now a replica.
    # Swap the labels so the variables match the current topology:
    #   primary_*  now refers to the promoted replica2 (current primary)
    #   replica2_* now refers to the old primary (now a replica)
    local temp_id="$primary_id"
    local temp_name="$primary_name"
    primary_id="$replica2_id"
    primary_name="$replica2_name"
    replica2_id="$temp_id"
    replica2_name="$temp_name"

    # stop the guest agent on the primary instance to simulate a 'bad' primary
    log_msg "$INFO" "Stopping the guest agent on the primary instance to simulate a 'bad' primary"
    /opt/genestack/scripts/trove-guest-ssh.sh "$primary_id" "sudo systemctl stop guest-agent"
    sleep 90

    log_msg "$INFO" "Ejecting primary $primary_name ..."
    db instance eject "$primary_name" \
        || { log_msg "$FAIL" "Failed to eject $primary_name."; return 1; }

    # wait for promotion of replica to complete
    log_msg "$INFO" "Waiting for $replica1_name to be ready ..."
    wait_for_instance "$replica1_name" || return 1
    log_msg "$INFO" "Waiting for $replica2_name to be ready ..."
    wait_for_instance "$replica2_name" || return 1

    # check original primary doesn't have replicas and is not a replica
    log_msg "$INFO" "Checking original primary $primary_name doesn't have replicas and is not a replica ..."
    db instance show "$primary_name" -f value -c replicas 1>/dev/null 2>&1 && { log_msg "$FAIL" "Eject test failed; original primary still showing replicas"; return 1; }
    db instance show "$primary_name" -f value -c replica_of 1>/dev/null 2>&1 && { log_msg "$FAIL" "Eject test failed; original primary showing as replica"; return 1; }
    # find promoted replica
    local promoted_replica_name;
    local promoted_replica_id;
    local other_replica_name;
    local other_replica_id;
    for replica_name in "$replica1_name" "$replica2_name"; do
        if db instance show "$replica_name" -f value -c replicas 1>/dev/null 2>&1; then
            promoted_replica_name="$replica_name"
            promoted_replica_id=$(instance_id "$promoted_replica_name")
        else
            other_replica_name="$replica_name"
            other_replica_id=$(instance_id "$other_replica_name")
        fi
    done
    if [ -z "$promoted_replica_name" ] || [ -z "$other_replica_name" ]; then
        log_msg "$FAIL" "Eject test failed; could not determine promoted replica"; return 1
    fi
    # check promoted replica doesn't show as replica and has the other replica attached
    log_msg "$INFO" "Checking promoted replica $promoted_replica_name doesn't show as replica and has the other replica attached ..."
    db instance show "$promoted_replica_name" -f value -c replica_of 1>/dev/null 2>&1 && { log_msg "$FAIL" "Eject test failed; promoted replica still showing as replica"; return 1; }
    { db instance show "$promoted_replica_name" -f value -c replicas | grep -q "$other_replica_id"; } || { log_msg "$FAIL" "Eject test failed; promoted replica does not show other replica attached as replica"; return 1; }
    # check other replica is still replica but attached to promoted replica
    log_msg "$INFO" "Checking other replica $other_replica_name is still replica but attached to promoted replica ..."
    { db instance show "$other_replica_name" -f value -c replica_of | grep -q "$promoted_replica_id"; } || { log_msg "$FAIL" "Eject test failed; unpromoted replica not showing as replica of promoted replica"; return 1; }

    log_msg "$INFO" "Eject test succeeded."

    # attempt cleanup, but don't let it sour the test results
    db instance delete "$primary_id" || true
    db instance delete "$replica1_id" || true
    db instance delete "$promoted_replica_id" || true
}

# ── deletion ──────────────────────────────────────────────────────────────────
test_delete_restore_instance() {
    log_msg "$INFO" "" false
    [[ -n $(db instance list 2>/dev/null | grep $INST_RESTORE) ]] \
        || { log_msg "$FAIL" "$INST_RESTORE not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting restore instance $INST_RESTORE ..."
    db instance delete "$INST_RESTORE" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete $INST_RESTORE."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_RESTORE) ]] && (( elapsed < 120 )); do
        log_msg "$INFO" sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    log_msg "$INFO" "Instance $INST_RESTORE deleted."
}

test_delete_replica_instance() {
    log_msg "$INFO" "" false
    [[ -n $(db instance list 2>/dev/null | grep $INST_REPLICA) ]] \
        || { log_msg "$FAIL" "$INST_REPLICA not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting replica instance $INST_REPLICA ..."
    db instance delete "$INST_REPLICA" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete $INST_REPLICA."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_REPLICA) ]] && (( elapsed < 120 )); do
        log_msg "$INFO" sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    log_msg "$INFO" "Instance $INST_REPLICA deleted."
}

test_delete_backups() {
    log_msg "$INFO" "" false
    [[ -n "$(backup_id "$BACKUP_NAME_INCR")" ]] \
        || { log_msg "$FAIL" "$BACKUP_NAME_INCR not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting backup $BACKUP_NAME_INCR ..."
    db backup delete "$BACKUP_NAME_INCR" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete backup $BACKUP_NAME_INCR."; return 1; }
    log_msg "$INFO" "Backup $BACKUP_NAME_INCR deleted."
    [[ -n "$(backup_id "$BACKUP_NAME")" ]] \
        || { log_msg "$FAIL" "$BACKUP_NAME not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting backup $BACKUP_NAME ..."
    db backup delete "$BACKUP_NAME" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete backup $BACKUP_NAME."; return 1; }
    log_msg "$INFO" "Backup $BACKUP_NAME deleted."
}

test_delete_configuration() {
    log_msg "$INFO" "" false
    [[ -n "$(config_id "$CONFIG_GROUP")" ]] \
        || { log_msg "$FAIL" "$CONFIG_GROUP not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting configuration group $CONFIG_GROUP ..."
    db configuration delete "$CONFIG_GROUP" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete configuration group $CONFIG_GROUP."; return 1; }
    log_msg "$INFO" "Configuration group $CONFIG_GROUP deleted."
}

test_force_delete_primary_instance() {
    log_msg "$INFO" "" false
    [[ -n $(db instance list 2>/dev/null | grep $INST_PRIMARY) ]] \
        || { log_msg "$FAIL" "$INST_PRIMARY not found, skipping."; return 0; }
    log_msg "$INFO" "Deleting primary instance $INST_PRIMARY ..."
    db instance force delete "$INST_PRIMARY" 2>&1 \
        || { log_msg "$FAIL" "Failed to delete $INST_PRIMARY."; return 1; }
    local elapsed=0
    while [[ -n $(db instance list 2>/dev/null | grep $INST_PRIMARY) ]] && (( elapsed < 180 )); do
        log_msg "$INFO" sleeping ...
        sleep 5; (( elapsed += 5 ))
    done
    log_msg "$INFO" "Instance $INST_PRIMARY deleted."
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════
main() {
    TEST_SUITE_NAME="trove-feature-tests"
    init_tests "${TEST_SUITE_NAME}"

    if ! source_credentials; then
        echo -e "$FAIL ERROR: Failed to source OpenStack credentials $ENDC"
        exit 1
    fi

    # ── customer network setup
    /opt/genestack/scripts/tests/lib/manage-test-tenants.sh create

    if [[ -n "${INSTANCE}" ]]; then
        db instance show ${INSTANCE} -f value -c name 1>/dev/null
        INST_NAME=$(db instance show ${INSTANCE} -f value -c name 2>/dev/null || true)
        if [[ -z "$INST_NAME" ]]; then
            echo -e "$FAIL ERROR: $INSTANCE not found $ENDC" && exit 99
        else
            export INST_PRIMARY=$INST_NAME
            echo -e "$INFO INST_PRIMARY: $INST_PRIMARY $ENDC"
        fi
    fi

    echo -e "$BLUE ════════════════════════════════════════════════════"
    echo -e "$BLUE   Trove Feature Validation Suite"
    echo -e "$BLUE ════════════════════════════════════════════════════"
    echo -e "$BLUE   Datastore:   $DATASTORE $DS_VERSION $ENDC"
    echo -e "$BLUE   Flavor:      $FLAVOR $ENDC"
    echo -e "$BLUE   Volume:      ${VOL_SIZE}GB $ENDC"
    echo -e "$BLUE   Network:     ${NET_NAME} $ENDC"
    echo -e "$BLUE   Prefix:      $PFX $ENDC"
    echo -e "$BLUE   Cleanup:     ${CLEANUP} $ENDC"
    echo -e "$BLUE ════════════════════════════════════════════════════ $ENDC"
    echo ""

    export NET_ID=$(os network show ${NET_NAME} -f value -c id)
    export ALLOWED_CIDR=$(os subnet show ${SUBNET_NAME} -f value -c cidr)

    # ── prerequisites
    run_test "trove_service_available"        test_trove_service_available
    run_test "trove_cli_available"            test_trove_cli_available

    # ── discovery
    run_test "datastore_list"                 test_datastore_list
    run_test "datastore_version_list"         test_datastore_version_list
    run_test "flavor_list"                    test_flavor_list
    run_test "flavor_show"                    test_flavor_show
    run_test "limit_list"                     test_limit_list
    run_test "quota_show"                     test_quota_show
    run_test "quota_update"                   test_quota_update

    # ── primary instance lifecycle
    run_test "create_instance"                test_create_instance
    run_test "instance_list"                  test_instance_list
    run_test "instance_show"                  test_instance_show

    # ── database & user management
    run_test "database_create"                test_database_create
    run_test "database_list"                  test_database_list
    run_test "database_delete"                test_database_delete
    run_test "user_create"                    test_user_create
    run_test "user_list"                      test_user_list
    run_test "user_show"                      test_user_show
    run_test "user_show_access"               test_user_show_access
    run_test "user_grant_access"              test_user_grant_access
    run_test "user_revoke_access"             test_user_revoke_access
    run_test "user_update_attributes"         test_user_update_attributes
    run_test "user_delete"                    test_user_delete
    run_test "root_show"                      test_root_show
    run_test "root_enable"                    test_root_enable
    run_test "root_disable"                   test_root_disable

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
    run_test "instance_rebuild"               test_instance_rebuild
    run_test "instance_upgrade"               test_instance_upgrade
    run_test "instance_reboot"                test_instance_reboot
    run_test "instance_restart"               test_instance_restart
    run_test "instance_update"                test_instance_update
    run_test "instance_reset_status"          test_instance_reset_status
    run_test "resize_instance"                test_resize_instance
    run_test "resize_volume"                  test_resize_volume

    # ── log actions
    run_test "log_list"                       test_log_list
    run_test "log_enable_disable"             test_log_enable_disable
    run_test "log_show"                       test_log_show
    run_test "log_save"                       test_log_save
    run_test "log_tail"                       test_log_tail

    # ── backup & restore
    run_test "backup_execution_delete"        test_backup_execution_delete
    run_test "backup_strategy_create"         test_backup_strategy_create
    run_test "backup_strategy_list"           test_backup_strategy_list
    run_test "backup_strategy_delete"         test_backup_strategy_delete
    run_test "backup_create"                  test_backup_create
    run_test "backup_list"                    test_backup_list
    run_test "backup_list_instance"           test_backup_list_instance
    run_test "backup_show"                    test_backup_show
    run_test "incremental_backup_create"      test_incremental_backup_create
    run_test "restore_from_backup"            test_restore_from_backup

    # ── replication
    run_test "create_replica"                 test_create_replica
    run_test "replica_list"                   test_replica_list
    run_test "detach_instance"                test_detach_instance
    run_test "instance_promote_eject"         test_instance_promote_eject

    # ── clusters
    skip_test "cluster_create"                "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_delete"                "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_force_delete"          "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_grow"                  "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_list"                  "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_list_instances"        "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_modules"               "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_reset_status"          "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_show"                  "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_shrink"                "Clusters are experimental and only MongoDB is supported"
    skip_test "cluster_upgrade"               "Clusters are experimental and only MongoDB is supported"

    # ── deletion (ordered: restore → replica → backup → config → primary)
    if [[ "$CLEANUP" != "none" ]]; then
        run_test "delete_restore_instance"    test_delete_restore_instance
        run_test "delete_replica_instance"    test_delete_replica_instance
        run_test "delete_backups"             test_delete_backups
        run_test "delete_configuration"       test_delete_configuration
        run_test "delete_primary_instance"    test_force_delete_primary_instance
        CLEANUP_DONE=1   # All resources explicitly deleted above
    fi

    echo ""
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
