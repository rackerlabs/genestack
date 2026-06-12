#!/usr/bin/env bash
# Talos cluster functions

# Each lib module resolves its own location to find helpers.sh
_SCRIPT_LOCAL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${_SCRIPT_LOCAL}/../helpers.sh"

function installTalosctl() {
    echo "Installing talosctl version ${TALOS_VERSION}..."
    wget https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/${TALOS_BINARY} -O talosctl
    sudo install -o root -g root -m 0755 talosctl /usr/local/bin/talosctl
}

function ensureTalosctl() {
    if ! talosctl version --client 2>/dev/null; then
        echo "talosctl is not installed. Attempting to install talosctl"
        installTalosctl
    fi
}

function writeKubeOvnTalosConfig() {
    # Configure Kube-OVN for Talos
    local config_path="${1:-/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml}"
    mkdir -p "$(dirname "${config_path}")"

    if [ ! -f "${config_path}" ]; then
        cat > "${config_path}" <<EOF
---
global:
  cni:
    config:
      args:
        container_infra_prefixes:
          - registry.rackspace.com
      ifName: $(ip -o r g 1 | awk '{print $5}')
      mtu: 1500
      provider:
        pod_cidrs:
          - 10.244.0.0/16
          - 10.245.0.0/16
    kubeovn:
      image: /docker.io/kubeovn/kube-ovn:v1.12.3
      containerInfraPrefixes:
        - registry.rackspace.com
      kubeOvnTcRedirectAction: "kubeovn-tc-redirect"
  openvswitch:
    containerDir: /var/run/openvswitch
    dir: /var/lib/openvswitch
  ovn:
    dir: /var/lib/ovn
  config:
    mtu: 1500
    provider:
      disableVxlan: true
EOF
    fi
}

function writeRookCephTalosNamespace() {
    # Configure Rook-Ceph namespace with Talos privileged permissions
    local config_path="${1:-/etc/genestack/kustomize/rook-operator/overlay}"
    local overlay_path="${config_path}/rook-ceph"

    mkdir -p "${overlay_path}"

    cat > "${overlay_path}/namespace-talos.yaml" <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/audit: privileged
EOF

    cat > "${overlay_path}/kustomization.yaml" <<EOF
---
namespace: rook-ceph
resources:
  - namespace-talos.yaml
patches:
  - path: namespace-talos.yaml
    target:
      kind: Namespace
      name: rook-ceph
EOF
}
