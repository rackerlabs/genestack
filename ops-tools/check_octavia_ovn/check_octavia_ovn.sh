#!/usr/bin/env bash
# -----------------------------------------------
#                             _             _
#                            | |           | |
#   __ _  ___ _ __   ___  ___| |_ __ _  ___| | __
#  / _` |/ _ \ '_ \ / _ \/ __| __/ _` |/ __| |/ /
# | (_| |  __/ | | |  __/\__ \ || (_| | (__|   <
#  \__, |\___|_| |_|\___||___/\__\__,_|\___|_|\_\
#   __/ |            ops tools
#  |___/         check_octavia_ovn
# -----------------------------------------------
#
# Checks that every Octavia Load Balancer VIP has a healthy OVN port binding.
# For each LB, verifies whether listeners/pools are configured, finds the
# Neutron VIP port, queries OVN via kubectl-ko, and reports OK (chassis UUID
# present) or FAIL (chassis empty / []).
#
# Load balancers with no listeners and no pools are treated as healthy and are
# excluded from failover actions.
#
# LBs are checked in parallel. Results are collected and tallied at the end.
# Failed LBs are automatically failed over via `openstack loadbalancer failover`,
# but only once per failure cycle — the LB is tracked in a state file so it
# won't be failed over again on subsequent runs until it recovers (OK).
#
# Usage:
#   ./check_octavia_ovn.sh
#   ./check_octavia_ovn.sh --apply                # enable failover/state changes
#   ./check_octavia_ovn.sh --dry-run              # explicit dry-run
#   ./check_octavia_ovn.sh --log-file /var/log/octavia_ovn_check.log   # optional file copy
#   DEBUG=1 ./check_octavia_ovn.sh                # include raw OVN JSON output
#   PARALLEL=20 ./check_octavia_ovn.sh            # set max parallel jobs
#   DRY_RUN=0 ./check_octavia_ovn.sh              # env-var apply mode
#
# Env overrides:
#   PARALLEL=20, STATE_FILE=/tmp/x.state, FAILOVER_TIMEOUT=300 (seconds),
#   DRY_RUN=1 (default), LOG_FILE=/var/log/octavia_ovn_check.log
#
# Cron example (every 5 minutes):
#   */5 * * * * /usr/local/bin/check_octavia_ovn.sh --log-file /var/log/octavia_ovn_check.log
#
# Requirements:
#   - openstack CLI authenticated (clouds.yaml or sourced RC file)
#   - kubectl with ko plugin available and kubeconfig set
#   - jq
#   - bash 4.3+ (for wait -n)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"
PARALLEL="${PARALLEL:-10}"
STATE_FILE="${STATE_FILE:-/var/lib/check_octavia_ovn/failovers.state}"
FAILOVER_TIMEOUT="${FAILOVER_TIMEOUT:-300}"   # seconds before re-issuing a failover (default: 5 min)
DRY_RUN="${DRY_RUN:-1}"
LOG_FILE="${LOG_FILE:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
status()  { printf '[%s] [%-8s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"; }
ok()      { status "OK" "$1"; }
fail()    { status "FAIL" "$1" >&2; }
fover()   { status "FAILOVER" "$1"; }
skip()    { status "SKIP" "$1"; }
info()    { status "INFO" "$1"; }
die()     { status "ERROR" "$1" >&2; exit 1; }
section() { log "---- $* ----"; }

usage() {
    cat <<USAGE
Usage: $0 [--dry-run|-n] [--apply|-a] [--log-file PATH|-l PATH] [--help|-h]

Options:
  -n, --dry-run   Check and report only; do not run failover and do not change state (default)
  -a, --apply     Enable failover actions and state file updates
  -l, --log-file  Optional: append output to PATH while still writing to stdout/stderr
  -h, --help      Show this help

Env overrides:
  PARALLEL, STATE_FILE, FAILOVER_TIMEOUT, DRY_RUN, KUBECTL_CMD, DEBUG, LOG_FILE
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -a|--apply)
                DRY_RUN=0
                ;;
            -l|--log-file)
                shift
                [[ $# -gt 0 ]] || die "Missing value for --log-file"
                LOG_FILE="$1"
                ;;
            --log-file=*)
                LOG_FILE="${1#*=}"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
        shift
    done
}

init_logging() {
    if [[ -n "${LOGGING_INITIALIZED:-}" ]]; then
        return
    fi

    if [[ -z "${LOG_FILE}" ]]; then
        LOGGING_INITIALIZED=1
        export LOGGING_INITIALIZED
        return
    fi

    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if mkdir -p "$log_dir" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
        LOGGING_INITIALIZED=1
        export LOGGING_INITIALIZED LOG_FILE
        exec > >(tee -a "$LOG_FILE") 2>&1
        return
    fi

    LOGGING_INITIALIZED=1
    export LOGGING_INITIALIZED
    status "WARN" "Cannot write log file ${LOG_FILE}; continuing with stdout/stderr only"
}

check_deps() {
    for cmd in openstack kubectl jq; do
        command -v "$cmd" &>/dev/null || die "Required command not found: ${cmd}"
    done
}

# ---------------------------------------------------------------------------
# State file helpers
#
# Format: one line per failed-over LB
#   <lb_id> <iso_timestamp>
# ---------------------------------------------------------------------------
state_init() {
    local dir
    dir=$(dirname "$STATE_FILE")

    if mkdir -p "$dir" 2>/dev/null && touch "$STATE_FILE" 2>/dev/null; then
        return
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        STATE_FILE=$(mktemp)
        log "Dry-run: cannot write configured state file; using temporary state file: ${STATE_FILE}"
        return
    fi

    die "Cannot initialize state file: ${STATE_FILE}"
}

state_has() {
    local lb_id="$1"
    grep -q "^${lb_id} " "$STATE_FILE" 2>/dev/null
}

state_add() {
    local lb_id="$1"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "${lb_id} ${ts}" >> "$STATE_FILE"
}

state_remove() {
    local lb_id="$1"
    # Re-write the file without this LB's entry (in-place via temp file)
    local tmp
    tmp=$(mktemp)
    grep -v "^${lb_id} " "$STATE_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$STATE_FILE"
}

state_update() {
    # Replace the timestamp for an existing entry (remove + re-add)
    local lb_id="$1"
    state_remove "$lb_id"
    state_add "$lb_id"
}

state_age_seconds() {
    # Return how many seconds have elapsed since the state entry was recorded
    local lb_id="$1"
    local ts then now
    ts=$(state_timestamp "$lb_id")
    if [[ -z "$ts" ]]; then
        echo 0
        return
    fi
    # Try GNU date first (Linux), fall back to BSD date (macOS)
    if ! then=$(date -d "$ts" '+%s' 2>/dev/null); then
        then=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$ts" '+%s' 2>/dev/null) || { echo 0; return; }
    fi
    now=$(date '+%s')
    echo $(( now - then ))
}

state_timestamp() {
    local lb_id="$1"
    grep "^${lb_id} " "$STATE_FILE" 2>/dev/null | awk '{print $2}'
}

# ---------------------------------------------------------------------------
# Per-LB check — runs in a subshell, writes result to RESULT_DIR/<lb_id>
#
# Result file format (three lines):
#   OK|FAIL
#   <lb_name>
#   <lb_id>|<message>
# ---------------------------------------------------------------------------
check_lb() {
    local lb="$1"
    local result_dir="$2"

    local LB_ID LB_NAME VIP_ADDR PORT_ID OVN_JSON ROW_COUNT CHASSIS_TAG CHASSIS_VALUE
    local LB_DETAILS LISTENER_COUNT POOL_COUNT
    LB_ID=$(echo "$lb"   | jq -r '.id')
    LB_NAME=$(echo "$lb" | jq -r '.name')
    VIP_ADDR=$(echo "$lb" | jq -r '.vip_address')

    local result_file="${result_dir}/${LB_ID}"

    write_result() { printf '%s\n%s\n%s\n' "$1" "$LB_NAME" "${LB_ID}|$2" > "$result_file"; }

    info "Checking ${LB_NAME} (${LB_ID}) vip=${VIP_ADDR}"

    # 1. Fetch full LB details so we can evaluate configuration completeness.
    if ! LB_DETAILS=$(openstack loadbalancer show "${LB_ID}" --format json 2>/dev/null); then
        fail "${LB_NAME} (${LB_ID}) | openstack loadbalancer show failed"
        write_result "FAIL" "openstack loadbalancer show failed"
        return
    fi

    LISTENER_COUNT=$(echo "$LB_DETAILS" | jq '(.listeners // []) | length')
    POOL_COUNT=$(echo "$LB_DETAILS" | jq '(.pools // []) | length')

    if [[ "$LISTENER_COUNT" -eq 0 && "$POOL_COUNT" -eq 0 ]]; then
        ok "${LB_NAME} (${LB_ID}) | active but unconfigured (no listeners or pools)"
        write_result "OK" "no listeners/pools configured; skipped OVN binding check"
        return
    fi

    # 2. Get VIP port ID from the full LB object
    PORT_ID=$(echo "$LB_DETAILS" | jq -r '.vip_port_id // empty')

    if [[ -z "$PORT_ID" ]]; then
        fail "${LB_NAME} (${LB_ID}) | could not determine VIP port ID"
        write_result "FAIL" "could not determine VIP port ID"
        return
    fi

    info "${LB_NAME} (${LB_ID}) | listeners=${LISTENER_COUNT} pools=${POOL_COUNT} port=${PORT_ID}"

    # 3. Query OVN port binding
    # Response: {"data": [["<logical_port>", ["uuid","<chassis-uuid>"], ...]], "headings": [...]}
    # Unbound:  {"data": [], ...}  or chassis field is []
    if ! OVN_JSON=$(${KUBECTL_CMD} ko sbctl \
            --format=json \
            --columns=logical_port,chassis,up,mac,options,type \
            find port_binding logical_port="${PORT_ID}" 2>/dev/null); then
        fail "${LB_NAME} (${LB_ID}) | kubectl ko sbctl failed for port ${PORT_ID}"
        write_result "FAIL" "kubectl ko sbctl failed for port ${PORT_ID}"
        return
    fi

    if [[ "${DEBUG:-0}" == "1" ]]; then
        info "${LB_NAME} (${LB_ID}) | OVN output"
        echo "$OVN_JSON" | jq '.' | sed "s/^/    [${LB_NAME}] /"
    fi

    # 4. Validate chassis
    ROW_COUNT=$(echo "$OVN_JSON" | jq '.data | length')

    if [[ "$ROW_COUNT" -eq 0 ]]; then
        fail "${LB_NAME} (${LB_ID}) | port ${PORT_ID} | no port_binding row found in OVN"
        write_result "FAIL" "no port_binding row found in OVN (port ${PORT_ID})"
        return
    fi

    CHASSIS_TAG=$(echo "$OVN_JSON"   | jq -r '.data[0][1][0] // empty')
    CHASSIS_VALUE=$(echo "$OVN_JSON" | jq -r '.data[0][1][1] // empty')

    if [[ "$CHASSIS_TAG" == "uuid" && -n "$CHASSIS_VALUE" ]]; then
        ok "${LB_NAME} (${LB_ID}) | port=${PORT_ID} chassis=${CHASSIS_VALUE}"
        write_result "OK" "chassis=${CHASSIS_VALUE}"
    else
        fail "${LB_NAME} (${LB_ID}) | port ${PORT_ID} | no chassis binding"
        write_result "FAIL" "no chassis binding (port ${PORT_ID})"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
parse_args "$@"
init_logging
check_deps
state_init

section "Octavia Amphora OVN Check"
log "Parallel jobs : ${PARALLEL}"
log "State file    : ${STATE_FILE}"
log "Log file      : ${LOG_FILE:-journald only}"
if [[ "$DRY_RUN" == "1" ]]; then
    log "Mode          : DRY-RUN (no failover/state changes)"
else
    log "Mode          : APPLY"
fi

# Fetch Amphora load balancers upfront
section "Discovery"
log "Fetching load balancers for provider amphora..."
LB_JSON=$(openstack loadbalancer list --provider amphora --format json 2>/dev/null) \
    || die "Failed to list amphora load balancers. Is the OpenStack CLI authenticated?"

LB_COUNT=$(echo "$LB_JSON" | jq 'length')
log "Discovered ${LB_COUNT} amphora load balancer(s)."

if [[ "$LB_COUNT" -eq 0 ]]; then
    log "No amphora load balancers found. Exiting."
    exit 0
fi

# Temp dir for per-LB result files; cleaned up automatically on exit
RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# ---------------------------------------------------------------------------
# Dispatch parallel jobs, capped at $PARALLEL concurrent processes
# ---------------------------------------------------------------------------
job_count=0

while IFS= read -r lb; do
    check_lb "$lb" "$RESULT_DIR" &
    (( job_count++ )) || true

    # Once we hit the cap, wait for any one child to finish before spawning more
    if [[ $job_count -ge $PARALLEL ]]; then
        wait -n 2>/dev/null || true   # bash 4.3+
        (( job_count-- )) || true
    fi
done < <(echo "$LB_JSON" | jq -c '.[]')

# Wait for all remaining background jobs
wait

# ---------------------------------------------------------------------------
# Tally results from temp files
# ---------------------------------------------------------------------------
OK_LBS=()
UNCONFIGURED_LBS=()
FAILED_LBS=()
FAILED_MSGS=()

for result_file in "$RESULT_DIR"/*; do
    [[ -f "$result_file" ]] || continue
    status=$(sed -n '1p' "$result_file")
    lb_name=$(sed -n '2p' "$result_file")
    payload=$(sed -n '3p' "$result_file")
    lb_id="${payload%%|*}"
    message="${payload#*|}"

    if [[ "$status" == "OK" ]]; then
        if [[ "$message" == "no listeners/pools configured; skipped OVN binding check" ]]; then
            UNCONFIGURED_LBS+=("${lb_name} (${lb_id})")
        else
            OK_LBS+=("$lb_name")
        fi
        # Clear from state file if it was previously failed over — it's healthy again
        if state_has "$lb_id"; then
            local_ts=$(state_timestamp "$lb_id")
            if [[ "$DRY_RUN" == "1" ]]; then
                log "Dry-run: would clear failover record for ${lb_name} (failed over at ${local_ts}, now healthy)"
            else
                state_remove "$lb_id"
                info "Cleared failover record for ${lb_name} (previous failover at ${local_ts})"
            fi
        fi
    else
        FAILED_LBS+=("$lb_name")
        FAILED_MSGS+=("${lb_name}: ${message}")
    fi
done

# ---------------------------------------------------------------------------
# Failover unhealthy LBs (only if not already recorded in state)
# ---------------------------------------------------------------------------
FAILOVER_LBS=()
WOULD_FAILOVER_LBS=()
SKIPPED_LBS=()

for result_file in "$RESULT_DIR"/*; do
    [[ -f "$result_file" ]] || continue
    status=$(sed -n '1p' "$result_file")
    lb_name=$(sed -n '2p' "$result_file")
    payload=$(sed -n '3p' "$result_file")
    lb_id="${payload%%|*}"

    [[ "$status" == "OK" ]] && continue

    if state_has "$lb_id"; then
        local_ts=$(state_timestamp "$lb_id")
        age=$(state_age_seconds "$lb_id")
        if [[ $age -lt $FAILOVER_TIMEOUT ]]; then
            remaining=$(( FAILOVER_TIMEOUT - age ))
            skip "${lb_name} (${lb_id}) | failover already issued ${age}s ago; retry in ${remaining}s"
            SKIPPED_LBS+=("$lb_name")
        else
            if [[ "$DRY_RUN" == "1" ]]; then
                fover "Dry-run: ${lb_name} (${lb_id}) | still unhealthy after ${age}s; would re-issue failover"
                WOULD_FAILOVER_LBS+=("${lb_name} (${lb_id})")
            else
                fover "${lb_name} (${lb_id}) | still unhealthy after ${age}s; re-issuing failover"
                if openstack loadbalancer failover "${lb_id}" 2>/dev/null; then
                    state_update "$lb_id"
                    fover "${lb_name} (${lb_id}) | failover re-issued and state refreshed"
                    FAILOVER_LBS+=("$lb_name")
                else
                    fail "${lb_name} (${lb_id}) | failover command failed"
                fi
            fi
        fi
    else
        if [[ "$DRY_RUN" == "1" ]]; then
            fover "Dry-run: ${lb_name} (${lb_id}) | would trigger failover"
            WOULD_FAILOVER_LBS+=("${lb_name} (${lb_id})")
        else
            fover "${lb_name} (${lb_id}) | triggering failover"
            if openstack loadbalancer failover "${lb_id}" 2>/dev/null; then
                state_add "$lb_id"
                fover "${lb_name} (${lb_id}) | failover issued and recorded"
                FAILOVER_LBS+=("$lb_name")
            else
                fail "${lb_name} (${lb_id}) | failover command failed"
            fi
        fi
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Summary"
log "Healthy        : ${#OK_LBS[@]}"
log "Unconfigured   : ${#UNCONFIGURED_LBS[@]}"
log "Failed         : ${#FAILED_LBS[@]}"
if [[ "$DRY_RUN" == "1" ]]; then
    log "Would fail over: ${#WOULD_FAILOVER_LBS[@]}"
else
    log "Failed over    : ${#FAILOVER_LBS[@]}"
fi
log "Skipped        : ${#SKIPPED_LBS[@]}"

if [[ ${#FAILED_LBS[@]} -gt 0 ]]; then
    section "Failed Load Balancers"
    for msg in "${FAILED_MSGS[@]}"; do
        log " - ${msg}"
    done

    if [[ "$DRY_RUN" == "1" && ${#WOULD_FAILOVER_LBS[@]} -gt 0 ]]; then
        section "Would Be Failed Over"
        for name in "${WOULD_FAILOVER_LBS[@]}"; do
            log " - ${name}"
        done
    fi

    if [[ "$DRY_RUN" != "1" && ${#FAILOVER_LBS[@]} -gt 0 ]]; then
        section "Newly Failed Over"
        for name in "${FAILOVER_LBS[@]}"; do
            log " - ${name}"
        done
    fi

    if [[ ${#SKIPPED_LBS[@]} -gt 0 ]]; then
        section "Skipped"
        for name in "${SKIPPED_LBS[@]}"; do
            log " - ${name}"
        done
    fi

    exit 1   # non-zero exit so cron monitoring tools can detect failures
fi

if [[ ${#UNCONFIGURED_LBS[@]} -gt 0 ]]; then
    section "Active But Unconfigured"
    for name in "${UNCONFIGURED_LBS[@]}"; do
        log " - ${name}"
    done
    log "Result: active but unconfigured load balancers were treated as healthy."
else
    log "Result: all configured load balancers have healthy OVN port bindings."
fi
exit 0
