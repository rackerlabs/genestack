#!/bin/bash
# trove-mgmt-bridge init container.
#
# Plumbs the chassis-bound Neutron LSP for this node into the pod netns,
# mirroring the openstack-helm octavia-health-manager-init pattern:
#   1. ovs-vsctl creates an OVS internal port on br-int with
#      external_ids:iface-id=<lsp-uuid>. The kernel device lands in
#      root netns (where ovs-vswitchd lives).
#   2. nsenter into root netns to move the device into the pod netns.
#      $$ here is the host-visible PID of this script (we run with
#      hostPID=true), so /proc/$$/ns/net is the pod's netns.
#   3. Configure the IP inside the pod netns.
#
# Per-node port metadata (LSP_UUID, IP_ADDR, PREFIX_LEN) is resolved by
# ansible at deploy time and mounted as a ConfigMap; we just source the
# file matching this node's short hostname. That keeps the init image
# free of the openstack CLI.
#
# Idempotent on container restart: if the device is already in the pod
# netns we skip the plumbing steps but still re-affirm config.

set -euo pipefail

DEV="${BRIDGE_DEV:-t-mgmt0}"
PORT_INFO_DIR="${PORT_INFO_DIR:-/etc/trove-mgmt-bridge/ports}"
PORT_INFO_FILE="${PORT_INFO_DIR}/${NODE_NAME%%.*}"

if [ ! -f "${PORT_INFO_FILE}" ]; then
  echo "[trove-mgmt-bridge] ERROR: no port metadata at ${PORT_INFO_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "${PORT_INFO_FILE}"

: "${LSP_UUID:?LSP_UUID missing in ${PORT_INFO_FILE}}"
: "${LSP_MAC:?LSP_MAC missing in ${PORT_INFO_FILE}}"
: "${IP_ADDR:?IP_ADDR missing in ${PORT_INFO_FILE}}"
: "${PREFIX_LEN:?PREFIX_LEN missing in ${PORT_INFO_FILE}}"

echo "[trove-mgmt-bridge] node=${NODE_NAME} LSP=${LSP_UUID} mac=${LSP_MAC} ip=${IP_ADDR}/${PREFIX_LEN}"

if ip link show "${DEV}" >/dev/null 2>&1; then
  echo "[trove-mgmt-bridge] ${DEV} already in pod netns; skipping plumb"
else
  # Create OVS internal port. Kernel device lands in root netns.
  ovs-vsctl --may-exist add-port br-int "${DEV}" \
    -- set Interface "${DEV}" type=internal external_ids:iface-id="${LSP_UUID}"

  # Move device from root netns into this pod netns.
  # nsenter -t 1 -n enters PID 1's netns (root). $$ is our own host PID.
  nsenter -t 1 -n ip link set "${DEV}" netns "$$"
fi

# MAC must match the LSP's MAC or OVN's source-MAC anti-spoof drops
# cross-chassis traffic. Set before bringing the link up.
ip link set "${DEV}" down 2>/dev/null || true
ip link set "${DEV}" address "${LSP_MAC}"
ip link set "${DEV}" up
ip addr replace "${IP_ADDR}/${PREFIX_LEN}" dev "${DEV}"

echo "[trove-mgmt-bridge] ${DEV} ready on ${NODE_NAME}"
