#!/bin/bash
# create_trove_mgmt_ports.sh — create per-chassis anchor ports on
# trove-mgmt-net for the trove-mgmt-bridge DaemonSet.
#
# Each port is bound to a specific chassis via --host=, mirroring
# Octavia's octavia-health-manager-port pattern. Port IPs are pinned
# (--fixed-ip) below the subnet's allocation pool so the trove-mgmt-bridge
# init container can predictably resolve "my port" by node-name suffix.
#
# Args:
#   $1 NET_NAME             trove-mgmt-net
#   $2 SECGRP_ID            trove-services-secgroup id (allows 5672/5000 in)
#   $3 SUBNET_NAME          trove-mgmt-subnet
#   $4 ANCHOR_BASE_OFFSET   first host octet to assign (default 10)
#   $5 CLOUD_NAME           os_cloud (default: default)

set -xeuo pipefail

NET_NAME=$1
SECGRP_ID=$2
SUBNET_NAME=$3
ANCHOR_BASE_OFFSET=${4:-10}
CLOUD_NAME=${5:-default}

export OS_CLOUD="${CLOUD_NAME}"

SUBNET_CIDR=$(openstack subnet show "${SUBNET_NAME}" -f value -c cidr)
NET_PREFIX=$(echo "${SUBNET_CIDR}" | awk -F'.' '{print $1"."$2"."$3}')

# Sort node names so anchor-IP assignment is deterministic across runs.
mapfile -t NODES < <(kubectl get nodes -l openstack-control-plane=enabled -o name \
                      | awk -F/ '{print $2}' | sort)

i=0
for node in "${NODES[@]}"; do
  short="${node%%.*}"
  port="trove-mgmt-bridge-port-${short}"
  ip="${NET_PREFIX}.$((ANCHOR_BASE_OFFSET + i))"

  if openstack port show "${port}" >/dev/null 2>&1; then
    echo "[create_trove_mgmt_ports] ${port} already exists"
  else
    openstack port create "${port}" \
      --network "${NET_NAME}" \
      --host "${node}" \
      --device-owner "trove:management-bridge" \
      --security-group "${SECGRP_ID}" \
      --fixed-ip "subnet=${SUBNET_NAME},ip-address=${ip}"
  fi
  i=$((i+1))
done
