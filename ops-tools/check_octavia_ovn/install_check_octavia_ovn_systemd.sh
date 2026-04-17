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

set -euo pipefail

SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="check_octavia_ovn.sh"
SERVICE_NAME="check-octavia-ovn.service"
TIMER_NAME="check-octavia-ovn.timer"

INSTALL_SCRIPT_PATH="/usr/local/bin/${SCRIPT_NAME}"
INSTALL_SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
INSTALL_TIMER_PATH="/etc/systemd/system/${TIMER_NAME}"
TIMER_OVERRIDE_DIR="/etc/systemd/system/${TIMER_NAME}.d"
TIMER_OVERRIDE_FILE="${TIMER_OVERRIDE_DIR}/override.conf"
STATE_DIR="/var/lib/check_octavia_ovn"
ENV_FILE="/etc/default/check-octavia-ovn"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run this installer as root (for example: sudo $0)"
    fi
}

check_source_files() {
    local path
    for path in \
        "${SCRIPT_SOURCE_DIR}/${SCRIPT_NAME}" \
        "${SCRIPT_SOURCE_DIR}/${SERVICE_NAME}" \
        "${SCRIPT_SOURCE_DIR}/${TIMER_NAME}"; do
        [[ -f "${path}" ]] || die "Required file not found: ${path}"
    done
}

install_files() {
    log "Installing ${SCRIPT_NAME} to ${INSTALL_SCRIPT_PATH}"
    install -D -m 0755 "${SCRIPT_SOURCE_DIR}/${SCRIPT_NAME}" "${INSTALL_SCRIPT_PATH}"

    log "Installing ${SERVICE_NAME} to ${INSTALL_SERVICE_PATH}"
    install -D -m 0644 "${SCRIPT_SOURCE_DIR}/${SERVICE_NAME}" "${INSTALL_SERVICE_PATH}"

    log "Installing ${TIMER_NAME} to ${INSTALL_TIMER_PATH}"
    install -D -m 0644 "${SCRIPT_SOURCE_DIR}/${TIMER_NAME}" "${INSTALL_TIMER_PATH}"

    log "Ensuring timer override directory exists at ${TIMER_OVERRIDE_DIR}"
    install -d -m 0755 "${TIMER_OVERRIDE_DIR}"

    log "Ensuring state directory exists at ${STATE_DIR}"
    install -d -m 0755 "${STATE_DIR}"

    if [[ ! -f "${ENV_FILE}" ]]; then
        log "Creating optional environment override file at ${ENV_FILE}"
        cat > "${ENV_FILE}" <<'EOF'
# Optional overrides for check-octavia-ovn.service
# PARALLEL=10
# FAILOVER_TIMEOUT=300
# Preserve failover history across runs:
# STATE_FILE=/var/lib/check_octavia_ovn/failovers.state
# LOG_FILE=/var/log/octavia_ovn_check.log
# KUBECTL_CMD=kubectl
# DEBUG=0
EOF
    fi

    if [[ ! -f "${TIMER_OVERRIDE_FILE}" ]]; then
        log "Creating optional timer override file at ${TIMER_OVERRIDE_FILE}"
        cat > "${TIMER_OVERRIDE_FILE}" <<'EOF'
# Optional systemd timer overrides for check-octavia-ovn.timer
# To change the run interval, uncomment the lines below and set the value you want.
#
# [Timer]
# OnUnitActiveSec=
# OnUnitActiveSec=5min
EOF
    fi
}

enable_timer() {
    log "Reloading systemd units"
    systemctl daemon-reload

    log "Enabling and starting ${TIMER_NAME}"
    systemctl enable --now "${TIMER_NAME}"
}

show_status() {
    log "Timer status"
    systemctl --no-pager --full status "${TIMER_NAME}" || true
}

require_root
check_source_files
install_files
enable_timer
show_status
