# -----------------------------------------------
#                             _             _
#                            | |           | |
#   __ _  ___ _ __   ___  ___| |_ __ _  ___| | __
#  / _` |/ _ \ '_ \ / _ \/ __| __/ _` |/ __| |/ /
# | (_| |  __/ | | |  __/\__ \ || (_| | (__|   <
#  \__, |\___|_| |_|\___||___/\__\__,_|\___|_|\_\
#   __/ |           ops scripts
#  |___/
# -----------------------------------------------
#!/usr/bin/env bash

# Copyright 2024-Present, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Globals
BASEDIR=${BASEDIR:-/opt/genestack}
if [ -f "${BASEDIR}/scripts/genestack.rc" ]; then
    source "${BASEDIR}/scripts/genestack.rc"
fi

test -f ~/.rackspace/datacenter && export RAX_DC="$(cat ~/.rackspace/datacenter |tr '[:upper:]' '[:lower:]')"
test -f /etc/openstack_deploy/openstack_inventory.json && export RPC_CONFIG_IN_PLACE=true || export RPC_CONFIG_IN_PLACE=false

# Global functions
# Function to wait for cloud-init to finish.
# BLOCKING if cloud-init is found and will retur exit code.
wait_for_cloud_init() {
    if command -v cloud-init &> /dev/null; then
        cloud-init status --wait
        return $?
    else
        echo "Error: cloud-init command not found."
        return 3
    fi
}

# Function to wait for Apt and DNF locks, then install packages
wait_and_install_packages() {
    local sleep_time=5  # Default sleep time between checks (in seconds)
    local pkg_manager=""
    local apt_packages=("python3-pip" "python3-venv" "python3-dev" "jq" "build-essential" "curl" "wget")
    local dnf_packages=("python3-pip" "python3-venv" "python3-dev" "jq" "build-essential" "curl" "wget")

    # Check for Apt locks
    echo "Checking for Apt locks..."
    while sudo fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo "Apt lock detected. Waiting for it to be released..."
        sleep "$sleep_time"
    done

    # Check for DNF process (indicating a DNF operation)
    echo "Checking for DNF locks..."
    while pgrep dnf >/dev/null; do
        echo "DNF process detected. Waiting for it to finish..."
        sleep "$sleep_time"
    done

    echo "No package manager locks or active processes found. Proceeding with installation."

    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        pkg_manager="apt"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
    else
        echo "Error: Neither Apt nor DNF package manager found. Cannot install packages."
        return 1
    fi

    # Install packages based on detected manager
    if [[ "$pkg_manager" == "apt" ]]; then
        echo "Detected Apt. Installing packages: ${apt_packages[@]}"
        sudo apt update
        sudo apt install -y "${apt_packages[@]}" # -y to auto-confirm installations
    elif [[ "$pkg_manager" == "dnf" ]]; then
        echo "Detected DNF. Installing packages: ${dnf_packages[@]}"
        sudo dnf check-update # Checks for updates, but does not download or install packages
        sudo dnf install -y "${dnf_packages[@]}" # -y to auto-confirm installations
    fi

    echo "Package installation complete."
}

function success {
  echo -e "\n\n\x1B[32m>> $1\x1B[39m"
}

function error {
  >&2 echo -e "\n\n\x1B[31m>> $1\x1B[39m"
  exit 1
}

function message {
  echo -n -e "\n\x1B[32m$1\x1B[39m"
}

# Detect OS and architecture for tool downloads.
function detectPlatform() {
    # Detect OS
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="darwin" ;;
        *)
            echo "Error: Unsupported operating system: $(uname -s)" >&2
            return 1
            ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        amd64)   arch="amd64" ;;
        aarch64) arch="arm64" ;;
        arm64)   arch="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac
}

# Install yq binary
# Supports Linux (amd64/arm64) and macOS (Intel/Apple Silicon)
# Usage: installYq
# Override these environment variables for air-gapped or internal artifactory environments.
function installYq() {
    echo "Installing yq..."
    local github_mirror_url="${GITHUB_MIRROR_URL:-https://github.com}"
    local version="${YQ_VERSION:-v4.47.2}"
    local download_base_url="${YQ_DOWNLOAD_BASE_URL:-${github_mirror_url}/mikefarah/yq/releases/download}"
    local os arch binary download_url

    detectPlatform || return 1

    binary="yq_${os}_${arch}"
    download_url="${YQ_DOWNLOAD_URL:-${download_base_url}/${version}/${binary}.tar.gz}"
    echo "Detected platform: ${os}/${arch}"
    echo "Downloading yq from: ${download_url}"

    export SUDO_CMD=""
    if sudo -l 2>/dev/null | grep -q NOPASSWD; then
        SUDO_CMD="/usr/bin/sudo -n "
    fi

    wget "${download_url}" -q -O - | tar xz
    ${SUDO_CMD} mv "${binary}" /usr/local/bin/yq
    ${SUDO_CMD} chmod +x /usr/local/bin/yq
}

# Install helm binary using the upstream get-helm-3 helper.
# Usage: installHelm
# Override these environment variables for air-gapped or internal artifactory environments.
function installHelm() {
    echo "Installing helm..."
    local version="${HELM_VERSION:-v3.17.3}"
    local download_base_url="${HELM_DOWNLOAD_BASE_URL:-https://get.helm.sh}"
    local archive download_url extract_dir

    detectPlatform || return 1

    archive="helm-${version}-${os}-${arch}.tar.gz"
    download_url="${HELM_DOWNLOAD_URL:-${download_base_url}/${archive}}"
    extract_dir="$(mktemp -d)"
    trap 'rm -rf "${extract_dir}"' RETURN

    echo "Detected platform: ${os}/${arch}"
    echo "Downloading helm from: ${download_url}"

    export SUDO_CMD=""
    if sudo -l 2>/dev/null | grep -q NOPASSWD; then
        SUDO_CMD="/usr/bin/sudo -n "
    fi

    wget "${download_url}" -q -O - | tar xz -C "${extract_dir}"
    ${SUDO_CMD} mv "${extract_dir}/${os}-${arch}/helm" /usr/local/bin/helm
    ${SUDO_CMD} chmod +x /usr/local/bin/helm
}

# Ensure yq is installed, install if missing
# Usage: ensureYq
function ensureYq() {
    if ! yq --version &> /dev/null; then
        echo "yq is not installed. Attempting to install yq"
        installYq
    fi
}

# Ensure helm is installed, install if missing
# Usage: ensureHelm
function ensureHelm() {
    if ! helm version --short &> /dev/null; then
        echo "helm is not installed. Attempting to install helm"
        installHelm
    fi
}
