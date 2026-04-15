#!/bin/bash
#
# uninstall-freezer-client.sh
# Removes Freezer Agent + Scheduler from a Freezer-Client VM.
# Stops the scheduler, removes venv, config files, and optionally
# deregisters the client from the Freezer API.
#

set -o pipefail

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

VENV_DIR="$HOME/freezer-venv"
OPENRC_FILE="$HOME/openrc"
CLIENT_CONFIG="$HOME/client_register_config.json"
SCHEDULER_CONF="/etc/freezer/freezer-scheduler.conf"
LOG_DIR="/var/log/freezer"
JOBS_DIR="$HOME/freezer-bkp-dir"

# ── Confirm with user ────────────────────────────────────────────
confirm() {
    echo ""
    echo "============================================"
    echo "  Freezer Client Uninstaller"
    echo "============================================"
    echo ""
    echo "  This will remove:"
    echo "    - Freezer scheduler process"
    echo "    - Python virtual environment: ${VENV_DIR}"
    echo "    - OpenRC file: ${OPENRC_FILE}"
    echo "    - Scheduler config: ${SCHEDULER_CONF}"
    echo "    - Client config: ${CLIENT_CONFIG}"
    echo "    - Log directory: ${LOG_DIR}"
    echo "    - Jobs directory: ${JOBS_DIR}"
    echo ""

    read -rp "Continue? (y/N): " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi
}

# ── Stop freezer-scheduler ───────────────────────────────────────
stop_scheduler() {
    info "Stopping freezer-scheduler..."

    # Try using the freezer-scheduler stop command first
    if [ -f "$VENV_DIR/bin/activate" ] && [ -f "$OPENRC_FILE" ]; then
        # shellcheck disable=SC1091
        source "$VENV_DIR/bin/activate" 2>/dev/null || true
        # shellcheck disable=SC1090
        source "$OPENRC_FILE" 2>/dev/null || true

        if command -v freezer-scheduler &>/dev/null; then
            freezer-scheduler stop \
                --config-file "$SCHEDULER_CONF" 2>/dev/null || true
        fi
        deactivate 2>/dev/null || true
    fi

    # Kill any remaining freezer-scheduler processes
    if pgrep -f "freezer-scheduler" &>/dev/null; then
        info "Killing remaining freezer-scheduler processes..."
        pkill -f "freezer-scheduler" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        if pgrep -f "freezer-scheduler" &>/dev/null; then
            pkill -9 -f "freezer-scheduler" 2>/dev/null || true
        fi
    fi

    info "Freezer scheduler stopped."
}

# ── Deregister client from Freezer API ───────────────────────────
deregister_client() {
    if [ ! -f "$CLIENT_CONFIG" ]; then
        warn "No client config found, skipping deregistration."
        return
    fi

    local client_id
    client_id=$(python3 -c "import json; print(json.load(open('$CLIENT_CONFIG'))['client_id'])" 2>/dev/null || true)

    if [ -z "$client_id" ]; then
        warn "Could not read client_id from ${CLIENT_CONFIG}, skipping deregistration."
        return
    fi

    read -rp "Deregister client '${client_id}' from Freezer API? (y/N): " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Skipping client deregistration."
        return
    fi

    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        warn "Virtual environment not found at ${VENV_DIR}, skipping deregistration."
        return
    fi

    if [ ! -f "$OPENRC_FILE" ]; then
        warn "OpenRC file not found at ${OPENRC_FILE}, skipping deregistration."
        return
    fi

    info "Activating virtual environment at ${VENV_DIR}..."
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    # Verify the freezer CLI is available from the venv
    if ! command -v freezer &>/dev/null; then
        warn "freezer CLI not found in ${VENV_DIR}. Was it installed correctly?"
        deactivate 2>/dev/null || true
        read -rp "Continue with uninstall anyway? (y/N): " force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            error "Aborting uninstall. Reinstall freezer in the venv and retry."
        fi
        return
    fi

    # Verify freezer CLI is coming from the venv, not the system
    local freezer_path
    freezer_path="$(command -v freezer)"
    if [[ "$freezer_path" != "$VENV_DIR"* ]]; then
        warn "freezer CLI found at ${freezer_path} (not from ${VENV_DIR})."
        warn "This may cause authentication issues. Expected it inside the venv."
        deactivate 2>/dev/null || true
        read -rp "Continue with uninstall anyway? (y/N): " force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            error "Aborting uninstall. Check the virtual environment and retry."
        fi
        return
    fi

    info "Sourcing openrc at ${OPENRC_FILE}..."
    # shellcheck disable=SC1090
    source "$OPENRC_FILE"

    info "Deregistering client '${client_id}'..."
    if freezer client-delete "${client_id}"; then
        info "Client '${client_id}' deregistered."
    else
        warn "Client deregistration failed."
        deactivate 2>/dev/null || true
        read -rp "Continue with uninstall anyway? (y/N): " force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            error "Aborting uninstall. Fix the issue and retry."
        fi
        return
    fi

    deactivate 2>/dev/null || true
}

# ── Remove files and directories ─────────────────────────────────
remove_files() {
    info "Removing virtual environment: ${VENV_DIR}..."
    rm -rf "$VENV_DIR"

    info "Removing openrc: ${OPENRC_FILE}..."
    rm -f "$OPENRC_FILE"

    info "Removing client config: ${CLIENT_CONFIG}..."
    rm -f "$CLIENT_CONFIG"

    info "Removing scheduler config directory: /etc/freezer/..."
    sudo rm -rf /etc/freezer

    info "Removing log directory: ${LOG_DIR}..."
    sudo rm -rf "$LOG_DIR"

    info "Removing jobs directory: ${JOBS_DIR}..."
    rm -rf "$JOBS_DIR"
}

# ── Print summary ────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "============================================"
    echo "  Uninstall Complete"
    echo "============================================"
    echo ""
    echo "  Removed:"
    echo "    - Freezer scheduler process"
    echo "    - ${VENV_DIR}"
    echo "    - ${OPENRC_FILE}"
    echo "    - ${CLIENT_CONFIG}"
    echo "    - /etc/freezer/"
    echo "    - ${LOG_DIR}"
    echo "    - ${JOBS_DIR}"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────
main() {
    confirm
    stop_scheduler
    deregister_client
    remove_files
    print_summary
}

main "$@"
