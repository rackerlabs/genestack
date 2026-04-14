#!/bin/bash
#
# install-freezer-client.sh
# Installs Freezer Agent + Scheduler on a Freezer-Client VM.
# Creates openrc, freezer-scheduler.conf, and client_register_config.json
# from user-provided inputs, then registers the client with the Freezer API.
#

# ── Error trap: show line number on failure ────────────────────────
trap 'echo ""; echo "[ERROR] Script failed at line $LINENO. Command: $BASH_COMMAND"; exit 1' ERR
set -o pipefail

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Print DNS / connectivity troubleshooting hints ─────────────────
print_dns_hints() {
    echo ""
    echo "  Possible fixes:"
    echo ""
    echo "  1. Add an entry to /etc/hosts:"
    echo "       echo '<KEYSTONE_IP>  ${KEYSTONE_FQDN}' | sudo tee -a /etc/hosts"
    echo ""
    echo "  2. Configure a DNS server that knows about your OpenStack endpoints:"
    echo "       sudo sed -i '1s/^/nameserver <DNS_SERVER_IP>\n/' /etc/resolv.conf"
    echo "     or if using systemd-resolved:"
    echo "       sudo resolvectl dns <INTERFACE> <DNS_SERVER_IP>"
    echo "       sudo systemctl restart systemd-resolved"
    echo ""
    echo "  3. If behind a VPN or private network, ensure the VPN is connected"
    echo "     and routes to the OpenStack management network are in place."
    echo ""
    echo "  4. Verify with:"
    echo "       nslookup ${KEYSTONE_FQDN}"
    echo "       curl -sk https://${KEYSTONE_FQDN}/v3"
    echo ""
}

# ── Rollback: remove everything created during install ─────────────
rollback() {
    warn "Rolling back installation..."
    deactivate 2>/dev/null || true
    [ -d "$HOME/freezer-venv" ]                && rm -rf "$HOME/freezer-venv"        && info "Removed $HOME/freezer-venv"
    [ -f "$HOME/openrc" ]                      && rm -f  "$HOME/openrc"              && info "Removed $HOME/openrc"
    [ -f "$HOME/client_register_config.json" ]  && rm -f  "$HOME/client_register_config.json" && info "Removed $HOME/client_register_config.json"
    [ -d "/etc/freezer" ]                      && sudo rm -rf /etc/freezer           && info "Removed /etc/freezer/"
    [ -d "/var/log/freezer" ]                  && sudo rm -rf /var/log/freezer       && info "Removed /var/log/freezer/"
    [ -d "$HOME/freezer-bkp-dir" ]             && rm -rf "$HOME/freezer-bkp-dir"     && info "Removed $HOME/freezer-bkp-dir"
    info "Rollback complete."
}

# ── Globals (set after user input / OS detection) ──────────────────
KEYSTONE_FQDN=""
FREEZER_PASSWORD=""
CLIENT_ID=""
CLIENT_OS=""
OS_VERSION=""
ARCH=""
VENV_DIR=""

# ── Auto-detect OS ─────────────────────────────────────────────────
detect_os() {
    info "Detecting OS..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CLIENT_OS="${ID:-Linux}"
        OS_VERSION="${PRETTY_NAME:-${VERSION_ID:-unknown}}"
    elif command -v sw_vers &>/dev/null; then
        CLIENT_OS="macOS"
        OS_VERSION="$(sw_vers -productName) $(sw_vers -productVersion)"
    else
        CLIENT_OS="Linux"
        OS_VERSION="unknown"
    fi
    ARCH="$(uname -m)"
    info "Detected: ${CLIENT_OS} / ${OS_VERSION} / ${ARCH}"
}

# ── Collect user inputs ───────────────────────────────────────────
collect_inputs() {
    echo ""
    echo "============================================"
    echo "  Freezer Client Installer"
    echo "============================================"
    echo ""

    read -rp "Enter Keystone FQDN (e.g. keystone.cloud.dev): " KEYSTONE_FQDN
    if [ -z "$KEYSTONE_FQDN" ]; then
        error "Keystone FQDN cannot be empty"
    fi

    read -rsp "Enter Freezer service password (keystone_authtoken): " FREEZER_PASSWORD
    echo ""
    if [ -z "$FREEZER_PASSWORD" ]; then
        error "Freezer service password cannot be empty"
    fi

    read -rp "Enter client_id (e.g. backup-client-vm): " CLIENT_ID
    if [ -z "$CLIENT_ID" ]; then
        error "client_id cannot be empty"
    fi
}

# ── Install system packages and Python venv ────────────────────────
install_packages() {
    info "Installing system packages..."

    if command -v apt-get &>/dev/null; then
        info "Running apt-get update..."
        apt-get update
        info "Installing python3-dev python3-venv..."
        apt-get install -y python3-dev python3-venv
    elif command -v dnf &>/dev/null; then
        dnf install -y python3-devel python3
    elif command -v yum &>/dev/null; then
        yum install -y python3-devel python3
    else
        warn "Could not detect package manager. Ensure python3-dev and python3-venv are installed."
    fi

    VENV_DIR="$HOME/freezer-venv"
    info "Creating Python virtual environment at ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"

    info "Activating virtual environment..."
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    info "Installing freezer and pymysql via pip..."
    pip install --upgrade pip
    pip install pymysql freezer

    info "Packages installed successfully."
}

# ── Create openrc ─────────────────────────────────────────────────
create_openrc() {
    local openrc_file="$HOME/openrc"
    info "Writing ${openrc_file}..."

    cat > "$openrc_file" <<EOF
# ==================== BASIC AUTHENTICATION ====================
export OS_AUTH_URL="https://${KEYSTONE_FQDN}/v3"
export OS_USERNAME=admin
export OS_PASSWORD=password
export OS_PROJECT_NAME=admin
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default

# ==================== API VERSIONS ====================
export OS_IDENTITY_API_VERSION=3

# ==================== ENDPOINT CONFIGURATION ====================
export OS_ENDPOINT_TYPE=publicURL
export OS_REGION_NAME=RegionOne

# ==================== SSL CONFIGURATION ====================
export OS_INSECURE=true
export PYTHONHTTPSVERIFY=0
EOF

    chmod 600 "$openrc_file"
    info "Created ${openrc_file}"
}

# ── Create freezer-scheduler.conf ─────────────────────────────────
create_scheduler_conf() {
    local conf_dir="/etc/freezer"
    local conf_file="${conf_dir}/freezer-scheduler.conf"
    local log_dir="/var/log/freezer"

    info "Writing ${conf_file}..."

    mkdir -p "$conf_dir" "$log_dir"

    cat > "$conf_file" <<EOF
[DEFAULT]

freezer_endpoint_interface=public

# Logging Configuration
log_file = ${log_dir}/scheduler.log
log_dir = ${log_dir}
use_syslog = False

# Client Identification
client_id = ${CLIENT_ID}

# Jobs Directory
jobs_dir = ${HOME}/freezer-bkp-dir

# API Polling Interval (in seconds)
interval = 60

[keystone_authtoken]
auth_url = https://${KEYSTONE_FQDN}/v3
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = freezer
password = ${FREEZER_PASSWORD}
EOF

    chmod 640 "$conf_file"
    mkdir -p "$HOME/freezer-bkp-dir"
    info "Created ${conf_file}"
}

# ── Create client_register_config.json ────────────────────────────
create_client_config() {
    local config_file="$HOME/client_register_config.json"
    info "Writing ${config_file}..."

    cat > "$config_file" <<EOF
{
  "client_id": "${CLIENT_ID}",
  "client_name": "${CLIENT_ID}",
  "client_os": "${CLIENT_OS}",
  "architecture": "${ARCH}",
  "os_version": "${OS_VERSION}"
}
EOF

    info "Created ${config_file}"
}

# ── Register client with Freezer API ─────────────────────────────
register_client() {
    info "Sourcing openrc..."
    # shellcheck disable=SC1091
    source "$HOME/openrc"

    info "Checking DNS resolution for ${KEYSTONE_FQDN}..."
    if ! host "$KEYSTONE_FQDN" &>/dev/null && ! nslookup "$KEYSTONE_FQDN" &>/dev/null && ! getent hosts "$KEYSTONE_FQDN" &>/dev/null; then
        echo ""
        echo -e "${RED}[ERROR]${NC} Cannot resolve ${KEYSTONE_FQDN}. DNS resolution failed."
        print_dns_hints
        rollback
        error "Aborting install due to DNS resolution failure."
    fi
    info "DNS resolution OK for ${KEYSTONE_FQDN}"

    info "Checking HTTPS connectivity to Keystone endpoint..."
    if ! curl -sk --connect-timeout 10 "https://${KEYSTONE_FQDN}/v3" &>/dev/null; then
        warn "Cannot reach https://${KEYSTONE_FQDN}/v3 — Keystone may be unreachable. Continuing anyway."
    else
        info "Keystone endpoint reachable"
    fi

    info "Registering client '${CLIENT_ID}' with Freezer API..."
    if freezer client-register --file "$HOME/client_register_config.json"; then
        info "Client '${CLIENT_ID}' registered successfully."
    else
        warn "Client registration failed. Verify Freezer API is reachable and DNS resolves ${KEYSTONE_FQDN}."
        print_dns_hints
        read -rp "Continue with install anyway? (y/N): " force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            rollback
            error "Aborting install. Fix the issue and retry."
        fi
    fi
}

# ── Print summary ────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "============================================"
    echo "  Installation Complete"
    echo "============================================"
    echo ""
    echo "  Files created:"
    echo "    - $HOME/openrc"
    echo "    - /etc/freezer/freezer-scheduler.conf"
    echo "    - $HOME/client_register_config.json"
    echo ""
    echo "  Detected OS:    ${CLIENT_OS}"
    echo "  OS Version:     ${OS_VERSION}"
    echo "  Architecture:   ${ARCH}"
    echo "  Client ID:      ${CLIENT_ID}"
    echo "  Keystone FQDN:  ${KEYSTONE_FQDN}"
    echo ""
    echo "  Freezer scheduler is running."
    echo "  To reactivate the virtual environment in a new shell:"
    echo "    source $HOME/freezer-venv/bin/activate"
    echo "    source $HOME/openrc"
    echo ""
}

# ── Start freezer-scheduler ─────────────────────────────────────
start_scheduler() {
    info "Activating virtual environment..."
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    info "Sourcing openrc..."
    # shellcheck disable=SC1091
    source "$HOME/openrc"

    info "Starting freezer-scheduler..."
    freezer-scheduler start \
        --insecure \
        --config-file /etc/freezer/freezer-scheduler.conf

    info "Freezer scheduler started."
}

# ── Main ─────────────────────────────────────────────────────────
main() {
    detect_os
    collect_inputs
    install_packages
    create_openrc
    create_scheduler_conf
    create_client_config
    register_client
    start_scheduler
    print_summary
}

main "$@"
