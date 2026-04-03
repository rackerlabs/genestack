#!/bin/bash
# ==========================================================================
# test-tenant-shares.sh
#
# End-to-end Manila share test for each tenant: creates shares, VMs,
# routers with external gateway, floating IPs, and mounts the share.
#
#   Usage:
#     test-tenant-shares.sh create  [--size <GB>] [--flavor <name>] [--image <name>]
#     test-tenant-shares.sh destroy
#
#   Options:
#     --size <GB>        Share size in GB (default: 5)
#     --flavor <name>    VM flavor (default: m1.medium)
#     --image <name>     VM image (default: amphora-ubuntu-noble)
#
# Run as: ubuntu@controller
# Requires: genestack venv, yq, ~/customers/clouds.yaml
# ==========================================================================

ACTION="${1:-}"
SHARE_SIZE=5
VM_FLAVOR="m1.medium"
VM_IMAGE="amphora-ubuntu-noble"
EXTERNAL_NETWORK="flat"

# Parse arguments
shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --size)   SHARE_SIZE="${2:-5}"; shift 2 ;;
    --flavor) VM_FLAVOR="${2}"; shift 2 ;;
    --image)  VM_IMAGE="${2}"; shift 2 ;;
    *)        echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$ACTION" != "create" && "$ACTION" != "destroy" ]]; then
  echo "Usage: $0 {create|destroy} [--size <GB>] [--flavor <name>] [--image <name>]"
  echo ""
  echo "  create   — Create shares, VMs, routers, floating IPs, and mount shares"
  echo "  destroy  — Tear down everything created by this script"
  echo ""
  echo "Options:"
  echo "  --size <GB>        Share size in GB (default: 5)"
  echo "  --flavor <name>    VM flavor (default: m1.medium)"
  echo "  --image <name>     VM image (default: amphora-ubuntu-noble)"
  exit 1
fi

# --------------------------------------------------------------------------
# Environment setup
# --------------------------------------------------------------------------
source /home/ubuntu/.venvs/genestack/bin/activate
set -a
source /opt/genestack/scripts/genestack.rc
set +a
export HOME=/home/ubuntu

CUSTOMER_DIR=/home/ubuntu/customers
CLOUDS_YAML="${CUSTOMER_DIR}/clouds.yaml"
export OS_CLIENT_CONFIG_FILE="${CLOUDS_YAML}"

# Admin commands need the system clouds.yaml, not the tenant one.
# Use a function wrapper so OS_CLIENT_CONFIG_FILE is overridden per-call.
ADMIN_CLOUDS="${HOME}/.config/openstack/clouds.yaml"
os_admin() {
  OS_CLIENT_CONFIG_FILE="$ADMIN_CLOUDS" openstack --os-cloud=default "$@"
}

if [ ! -f "$CLOUDS_YAML" ]; then
  echo "ERROR: ${CLOUDS_YAML} not found."
  echo "       Run manage-test-tenants.sh create first."
  exit 1
fi

TENANTS=$(yq '.clouds | keys | .[]' "$CLOUDS_YAML")

if [ -z "$TENANTS" ]; then
  echo "ERROR: No tenants found in ${CLOUDS_YAML}"
  exit 1
fi

# ==========================================================================
# CREATE
# ==========================================================================
if [ "$ACTION" = "create" ]; then

  echo "============================================================"
  echo "  END-TO-END MANILA SHARE TEST"
  echo "  Share size: ${SHARE_SIZE}GB  Flavor: ${VM_FLAVOR}  Image: ${VM_IMAGE}"
  echo "============================================================"

  # ----------------------------------------------------------------------
  # Ensure the VM image is accessible to all tenants
  # ----------------------------------------------------------------------
  echo ""
  echo ">>> Ensuring VM image is accessible to tenants..."

  IMAGE_ID=$(os_admin image show "${VM_IMAGE}" -f json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null) || true

  if [ -z "$IMAGE_ID" ]; then
    echo "ERROR: Image '${VM_IMAGE}' not found."
    exit 1
  fi

  IMAGE_VIS=$(os_admin image show "${VM_IMAGE}" -f json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("visibility",""))' 2>/dev/null) || true

  if [ "$IMAGE_VIS" != "public" ] && [ "$IMAGE_VIS" != "shared" ]; then
    echo "  Image is '${IMAGE_VIS}', setting to shared..."
    os_admin image set "${IMAGE_ID}" --shared 2>/dev/null || true
  fi

  # Share image with each tenant project and accept membership as the tenant
  for tenant in $TENANTS; do
    PROJECT_ID=$(os_admin project show "$tenant" -f json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null) || true
    if [ -n "$PROJECT_ID" ]; then
      # Add the project as an image member (admin operation)
      os_admin image add project "${IMAGE_ID}" "${PROJECT_ID}" >/dev/null 2>&1 || true
      # Accept the membership as the tenant (must be done by the tenant)
      openstack --os-cloud="${tenant}" image set --accept "${IMAGE_ID}" 2>/dev/null || true
      echo "  Shared with ${tenant} (${PROJECT_ID})"
    fi
  done
  echo "  Image shared and accepted by all tenants."

  # ----------------------------------------------------------------------
  # Per-tenant setup
  # ----------------------------------------------------------------------
  for tenant in $TENANTS; do
    echo ""
    echo "============================================================"
    echo "  TENANT: ${tenant}"
    echo "============================================================"

    TENANT_OS="openstack --os-cloud=${tenant}"
    SHARE_NAME="${tenant}-test-share"
    SHARE_NET_NAME="${tenant}-share-network"
    NETWORK_NAME="${tenant}-network"
    SUBNET_NAME="${tenant}-subnet"
    ROUTER_NAME="${tenant}-router"
    SG_NAME="${tenant}-test-sg"
    KEYPAIR_NAME="${tenant}-keypair"
    VM_NAME="${tenant}-test-vm"
    KEY_DIR="${CUSTOMER_DIR}/${tenant}"
    mkdir -p "${KEY_DIR}"

    # ------------------------------------------------------------------
    # 1) SSH keypair
    # ------------------------------------------------------------------
    echo ">>> [1/8] SSH keypair..."
    if $TENANT_OS keypair show "${KEYPAIR_NAME}" -f json >/dev/null 2>&1; then
      echo "  (keypair exists)"
    else
      ssh-keygen -t ed25519 -f "${KEY_DIR}/id_ed25519" -N "" -C "${KEYPAIR_NAME}" -q 2>/dev/null || true
      $TENANT_OS keypair create --public-key "${KEY_DIR}/id_ed25519.pub" "${KEYPAIR_NAME}" >/dev/null 2>&1
      echo "  Created keypair, private key at ${KEY_DIR}/id_ed25519"
    fi

    # ------------------------------------------------------------------
    # 2) Router with external gateway
    # ------------------------------------------------------------------
    echo ">>> [2/8] Router..."
    if $TENANT_OS router show "${ROUTER_NAME}" -f json >/dev/null 2>&1; then
      echo "  (router exists)"
    else
      $TENANT_OS router create "${ROUTER_NAME}" >/dev/null 2>&1
      echo "  Created router ${ROUTER_NAME}"
    fi

    # Set external gateway
    $TENANT_OS router set "${ROUTER_NAME}" --external-gateway "${EXTERNAL_NETWORK}" 2>/dev/null || true

    # Add tenant subnet to router
    $TENANT_OS router add subnet "${ROUTER_NAME}" "${SUBNET_NAME}" 2>/dev/null || true
    echo "  External gateway: ${EXTERNAL_NETWORK}, subnet: ${SUBNET_NAME}"

    # ------------------------------------------------------------------
    # 3) Security group
    # ------------------------------------------------------------------
    echo ">>> [3/8] Security group..."
    if $TENANT_OS security group show "${SG_NAME}" -f json >/dev/null 2>&1; then
      echo "  (security group exists)"
    else
      $TENANT_OS security group create "${SG_NAME}" \
        --description "Test SG for ${tenant}" >/dev/null 2>&1

      # SSH
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol tcp --dst-port 22 --ingress >/dev/null 2>&1
      # ICMP
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol icmp --ingress >/dev/null 2>&1
      # NFS (TCP 2049)
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol tcp --dst-port 2049 --ingress >/dev/null 2>&1
      # NFS mountd (TCP 20048)
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol tcp --dst-port 20048 --ingress >/dev/null 2>&1
      # NFS portmapper (TCP/UDP 111)
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol tcp --dst-port 111 --ingress >/dev/null 2>&1
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol udp --dst-port 111 --ingress >/dev/null 2>&1
      # Allow all egress (default, but explicit)
      $TENANT_OS security group rule create "${SG_NAME}" \
        --protocol any --egress >/dev/null 2>&1 || true

      echo "  Created security group with SSH, ICMP, NFS rules"
    fi

    # ------------------------------------------------------------------
    # 4) Share network
    # ------------------------------------------------------------------
    echo ">>> [4/8] Share network..."
    NETWORK_ID=$($TENANT_OS network show "${NETWORK_NAME}" -f value -c id 2>/dev/null) || true
    SUBNET_ID=$($TENANT_OS subnet show "${SUBNET_NAME}" -f value -c id 2>/dev/null) || true

    if [ -z "$NETWORK_ID" ] || [ -z "$SUBNET_ID" ]; then
      echo "  ERROR: Could not find ${NETWORK_NAME} or ${SUBNET_NAME}. Skipping tenant."
      continue
    fi

    SHARE_NET_ID=$($TENANT_OS share network show "${SHARE_NET_NAME}" -f value -c id 2>/dev/null) || true

    if [ -z "$SHARE_NET_ID" ]; then
      CREATE_OUT=$($TENANT_OS share network create \
        --name "${SHARE_NET_NAME}" \
        --neutron-net-id "${NETWORK_ID}" \
        --neutron-subnet-id "${SUBNET_ID}" \
        --description "Share network for ${tenant}" \
        -f value -c id 2>&1)
      # Extract UUID from output (skip error text)
      SHARE_NET_ID=$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
      if [ -z "$SHARE_NET_ID" ]; then
        echo "  ERROR: Failed to create share-network:"
        echo "    $CREATE_OUT"
        echo "  Skipping tenant."
        continue
      fi
      echo "  Created share-network ${SHARE_NET_NAME} (${SHARE_NET_ID})"
    else
      echo "  (share-network exists: ${SHARE_NET_ID})"
    fi

    # ------------------------------------------------------------------
    # 5) Create NFS share
    # ------------------------------------------------------------------
    echo ">>> [5/8] NFS share (${SHARE_SIZE}GB)..."
    SHARE_ID=$($TENANT_OS share show "${SHARE_NAME}" -f value -c id 2>/dev/null) || true

    if [ -z "$SHARE_ID" ]; then
      CREATE_OUT=$($TENANT_OS share create NFS "${SHARE_SIZE}" \
        --name "${SHARE_NAME}" \
        --share-network "${SHARE_NET_ID}" \
        --description "Test share for ${tenant}" \
        --share-type generic \
        -f value -c id 2>&1)
      SHARE_ID=$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
      if [ -z "$SHARE_ID" ]; then
        echo "  ERROR: Failed to create share:"
        echo "    $CREATE_OUT"
        echo "  Skipping tenant."
        continue
      fi
      echo "  Created share ${SHARE_NAME} (${SHARE_ID})"
    else
      echo "  (share exists: ${SHARE_ID})"
    fi

    # ------------------------------------------------------------------
    # 6) Boot VM
    # ------------------------------------------------------------------
    echo ">>> [6/8] VM..."
    if $TENANT_OS server show "${VM_NAME}" -f json >/dev/null 2>&1; then
      echo "  (VM exists)"
    else
      $TENANT_OS server create "${VM_NAME}" \
        --flavor "${VM_FLAVOR}" \
        --image "${VM_IMAGE}" \
        --network "${NETWORK_NAME}" \
        --security-group "${SG_NAME}" \
        --key-name "${KEYPAIR_NAME}" \
        --wait >/dev/null 2>&1
      echo "  Created VM ${VM_NAME}"
    fi

    # ------------------------------------------------------------------
    # 7) Floating IP
    # ------------------------------------------------------------------
    echo ">>> [7/8] Floating IP..."
    EXISTING_FIP=$($TENANT_OS server show "${VM_NAME}" -f json 2>/dev/null \
      | python3 -c '
import json, sys
d = json.load(sys.stdin)
addrs = d.get("addresses", "")
if isinstance(addrs, str):
    # parse "network=ip1, ip2" format
    for part in addrs.replace(",", " ").split():
        octets = part.strip().split(".")
        if len(octets) == 4 and not part.startswith("192.168.50."):
            print(part.strip())
            break
' 2>/dev/null) || true

    if [ -n "$EXISTING_FIP" ]; then
      echo "  (floating IP already assigned: ${EXISTING_FIP})"
      FIP_ADDR="${EXISTING_FIP}"
    else
      FIP_ADDR=$($TENANT_OS floating ip create "${EXTERNAL_NETWORK}" -f json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["floating_ip_address"])' 2>/dev/null) || true

      if [ -z "$FIP_ADDR" ]; then
        echo "  WARNING: Could not allocate floating IP. VM will not be reachable externally."
      else
        $TENANT_OS server add floating ip "${VM_NAME}" "${FIP_ADDR}" 2>/dev/null || true
        echo "  Assigned floating IP: ${FIP_ADDR}"
      fi
    fi

    # ------------------------------------------------------------------
    # 8) Wait for share, grant access, and mount
    # ------------------------------------------------------------------
    echo ">>> [8/8] Share access and mount..."

    # Wait for share to be available
    echo "  Waiting for share to become available..."
    ATTEMPTS=0
    while [ "$ATTEMPTS" -lt 60 ]; do
      SHARE_STATUS=$($TENANT_OS share show "${SHARE_NAME}" -f json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null) || true
      if [ "$SHARE_STATUS" = "available" ]; then
        break
      elif [ "$SHARE_STATUS" = "error" ]; then
        echo "  ERROR: Share is in error state!"
        break
      fi
      ATTEMPTS=$((ATTEMPTS + 1))
      sleep 10
    done

    if [ "$SHARE_STATUS" = "available" ]; then
      echo "  Share is available."

      # Get the VM's fixed IP for access rule
      VM_FIXED_IP=$($TENANT_OS server show "${VM_NAME}" -f json 2>/dev/null \
        | python3 -c '
import json, sys
d = json.load(sys.stdin)
addrs = d.get("addresses", "")
if isinstance(addrs, str):
    for part in addrs.replace(",", " ").split():
        part = part.strip()
        if part.startswith("192.168.50."):
            print(part)
            break
elif isinstance(addrs, dict):
    for net, ips in addrs.items():
        for ip_info in ips:
            addr = ip_info if isinstance(ip_info, str) else ip_info.get("addr","")
            if addr.startswith("192.168.50."):
                print(addr)
                break
' 2>/dev/null) || true

      if [ -n "$VM_FIXED_IP" ]; then
        # Grant IP-based access to the share
        echo "  Granting NFS access to ${VM_FIXED_IP}..."
        $TENANT_OS share access create "${SHARE_NAME}" ip "${VM_FIXED_IP}" 2>/dev/null || true

        # Get the export path
        EXPORT_PATH=$($TENANT_OS share export location list "${SHARE_NAME}" -f json 2>/dev/null \
          | python3 -c '
import json, sys
locs = json.load(sys.stdin)
if locs:
    print(locs[0].get("Path", locs[0].get("path", "")))
' 2>/dev/null) || true

        echo "  Export path: ${EXPORT_PATH:-pending (share server may still be provisioning)}"
      else
        echo "  WARNING: Could not determine VM fixed IP."
      fi
    fi

    # Summary for this tenant
    echo ""
    echo "  --- Summary for ${tenant} ---"
    echo "  VM:          ${VM_NAME}"
    echo "  Floating IP: ${FIP_ADDR:-none}"
    echo "  Share:       ${SHARE_NAME} (${SHARE_STATUS:-unknown})"
    echo "  Export:      ${EXPORT_PATH:-pending}"
    if [ -n "$FIP_ADDR" ] && [ -f "${KEY_DIR}/id_ed25519" ]; then
      # Determine SSH user based on image
      SSH_USER="ubuntu"
      case "${VM_IMAGE,,}" in
        *cirros*)  SSH_USER="cirros" ;;
        *centos*)  SSH_USER="centos" ;;
        *debian*)  SSH_USER="debian" ;;
        *fedora*)  SSH_USER="fedora" ;;
        *ubuntu*|*amphora*) SSH_USER="ubuntu" ;;
      esac
      echo "  SSH:         ssh -i ${KEY_DIR}/id_ed25519 ${SSH_USER}@${FIP_ADDR}"
      if [ -n "$EXPORT_PATH" ]; then
        echo "  Mount:       sudo mkdir -p /mnt/share && sudo mount -t nfs ${EXPORT_PATH} /mnt/share"
      fi
    fi
  done

  # Summary table
  echo ""
  echo "============================================================"
  echo "  OVERALL STATUS"
  echo "============================================================"
  printf "  %-15s %-18s %-12s %-10s\n" "TENANT" "FLOATING IP" "SHARE" "VM"
  printf "  %-15s %-18s %-12s %-10s\n" "------" "-----------" "-----" "--"

  for tenant in $TENANTS; do
    TENANT_OS="openstack --os-cloud=${tenant}"

    FIP=$($TENANT_OS server show "${tenant}-test-vm" -f json 2>/dev/null \
      | python3 -c '
import json, sys
d = json.load(sys.stdin)
addrs = d.get("addresses", "")
if isinstance(addrs, str):
    for part in addrs.replace(",", " ").split():
        part = part.strip()
        if not part.startswith("192.168.50.") and "." in part:
            try:
                [int(o) for o in part.split(".")]
                print(part)
                break
            except ValueError:
                pass
' 2>/dev/null) || true

    SHARE_ST=$($TENANT_OS share show "${tenant}-test-share" -f json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null) || true

    VM_ST=$($TENANT_OS server show "${tenant}-test-vm" -f json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null) || true

    printf "  %-15s %-18s %-12s %-10s\n" "${tenant}" "${FIP:-none}" "${SHARE_ST:-?}" "${VM_ST:-?}"
  done

fi

# ==========================================================================
# DESTROY
# ==========================================================================
if [ "$ACTION" = "destroy" ]; then

  echo "============================================================"
  echo "  DESTROYING TEST SHARES, VMs, AND NETWORKING"
  echo "============================================================"

  for tenant in $TENANTS; do
    echo ""
    echo ">>> ${tenant}: tearing down..."

    TENANT_OS="openstack --os-cloud=${tenant}"
    VM_NAME="${tenant}-test-vm"
    SHARE_NAME="${tenant}-test-share"
    SHARE_NET_NAME="${tenant}-share-network"
    ROUTER_NAME="${tenant}-router"
    SG_NAME="${tenant}-test-sg"
    KEYPAIR_NAME="${tenant}-keypair"
    SUBNET_NAME="${tenant}-subnet"
    KEY_DIR="${CUSTOMER_DIR}/${tenant}"

    # Delete VM
    echo "  Deleting VM..."
    $TENANT_OS server delete "${VM_NAME}" --wait 2>/dev/null || true

    # Delete floating IPs
    echo "  Releasing floating IPs..."
    FIPS=$($TENANT_OS floating ip list -f json 2>/dev/null \
      | python3 -c 'import json,sys; [print(f["ID"]) for f in json.load(sys.stdin)]' 2>/dev/null) || true
    for fid in $FIPS; do
      $TENANT_OS floating ip delete "$fid" 2>/dev/null || true
    done

    # Revoke share access rules
    echo "  Revoking share access..."
    ACCESS_IDS=$($TENANT_OS share access list "${SHARE_NAME}" -f json 2>/dev/null \
      | python3 -c 'import json,sys; [print(a["id"]) for a in json.load(sys.stdin)]' 2>/dev/null) || true
    for aid in $ACCESS_IDS; do
      $TENANT_OS share access delete "${SHARE_NAME}" "$aid" 2>/dev/null || true
    done

    # Delete shares
    echo "  Deleting shares..."
    SHARE_IDS=$($TENANT_OS share list -f json 2>/dev/null \
      | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
    for sid in $SHARE_IDS; do
      $TENANT_OS share delete "$sid" --force 2>/dev/null || true
    done

    # Wait for shares to be deleted
    if [ -n "$SHARE_IDS" ]; then
      echo "  Waiting for shares to be deleted..."
      ATTEMPTS=0
      while [ "$ATTEMPTS" -lt 30 ]; do
        REMAINING=$($TENANT_OS share list -f json 2>/dev/null \
          | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null) || true
        if [ "$REMAINING" = "0" ] || [ -z "$REMAINING" ]; then
          break
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 5
      done
    fi

    # Delete share-networks
    echo "  Deleting share-networks..."
    SHARE_NET_IDS=$($TENANT_OS share network list -f json 2>/dev/null \
      | python3 -c 'import json,sys; [print(s["id"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
    for snid in $SHARE_NET_IDS; do
      $TENANT_OS share network delete "$snid" 2>/dev/null || true
    done

    # Remove router interfaces and delete router
    echo "  Removing router..."
    $TENANT_OS router remove subnet "${ROUTER_NAME}" "${SUBNET_NAME}" 2>/dev/null || true
    $TENANT_OS router unset --external-gateway "${ROUTER_NAME}" 2>/dev/null || true
    $TENANT_OS router delete "${ROUTER_NAME}" 2>/dev/null || true

    # Delete security group
    echo "  Deleting security group..."
    $TENANT_OS security group delete "${SG_NAME}" 2>/dev/null || true

    # Delete keypair and local key files
    echo "  Deleting keypair..."
    $TENANT_OS keypair delete "${KEYPAIR_NAME}" 2>/dev/null || true
    rm -f "${KEY_DIR}/id_ed25519" "${KEY_DIR}/id_ed25519.pub" 2>/dev/null || true
    rmdir "${KEY_DIR}" 2>/dev/null || true

    echo "  Done: ${tenant}"
  done

  echo ""
  echo "============================================================"
  echo "  TEARDOWN COMPLETE"
  echo "============================================================"
fi
