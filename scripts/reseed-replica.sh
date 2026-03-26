#!/usr/bin/env bash
# Reseeds one or more unhealthy MariaDB replicas in Kubernetes.
# The script discovers the current primary, evaluates replica health,
# takes a fresh dump from the primary, recreates the selected replica
# pods and PVC-backed storage, restores the dump, and reconfigures
# replication to point back at the current primary.
#
# Safety notes:
# - The primary pod is never a valid reseed target.
# - If multiple unhealthy replicas are found, the script can prompt for
#   one target or reseed all unhealthy replicas.
# - A single dump is reused when reseeding multiple replicas in one run.
# - Backup-only mode stops after producing and validating a fresh dump.
set -euo pipefail

NAMESPACE="openstack"
STS_NAME="mariadb-cluster"
ROOT_SECRET="mariadb"
REPL_SECRET="repl-password-mariadb-cluster"
REPLICA_POD=""
WORKDIR=""
KEEP_DUMP="false"
WAIT_TIMEOUT="600s"
INTERACTIVE="false"
ALL_UNHEALTHY="false"
BACKUP_ONLY="false"
SUCCESS="false"
declare -a UNHEALTHY_REPLICAS=()
declare -a HEALTHY_REPLICAS=()
declare -a TARGET_REPLICAS=()
declare -a COMPLETED_REPLICAS=()
declare -a FINAL_STATUS_SUMMARIES=()

usage() {
  cat <<'EOF'
Usage:
  reseed-replica.sh [options]

Options:
  --namespace <ns>         Kubernetes namespace (default: openstack)
  --statefulset <name>     StatefulSet name (default: mariadb-cluster)
  --root-secret <name>     Secret containing root-password (default: mariadb)
  --repl-secret <name>     Secret containing repl password (default: repl-password-mariadb-cluster)
  --replica <pod>          Replica pod to reseed explicitly
  --all-unhealthy          Reseed all unhealthy replicas without prompting
  --backup-only            Only create and validate a fresh dump, then exit
  --workdir <dir>          Directory for local dump file (default: ~/backups)
  --keep-dump              Keep local dump file after completion
  --interactive            Print each major command and ask before running it
  --help                   Show this help
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$(date +'%F %T')" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

prompt_confirm() {
  local prompt="${1:-Continue?}"
  local reply
  while true; do
    printf '%s [y/N]: ' "$prompt" >&2
    read -r reply || return 1
    case "$reply" in
      y|Y|yes|YES)
        return 0
        ;;
      "")
        printf 'Press y to continue or n to abort.\n' >&2
        ;;
      *)
        return 1
        ;;
    esac
  done
}

stdin_is_tty() {
  [[ -t 0 ]]
}

prompt_choice() {
  local prompt="$1"
  shift
  local choices=("$@")
  local reply
  local choice

  while true; do
    printf '%s [%s]: ' "${prompt}" "$(IFS=/; printf '%s' "${choices[*]}")" >&2
    read -r reply || return 1
    for choice in "${choices[@]}"; do
      if [[ "${reply}" == "${choice}" ]]; then
        printf '%s' "${choice}"
        return 0
      fi
    done
    printf 'Please enter one of: %s\n' "${choices[*]}" >&2
  done
}

run_cmd() {
  local desc="$1"
  shift

  if [[ "${INTERACTIVE}" == "true" ]]; then
    printf '\n' >&2
    log "${desc}"
    printf 'Command:\n' >&2
    printf '  ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    if ! prompt_confirm "Run this command?"; then
      die "Aborted by user"
    fi
  else
    log "${desc}"
  fi

  "$@"
}

run_remote_sql_file() {
  local desc="$1"
  local pod="$2"
  local sql_file="$3"

  if [[ "${INTERACTIVE}" == "true" ]]; then
    printf '\n' >&2
    log "${desc}"
    printf 'Command:\n' >&2
    printf '  kubectl -n %q exec -i %q -- sh -c %q < %q\n' \
      "${NAMESPACE}" "${pod}" "exec mariadb -uroot -p'*****'" "${sql_file}" >&2
    if ! prompt_confirm "Run this restore/import command?"; then
      die "Aborted by user"
    fi
  else
    log "${desc}"
  fi

  kubectl -n "${NAMESPACE}" exec -i "${pod}" -- sh -c \
    "exec mariadb -uroot -p'${ROOT_PASSWORD}'" \
    < "${sql_file}"
}

run_remote_sql_text() {
  local desc="$1"
  local pod="$2"
  local sql_text="$3"
  local display_sql="${4:-$3}"

  if [[ "${INTERACTIVE}" == "true" ]]; then
    printf '\n' >&2
    log "${desc}"
    printf 'SQL to execute on %s:\n' "${pod}" >&2
    printf '%s\n' "${display_sql}" >&2
    if ! prompt_confirm "Run this SQL?"; then
      die "Aborted by user"
    fi
  else
    log "${desc}"
  fi

  kubectl -n "${NAMESPACE}" exec "${pod}" -- sh -c \
    "mariadb -uroot -p'${ROOT_PASSWORD}' -e \"${sql_text}\""
}

get_pod_uid() {
  local pod="$1"
  kubectl -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.metadata.uid}' 2>/dev/null || true
}

wait_for_new_pod_uid() {
  local pod="$1"
  local old_uid="$2"
  local timeout_secs="${3:-600}"
  local interval_secs=5
  local elapsed=0
  local current_uid=""

  if [[ "${INTERACTIVE}" == "true" ]]; then
    printf '\n' >&2
    log "Waiting for replacement pod ${pod} to appear"
    printf 'Criteria:\n' >&2
    printf '  pod exists and UID != old UID\n' >&2
    printf '  old UID: %s\n' "${old_uid:-<none>}" >&2
    printf '  timeout: %ss, interval: %ss\n' "${timeout_secs}" "${interval_secs}" >&2
    if ! prompt_confirm "Start waiting for replacement pod?"; then
      die "Aborted by user"
    fi
  else
    log "Waiting for replacement pod ${pod} to appear"
  fi

  while true; do
    current_uid="$(get_pod_uid "${pod}")"
    if [[ -n "${current_uid}" ]]; then
      if [[ -z "${old_uid}" || "${current_uid}" != "${old_uid}" ]]; then
        log "Replacement pod ${pod} detected with UID ${current_uid}"
        return 0
      fi
    fi

    if (( elapsed >= timeout_secs )); then
      die "Timed out waiting for replacement pod ${pod}"
    fi

    sleep "${interval_secs}"
    elapsed=$((elapsed + interval_secs))
  done
}

replication_channel_exists() {
  local pod="$1"
  local channel="$2"

  kubectl -n "${NAMESPACE}" exec "${pod}" -- sh -c \
    "mariadb -uroot -p'${ROOT_PASSWORD}' -e \"SHOW ALL SLAVES STATUS\\G\"" 2>/dev/null \
    | grep -q "Connection_name: ${channel}"
}

pod_ready_condition() {
  local pod="$1"
  kubectl -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true
}

replica_health_report() {
  local pod="$1"
  local ready_status
  local slave_status

  ready_status="$(pod_ready_condition "${pod}")"
  if [[ "${ready_status}" != "True" ]]; then
    printf 'unhealthy|pod-not-ready'
    return 0
  fi

  slave_status="$(kubectl -n "${NAMESPACE}" exec "${pod}" -- sh -c \
    "mariadb -uroot -p'${ROOT_PASSWORD}' -e \"SHOW ALL SLAVES STATUS\\G\"" 2>/dev/null || true)"

  if [[ -z "${slave_status}" ]]; then
    printf 'unhealthy|no-slave-status'
    return 0
  fi

  if printf '%s\n' "${slave_status}" | awk '
    BEGIN { channels = 0; bad = 0; io = ""; sql = "" }
    /^[[:space:]]*Connection_name:/ { channels++; next }
    /^[[:space:]]*Slave_IO_Running:/ { io = $2; next }
    /^[[:space:]]*Slave_SQL_Running:/ {
      sql = $2
      if (io != "Yes" || sql != "Yes") {
        bad = 1
      }
      io = ""
      sql = ""
    }
    END {
      if (channels == 0 || bad) {
        exit 1
      }
    }
  '; then
    printf 'healthy|replication-ok'
  else
    printf 'unhealthy|replication-stopped'
  fi
}

discover_replica_health() {
  local ordinal
  local pod
  local report
  local status
  local reason

  UNHEALTHY_REPLICAS=()
  HEALTHY_REPLICAS=()

  for (( ordinal=0; ordinal<STS_REPLICAS; ordinal++ )); do
    pod="${STS_NAME}-${ordinal}"
    if [[ "${pod}" == "${PRIMARY_POD}" ]]; then
      continue
    fi

    report="$(replica_health_report "${pod}")"
    status="${report%%|*}"
    reason="${report#*|}"

    if [[ "${status}" == "healthy" ]]; then
      HEALTHY_REPLICAS+=("${pod}")
      log "Replica health check: ${pod} is healthy (${reason})"
    else
      UNHEALTHY_REPLICAS+=("${pod}")
      log "Replica health check: ${pod} is unhealthy (${reason})"
    fi
  done
}

validate_dump_file() {
  local dump_file="$1"

  [[ -f "${dump_file}" ]] || die "Dump file was not created: ${dump_file}"
  [[ -s "${dump_file}" ]] || die "Dump file is empty: ${dump_file}"

  grep -q -E '^-- Dump completed on ' "${dump_file}" \
    || die "Dump file appears incomplete; missing mariadb-dump completion marker: ${dump_file}"

  grep -q -E 'CHANGE MASTER TO MASTER_LOG_FILE=' "${dump_file}" \
    || die "Dump file appears incomplete; missing replication coordinates: ${dump_file}"
}

build_replica_status_summary() {
  local pod="$1"
  local status_text="$2"
  local slave_io
  local slave_sql
  local seconds_behind
  local last_io_errno
  local last_sql_errno

  slave_io="$(printf '%s\n' "${status_text}" | awk -F': ' '/^[[:space:]]*Slave_IO_Running:/ {print $2; exit}')"
  slave_sql="$(printf '%s\n' "${status_text}" | awk -F': ' '/^[[:space:]]*Slave_SQL_Running:/ {print $2; exit}')"
  seconds_behind="$(printf '%s\n' "${status_text}" | awk -F': ' '/^[[:space:]]*Seconds_Behind_Master:/ {print $2; exit}')"
  last_io_errno="$(printf '%s\n' "${status_text}" | awk -F': ' '/^[[:space:]]*Last_IO_Errno:/ {print $2; exit}')"
  last_sql_errno="$(printf '%s\n' "${status_text}" | awk -F': ' '/^[[:space:]]*Last_SQL_Errno:/ {print $2; exit}')"

  [[ -n "${slave_io}" ]] || slave_io="unknown"
  [[ -n "${slave_sql}" ]] || slave_sql="unknown"
  [[ -n "${seconds_behind}" ]] || seconds_behind="unknown"
  [[ -n "${last_io_errno}" ]] || last_io_errno="unknown"
  [[ -n "${last_sql_errno}" ]] || last_sql_errno="unknown"

  printf '%s | Slave_IO_Running=%s | Slave_SQL_Running=%s | Seconds_Behind_Master=%s | Last_IO_Errno=%s | Last_SQL_Errno=%s' \
    "${pod}" "${slave_io}" "${slave_sql}" "${seconds_behind}" "${last_io_errno}" "${last_sql_errno}"
}

is_known_unhealthy_replica() {
  local pod="$1"
  local unhealthy
  for unhealthy in "${UNHEALTHY_REPLICAS[@]}"; do
    if [[ "${unhealthy}" == "${pod}" ]]; then
      return 0
    fi
  done
  return 1
}

select_target_replicas() {
  local selected
  local choice

  TARGET_REPLICAS=()

  if [[ -n "${REPLICA_POD}" && "${ALL_UNHEALTHY}" == "true" ]]; then
    die "Use either --replica or --all-unhealthy, not both"
  fi

  if [[ -n "${REPLICA_POD}" ]]; then
    [[ "${REPLICA_POD}" != "${PRIMARY_POD}" ]] || die "Replica pod must not be the primary pod"
    if ! kubectl -n "${NAMESPACE}" get pod "${REPLICA_POD}" >/dev/null 2>&1; then
      die "Replica pod ${REPLICA_POD} does not exist in namespace ${NAMESPACE}"
    fi
    log "Using explicitly requested replica target: ${REPLICA_POD}"
    TARGET_REPLICAS=("${REPLICA_POD}")
    return 0
  fi

  if [[ ${#UNHEALTHY_REPLICAS[@]} -eq 0 ]]; then
    die "No unhealthy replicas detected. Re-run with --replica <pod> only if you intentionally want to force a specific target."
  fi

  if [[ "${ALL_UNHEALTHY}" == "true" ]]; then
    TARGET_REPLICAS=("${UNHEALTHY_REPLICAS[@]}")
    return 0
  fi

  if [[ ${#UNHEALTHY_REPLICAS[@]} -eq 1 ]]; then
    TARGET_REPLICAS=("${UNHEALTHY_REPLICAS[0]}")
    log "Selected unhealthy replica automatically: ${TARGET_REPLICAS[0]}"
    return 0
  fi

  if ! stdin_is_tty; then
    die "Multiple unhealthy replicas detected (${UNHEALTHY_REPLICAS[*]}). Re-run with --replica <pod> or --all-unhealthy."
  fi

  printf '\nMultiple unhealthy replicas were detected:\n' >&2
  for selected in "${UNHEALTHY_REPLICAS[@]}"; do
    printf '  - %s\n' "${selected}" >&2
  done
  printf '\n' >&2

  choice="$(prompt_choice "Reseed a single replica or all unhealthy replicas?" one all abort)" || die "Aborted by user"
  case "${choice}" in
    one)
      while true; do
        printf 'Enter replica pod to reseed: ' >&2
        read -r selected || die "Aborted by user"
        if is_known_unhealthy_replica "${selected}"; then
          TARGET_REPLICAS=("${selected}")
          return 0
        fi
        printf 'Replica must be one of: %s\n' "${UNHEALTHY_REPLICAS[*]}" >&2
      done
      ;;
    all)
      TARGET_REPLICAS=("${UNHEALTHY_REPLICAS[@]}")
      return 0
      ;;
    *)
      die "Aborted by user"
      ;;
  esac
}

reseed_replica() {
  local replica_pod="$1"
  local old_replica_uid
  local owner_ref
  local final_status_text
  local -a replica_pvcs=()
  local pvc

  run_cmd "Verifying replica pod exists" \
    kubectl -n "${NAMESPACE}" get pod "${replica_pod}"

  owner_ref="$(kubectl -n "${NAMESPACE}" get pod "${replica_pod}" -o jsonpath='{.metadata.ownerReferences[0].name}')"
  [[ "${owner_ref}" == "${STS_NAME}" ]] || die "Replica pod ${replica_pod} is not owned by StatefulSet ${STS_NAME}"

  old_replica_uid="$(get_pod_uid "${replica_pod}")"
  [[ -n "${old_replica_uid}" ]] || die "Could not determine UID for replica pod ${replica_pod}"

  log "Discovering PVCs attached to ${replica_pod}"
  mapfile -t replica_pvcs < <(
    kubectl -n "${NAMESPACE}" get pod "${replica_pod}" \
      -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}' \
      | awk 'NF'
  )

  if [[ ${#replica_pvcs[@]} -eq 0 ]]; then
    die "No PVCs found on replica pod ${replica_pod}"
  fi

  printf '  Replica PVCs for %s:\n' "${replica_pod}"
  for pvc in "${replica_pvcs[@]}"; do
    printf '    - %s\n' "${pvc}"
  done
  printf '\n'

  if [[ "${INTERACTIVE}" == "true" ]]; then
    if ! prompt_confirm "Proceed with deleting these PVCs and pod ${replica_pod}?"; then
      die "Aborted by user"
    fi
  fi

  for pvc in "${replica_pvcs[@]}"; do
    run_cmd "Deleting PVC ${pvc}" \
      kubectl -n "${NAMESPACE}" delete pvc "${pvc}" --wait=false --ignore-not-found=true
  done

  run_cmd "Deleting replica pod ${replica_pod}" \
    kubectl -n "${NAMESPACE}" delete pod "${replica_pod}" --wait=false --ignore-not-found=true

  wait_for_new_pod_uid "${replica_pod}" "${old_replica_uid}" "${WAIT_TIMEOUT_SECS}"

  run_cmd "Waiting for ${replica_pod} to become Ready" \
    kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${replica_pod}" --timeout="${WAIT_TIMEOUT}"

  run_remote_sql_file "Restoring dump into ${replica_pod}" "${replica_pod}" "${DUMP_FILE}"

  run_remote_sql_text "Resetting default replication metadata on ${replica_pod}" "${replica_pod}" \
"STOP SLAVE;
RESET SLAVE ALL;"

  if replication_channel_exists "${replica_pod}" "mariadb-operator"; then
    run_remote_sql_text "Resetting operator replication channel on ${replica_pod}" "${replica_pod}" \
"STOP SLAVE 'mariadb-operator';
RESET SLAVE 'mariadb-operator' ALL;"
  else
    log "Replication channel mariadb-operator not present on ${replica_pod}; skipping channel reset"
  fi

  run_remote_sql_text \
    "Configuring replication on ${replica_pod}" \
    "${replica_pod}" \
    "${CHANGE_MASTER_SQL}" \
    "${CHANGE_MASTER_SQL_DISPLAY}"

  run_remote_sql_text \
    "Final replica status from ${replica_pod}" \
    "${replica_pod}" \
    "SHOW SLAVE STATUS\G"

  final_status_text="$(kubectl -n "${NAMESPACE}" exec "${replica_pod}" -- sh -c \
    "mariadb -uroot -p'${ROOT_PASSWORD}' -e \"SHOW SLAVE STATUS\\G\"")"
  FINAL_STATUS_SUMMARIES+=("$(build_replica_status_summary "${replica_pod}" "${final_status_text}")")

  COMPLETED_REPLICAS+=("${replica_pod}")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --statefulset)
      STS_NAME="$2"
      shift 2
      ;;
    --root-secret)
      ROOT_SECRET="$2"
      shift 2
      ;;
    --repl-secret)
      REPL_SECRET="$2"
      shift 2
      ;;
    --replica)
      REPLICA_POD="$2"
      shift 2
      ;;
    --all-unhealthy)
      ALL_UNHEALTHY="true"
      shift
      ;;
    --backup-only)
      BACKUP_ONLY="true"
      shift
      ;;
    --workdir)
      WORKDIR="$2"
      shift 2
      ;;
    --keep-dump)
      KEEP_DUMP="true"
      shift
      ;;
    --interactive)
      INTERACTIVE="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

need_cmd kubectl
need_cmd grep
need_cmd sed
need_cmd awk
need_cmd date
need_cmd base64

if [[ -z "${WORKDIR}" ]]; then
  WORKDIR="${HOME}/backups"
fi

mkdir -p "${WORKDIR}"

DUMP_FILE=""

cleanup() {
  if [[ "${KEEP_DUMP}" != "true" && "${SUCCESS}" == "true" ]]; then
    rm -f "${DUMP_FILE}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

WAIT_TIMEOUT_SECS="${WAIT_TIMEOUT%s}"
[[ "${WAIT_TIMEOUT_SECS}" =~ ^[0-9]+$ ]] || die "WAIT_TIMEOUT must be in whole seconds, e.g. 600s"

run_cmd "Verifying StatefulSet exists" \
  kubectl -n "${NAMESPACE}" get statefulset "${STS_NAME}"

ROOT_PASSWORD="$(kubectl -n "${NAMESPACE}" get secret "${ROOT_SECRET}" -o jsonpath='{.data.root-password}' | base64 -d)"
[[ -n "${ROOT_PASSWORD}" ]] || die "Could not read root-password from secret ${ROOT_SECRET}"

REPL_PASSWORD="$(kubectl -n "${NAMESPACE}" get secret "${REPL_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"
[[ -n "${REPL_PASSWORD}" ]] || die "Could not read password from secret ${REPL_SECRET}"

mapfile -t MARIADB_CRS < <(kubectl -n "${NAMESPACE}" get mariadbs -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[[ ${#MARIADB_CRS[@]} -ge 1 ]] || die "No MariaDB CRs found in namespace ${NAMESPACE}"

MARIADB_CR=""
for cr in "${MARIADB_CRS[@]}"; do
  if [[ "${cr}" == "${STS_NAME}" ]]; then
    MARIADB_CR="${cr}"
    break
  fi
done
if [[ -z "${MARIADB_CR}" ]]; then
  if [[ ${#MARIADB_CRS[@]} -eq 1 ]]; then
    MARIADB_CR="${MARIADB_CRS[0]}"
  else
    die "Multiple MariaDB CRs found (${MARIADB_CRS[*]}). Unable to select one safely."
  fi
fi

log "Using MariaDB CR: ${MARIADB_CR}"

get_jsonpath_value() {
  local path="$1"
  kubectl -n "${NAMESPACE}" get mariadb "${MARIADB_CR}" -o "jsonpath=${path}" 2>/dev/null || true
}

PRIMARY_RAW=""
for path in \
  '{.status.currentPrimaryPodIndex}' \
  '{.status.currentPrimaryIndex}' \
  '{.status.primaryIndex}' \
  '{.status.currentPrimary}' \
  '{.status.primary}' \
  '{.status.currentPrimaryPod}' \
  '{.status.primaryPod}'
do
  PRIMARY_RAW="$(get_jsonpath_value "${path}")"
  if [[ -n "${PRIMARY_RAW}" ]]; then
    break
  fi
done

[[ -n "${PRIMARY_RAW}" ]] || die "Could not determine primary from MariaDB CR status"

PRIMARY_POD=""
if [[ "${PRIMARY_RAW}" =~ ^[0-9]+$ ]]; then
  PRIMARY_POD="${STS_NAME}-${PRIMARY_RAW}"
elif [[ "${PRIMARY_RAW}" =~ ^${STS_NAME}-[0-9]+$ ]]; then
  PRIMARY_POD="${PRIMARY_RAW}"
elif [[ "${PRIMARY_RAW}" == *"${STS_NAME}-"* ]]; then
  PRIMARY_POD="${PRIMARY_RAW##*/}"
else
  die "Unrecognized primary value from CR status: ${PRIMARY_RAW}"
fi

log "Primary reported by CR: ${PRIMARY_POD}"

STS_REPLICAS="$(kubectl -n "${NAMESPACE}" get statefulset "${STS_NAME}" -o jsonpath='{.spec.replicas}')"
[[ "${STS_REPLICAS}" =~ ^[0-9]+$ ]] || die "Could not read replica count from StatefulSet ${STS_NAME}"

PRIMARY_ORDINAL="${PRIMARY_POD##*-}"
[[ "${PRIMARY_ORDINAL}" =~ ^[0-9]+$ ]] || die "Could not parse ordinal from primary pod ${PRIMARY_POD}"

if (( PRIMARY_ORDINAL < 0 || PRIMARY_ORDINAL >= STS_REPLICAS )); then
  die "Primary pod ${PRIMARY_POD} is outside StatefulSet ordinal range"
fi

run_cmd "Verifying primary pod exists" \
  kubectl -n "${NAMESPACE}" get pod "${PRIMARY_POD}"

run_cmd "Waiting for primary pod to be Ready" \
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${PRIMARY_POD}" --timeout="${WAIT_TIMEOUT}"

discover_replica_health

if [[ "${BACKUP_ONLY}" != "true" ]]; then
  select_target_replicas
fi

TIMESTAMP="$(date +'%Y%m%d-%H%M%S')"
if [[ ${#TARGET_REPLICAS[@]} -eq 1 ]]; then
  DUMP_FILE="${WORKDIR}/mariadb-reseed-${TARGET_REPLICAS[0]}-${TIMESTAMP}.sql"
elif [[ "${BACKUP_ONLY}" == "true" ]]; then
  DUMP_FILE="${WORKDIR}/mariadb-backup-${PRIMARY_POD}-${TIMESTAMP}.sql"
else
  DUMP_FILE="${WORKDIR}/mariadb-reseed-all-unhealthy-${TIMESTAMP}.sql"
fi

MASTER_FQDN="${PRIMARY_POD}.${STS_NAME}-internal.${NAMESPACE}.svc.cluster.local"

printf '\n'
printf 'Discovery summary:\n'
printf '  Namespace:         %s\n' "${NAMESPACE}"
printf '  StatefulSet:       %s\n' "${STS_NAME}"
printf '  MariaDB CR:        %s\n' "${MARIADB_CR}"
printf '  Primary pod:       %s\n' "${PRIMARY_POD}"
printf '  Primary endpoint:  %s\n' "${MASTER_FQDN}"
if [[ ${#UNHEALTHY_REPLICAS[@]} -gt 0 ]]; then
  printf '  Unhealthy replicas:%s\n' ""
  for pod in "${UNHEALTHY_REPLICAS[@]}"; do
    printf '                     %s\n' "${pod}"
  done
else
  printf '  Unhealthy replicas: none detected\n'
fi
if [[ ${#HEALTHY_REPLICAS[@]} -gt 0 ]]; then
  printf '  Healthy replicas:  %s\n' "${HEALTHY_REPLICAS[*]}"
fi
if [[ ${#TARGET_REPLICAS[@]} -gt 0 ]]; then
  printf '  Target replicas:   %s\n' "${TARGET_REPLICAS[*]}"
fi
printf '  Backup only:       %s\n' "${BACKUP_ONLY}"
printf '  Root secret:       %s\n' "${ROOT_SECRET}"
printf '  Repl secret:       %s\n' "${REPL_SECRET}"
printf '  Dump file:         %s\n' "${DUMP_FILE}"
printf '\n'

if [[ "${INTERACTIVE}" == "true" ]]; then
  if ! prompt_confirm "Proceed with reseed using these discovered values?"; then
    die "Aborted by user"
  fi
fi

if [[ "${INTERACTIVE}" == "true" ]]; then
  printf '\n' >&2
  log "Taking fresh dump from primary ${PRIMARY_POD}"
  printf 'Command:\n' >&2
  printf '  kubectl -n %q exec %q -- sh -c %q > %q\n' \
    "${NAMESPACE}" "${PRIMARY_POD}" "exec mariadb-dump --all-databases --single-transaction --master-data=2 -uroot -p'*****'" "${DUMP_FILE}" >&2
  if ! prompt_confirm "Run this dump command?"; then
    die "Aborted by user"
  fi
else
  log "Taking fresh dump from primary ${PRIMARY_POD}"
fi

kubectl -n "${NAMESPACE}" exec "${PRIMARY_POD}" -- sh -c \
  "exec mariadb-dump --all-databases --single-transaction --master-data=2 -uroot -p'${ROOT_PASSWORD}'" \
  > "${DUMP_FILE}"

validate_dump_file "${DUMP_FILE}"

if [[ "${BACKUP_ONLY}" == "true" ]]; then
  SUCCESS="true"
  cat <<EOF

Backup completed.

Primary pod:      ${PRIMARY_POD}
Primary endpoint: ${MASTER_FQDN}
Dump file:        ${DUMP_FILE}
Repl secret:      ${REPL_SECRET}

EOF
  exit 0
fi

CHANGE_MASTER_LINE="$(grep -m1 -E 'CHANGE MASTER TO MASTER_LOG_FILE=' "${DUMP_FILE}" || true)"
[[ -n "${CHANGE_MASTER_LINE}" ]] || die "Could not find CHANGE MASTER TO coordinates in dump"

MASTER_LOG_FILE="$(printf '%s\n' "${CHANGE_MASTER_LINE}" | sed -n "s/.*MASTER_LOG_FILE='\([^']*\)'.*/\1/p")"
MASTER_LOG_POS="$(printf '%s\n' "${CHANGE_MASTER_LINE}" | sed -n "s/.*MASTER_LOG_POS=\([0-9][0-9]*\).*/\1/p")"

[[ -n "${MASTER_LOG_FILE}" ]] || die "Could not parse MASTER_LOG_FILE from dump"
[[ -n "${MASTER_LOG_POS}" ]] || die "Could not parse MASTER_LOG_POS from dump"

log "Dump coordinates: ${MASTER_LOG_FILE}:${MASTER_LOG_POS}"

CHANGE_MASTER_SQL="CHANGE MASTER TO
  MASTER_HOST='${MASTER_FQDN}',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='${REPL_PASSWORD}',
  MASTER_LOG_FILE='${MASTER_LOG_FILE}',
  MASTER_LOG_POS=${MASTER_LOG_POS},
  MASTER_SSL=1,
  MASTER_SSL_CA='/etc/pki/ca.crt',
  MASTER_SSL_CERT='/etc/pki/client.crt',
  MASTER_SSL_KEY='/etc/pki/client.key',
  MASTER_SSL_VERIFY_SERVER_CERT=1;
FLUSH PRIVILEGES;
START SLAVE;"

CHANGE_MASTER_SQL_DISPLAY="CHANGE MASTER TO
  MASTER_HOST='${MASTER_FQDN}',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='*****',
  MASTER_LOG_FILE='${MASTER_LOG_FILE}',
  MASTER_LOG_POS=${MASTER_LOG_POS},
  MASTER_SSL=1,
  MASTER_SSL_CA='/etc/pki/ca.crt',
  MASTER_SSL_CERT='/etc/pki/client.crt',
  MASTER_SSL_KEY='/etc/pki/client.key',
  MASTER_SSL_VERIFY_SERVER_CERT=1;
FLUSH PRIVILEGES;
START SLAVE;"

for REPLICA_POD in "${TARGET_REPLICAS[@]}"; do
  printf '\n'
  log "Starting reseed workflow for ${REPLICA_POD}"
  reseed_replica "${REPLICA_POD}"
done

SUCCESS="true"

cat <<EOF

Completed.

Primary pod:      ${PRIMARY_POD}
Primary endpoint: ${MASTER_FQDN}
Target replicas:  ${TARGET_REPLICAS[*]}
Completed:        ${COMPLETED_REPLICAS[*]}
Dump file:        ${DUMP_FILE}
Coordinates:      ${MASTER_LOG_FILE}:${MASTER_LOG_POS}
Repl secret:      ${REPL_SECRET}

EOF

if [[ ${#FINAL_STATUS_SUMMARIES[@]} -gt 0 ]]; then
  printf 'Final replica summaries:\n'
  for status_summary in "${FINAL_STATUS_SUMMARIES[@]}"; do
    printf '  %s\n' "${status_summary}"
  done
  printf '\n'
fi
