#!/bin/bash

KUBECTL_DEST="/usr/local/bin/kubectl"
ARCH=$(dpkg --print-architecture)
DRY_RUN=false
OWNER_UID="root" 
OWNER_GID="root" 
INSTALL_MODE="0755" 
KUBE_VERSION_OVERRIDE=""

# --- Argument Parsing ---
if [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    KUBE_VERSION_OVERRIDE="${1#v}"
    shift
fi

if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "--- DRY-RUN MODE ACTIVATED ---"
fi

case "${ARCH}" in
    "amd64")
        KUBERNETES_ARCH="amd64"
        ;;
    "arm64")
        KUBERNETES_ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture ${ARCH}. This script supports amd64 and arm64."
        exit 1
        ;;
esac

echo "Detected system architecture: ${KUBERNETES_ARCH}"

get_kube_version() {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: 'kubectl' command not found in PATH." >&2
        return 1
    fi

    if $DRY_RUN && [ -z "${KUBE_VERSION_OVERRIDE}" ]; then
        echo "1.28.5 (SIMULATED)"
        return 0
    fi
    
    SERVER_VERSION=$(kubectl version --client=false --output=json 2>/dev/null | jq -r '.serverVersion.gitVersion')

    if [ -z "${SERVER_VERSION}" ] || [ "${SERVER_VERSION}" = "null" ]; then
        echo "Error: Could not determine Kubernetes server version. Is KUBECONFIG set and is the cluster reachable?" >&2
        return 1
    fi

    echo "${SERVER_VERSION#v}"
}

echo "Attempting to fetch Kubernetes server version..."

if [ -n "${KUBE_VERSION_OVERRIDE}" ]; then
    KUBE_VERSION="${KUBE_VERSION_OVERRIDE}"
    echo "Target Kubernetes version OVERRIDDEN by argument: v${KUBE_VERSION}"
else
    KUBE_VERSION=$(get_kube_version)
    
    if [ $? -ne 0 ]; then
        echo "FATAL: Auto-detection failed. When installing kubectl for the first time or when it's not in PATH, you MUST provide the target Kubernetes version as the first command-line argument (e.g., $0 1.29.1)." >&2
        exit 1
    fi
    echo "Target Kubernetes version detected: v${KUBE_VERSION}"
fi

DOWNLOAD_URL="https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/${KUBERNETES_ARCH}/kubectl"

if $DRY_RUN; then
    echo
    echo "--- Dry-Run Actions to be performed ---"
    
    if [ -f "${KUBECTL_DEST}" ]; then
        echo "DRY-RUN: Existing binary found. Permissions/Ownership would be read and preserved. File would be removed and replaced."
    else
        echo "DRY-RUN: No existing kubectl binary found. File would be installed using default permissions (${INSTALL_MODE}) and ownership (root:root)."
    fi

    echo "DRY-RUN: Binary v${KUBE_VERSION} would be downloaded from: ${DOWNLOAD_URL} to /tmp/kubectl"
    echo "DRY-RUN: The downloaded binary would be installed to ${KUBECTL_DEST}."
    echo "DRY-RUN: The temporary file /tmp/kubectl would be removed."
    
    echo
    echo "Dry-Run complete. No changes were made."
else    
    if [ -f "${KUBECTL_DEST}" ]; then
        echo "Existing kubectl binary found. Reading and preserving permissions/ownership for ${KUBECTL_DEST}..."
        
        OWNER_UID=$(sudo stat -c "%u" "${KUBECTL_DEST}" 2>/dev/null)
        OWNER_GID=$(sudo stat -c "%g" "${KUBECTL_DEST}" 2>/dev/null)
        OLD_MODE=$(sudo stat -c "%a" "${KUBECTL_DEST}" 2>/dev/null)

        if [ -n "$OLD_MODE" ]; then
            INSTALL_MODE="$OLD_MODE"
            echo "Preserving permissions: ${INSTALL_MODE}"
        fi
        
        if [ "$OWNER_UID" == "0" ]; then OWNER_UID="root"; fi
        if [ "$OWNER_GID" == "0" ]; then OWNER_GID="root"; fi

        if [ -n "$OWNER_UID" ] && [ -n "$OWNER_GID" ]; then
            echo "Preserving ownership: Owner=${OWNER_UID}, Group=${OWNER_GID}"
        else
             echo "Could not read existing ownership/permissions, defaulting to root:root and 0755."
             OWNER_UID="root"
             OWNER_GID="root"
        fi

        echo "Removing existing kubectl binary at ${KUBECTL_DEST}..."
        sudo rm -f "${KUBECTL_DEST}"
    else
        echo "No existing kubectl binary found at ${KUBECTL_DEST}. Installing new binary with default permissions."
    fi
    
    echo "Downloading kubectl v${KUBE_VERSION} from: ${DOWNLOAD_URL}"
    curl -sSL "${DOWNLOAD_URL}" -o /tmp/kubectl

    if [ ! -s "/tmp/kubectl" ]; then
        echo "Error: Download failed or the binary file is empty. Check the version number (v${KUBE_VERSION}) or URL." >&2
        rm -f /tmp/kubectl
        exit 1
    fi

    echo "Installing kubectl to ${KUBECTL_DEST} with mode ${INSTALL_MODE} and ownership ${OWNER_UID}:${OWNER_GID}..."
    
    sudo install -o "${OWNER_UID}" -g "${OWNER_GID}" -m "${INSTALL_MODE}" /tmp/kubectl "${KUBECTL_DEST}"
    rm -f /tmp/kubectl

    echo "Installation complete!"
    echo "New kubectl version:"
    ${KUBECTL_DEST} version --client

    echo ""
    echo "Server version check:"
    ${KUBECTL_DEST} version --client=false
fi
