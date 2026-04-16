#!/bin/bash
# ==========================================================================
# manage-test-tenants.sh
#
# Create, destroy, or reset 2 test tenant accounts with networks, subnets,
# admin users, and clouds.yaml credentials.
#
#   Usage:
#     manage-test-tenants.sh create   — create tenants (skip if they exist)
#     manage-test-tenants.sh destroy  — delete all tenant resources, users, and projects
#     manage-test-tenants.sh reset    — destroy everything and recreate
#
# Run as: ubuntu@controller
# Requires: genestack venv, admin cloud credentials, yq
# ==========================================================================

ACTION="${1:-}"

if [[ "$ACTION" != "create" && "$ACTION" != "destroy" && "$ACTION" != "reset" ]]; then
  echo "Usage: $0 {create|destroy|reset}"
  echo ""
  echo "  create   — Create test tenants, users, networks, subnets, clouds.yaml"
  echo "  destroy  — Delete all tenant resources, users, and projects"
  echo "  reset    — Destroy everything and recreate from scratch"
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
OS="openstack --os-cloud=default"

TENANTS=("acme-corp" "globex-inc")
CUSTOMER_DIR=/home/ubuntu/customers

# --------------------------------------------------------------------------
# Helper: generate random password
# --------------------------------------------------------------------------
generate_password() {
  < /dev/urandom tr -dc 'A-Za-z0-9' | head -c"${1:-24}"
}

# --------------------------------------------------------------------------
# Helper: delete all resources in a tenant project, then the user and project
# --------------------------------------------------------------------------
destroy_tenant() {
  local tenant="$1"

  PROJECT_ID=$($OS project show "$tenant" -f json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null) || true

  if [ -z "$PROJECT_ID" ]; then
    echo "  (project ${tenant} not found, skipping)"
    return
  fi

  echo "  Cleaning up ${tenant} (${PROJECT_ID})..."

  # Share access rules (must be revoked before shares can be deleted)
  TENANT_SHARES=$($OS share list --project "$PROJECT_ID" --all-projects -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for sid in $TENANT_SHARES; do
    ACCESS_IDS=$($OS share access list "$sid" -f json 2>/dev/null \
      | python3 -c 'import json,sys; [print(a["id"]) for a in json.load(sys.stdin)]' 2>/dev/null) || true
    for aid in $ACCESS_IDS; do
      echo "    Revoking share access $aid on share $sid..."
      $OS share access delete "$sid" "$aid" 2>/dev/null || true
    done
  done

  # Shares
  for sid in $TENANT_SHARES; do
    echo "    Deleting share $sid..."
    $OS share delete "$sid" --force 2>/dev/null || true
  done

  # Wait for shares to finish deleting before removing share-networks
  if [ -n "$TENANT_SHARES" ]; then
    echo "    Waiting for shares to be deleted..."
    ATTEMPTS=0
    while [ "$ATTEMPTS" -lt 30 ]; do
      REMAINING=$($OS share list --project "$PROJECT_ID" --all-projects -f json 2>/dev/null \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null) || true
      if [ "$REMAINING" = "0" ] || [ -z "$REMAINING" ]; then
        break
      fi
      ATTEMPTS=$((ATTEMPTS + 1))
      sleep 5
    done
  fi

  # Share networks (must be deleted after shares that reference them)
  TENANT_SHARE_NETS=$($OS share network list --project "$PROJECT_ID" --all-projects -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["id"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_SHARE_NETS; do
    echo "    Deleting share-network $id..."
    $OS share network delete "$id" 2>/dev/null || true
  done

  # Servers
  TENANT_SERVERS=$($OS server list --project "$PROJECT_ID" --all-projects -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_SERVERS; do
    echo "    Deleting server $id..."
    $OS server delete "$id" --wait 2>/dev/null || true
  done

  # Floating IPs
  TENANT_FIPS=$($OS floating ip list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(f["ID"]) for f in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_FIPS; do
    echo "    Deleting floating IP $id..."
    $OS floating ip delete "$id" 2>/dev/null || true
  done

  # Routers (remove interfaces and gateway first)
  TENANT_ROUTERS=$($OS router list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(r["ID"]) for r in json.load(sys.stdin)]' 2>/dev/null) || true
  for rid in $TENANT_ROUTERS; do
    echo "    Cleaning up router $rid..."
    ROUTER_SUBNETS=$($OS router show "$rid" -f json 2>/dev/null \
      | python3 -c '
import json, sys
d = json.load(sys.stdin)
for iface in d.get("interfaces_info", []):
    print(iface["subnet_id"])
' 2>/dev/null) || true
    for rsub in $ROUTER_SUBNETS; do
      $OS router remove subnet "$rid" "$rsub" 2>/dev/null || true
    done
    $OS router unset --external-gateway "$rid" 2>/dev/null || true
    $OS router delete "$rid" 2>/dev/null || true
  done

  # Ports
  TENANT_PORTS=$($OS port list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(p["ID"]) for p in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_PORTS; do
    $OS port delete "$id" 2>/dev/null || true
  done

  # Subnets
  TENANT_SUBNETS=$($OS subnet list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_SUBNETS; do
    echo "    Deleting subnet $id..."
    $OS subnet delete "$id" 2>/dev/null || true
  done

  # Networks
  TENANT_NETS=$($OS network list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(n["ID"]) for n in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_NETS; do
    echo "    Deleting network $id..."
    $OS network delete "$id" 2>/dev/null || true
  done

  # Security groups (skip 'default')
  TENANT_SGS=$($OS security group list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c '
import json, sys
for sg in json.load(sys.stdin):
    if sg.get("Name", "") != "default":
        print(sg["ID"])
' 2>/dev/null) || true
  for id in $TENANT_SGS; do
    echo "    Deleting security group $id..."
    $OS security group delete "$id" 2>/dev/null || true
  done

  # Volumes
  TENANT_VOLS=$($OS volume list --project "$PROJECT_ID" --all-projects -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(v["ID"]) for v in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_VOLS; do
    echo "    Deleting volume $id..."
    $OS volume delete "$id" --force 2>/dev/null || true
  done

  # Keypairs (delete via tenant cloud if possible, otherwise skip)
  TENANT_KEYPAIRS=$($OS keypair list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(k["Name"]) for k in json.load(sys.stdin)]' 2>/dev/null) || true
  for kp in $TENANT_KEYPAIRS; do
    echo "    Deleting keypair $kp..."
    $OS keypair delete "$kp" --user "${tenant}-admin" 2>/dev/null || true
  done

  # User
  echo "    Deleting user ${tenant}-admin..."
  $OS user delete "${tenant}-admin" 2>/dev/null || true

  # Project
  echo "    Deleting project ${tenant}..."
  $OS project delete "$tenant" 2>/dev/null || true

  # Local credential files
  if [ -d "${CUSTOMER_DIR}/${tenant}" ]; then
    echo "    Removing local keys in ${CUSTOMER_DIR}/${tenant}..."
    rm -rf "${CUSTOMER_DIR}/${tenant}" 2>/dev/null || true
  fi
}

# --------------------------------------------------------------------------
# Helper: create tenants, users, networks, subnets, clouds.yaml
# --------------------------------------------------------------------------
create_tenants() {
  AUTH_URL=$($OS endpoint list -f json \
    | python3 -c '
import json, sys
for ep in json.load(sys.stdin):
    if ep["Service Name"] == "keystone" and ep["Interface"] == "internal":
        print(ep["URL"])
        break
')

  if [ -z "$AUTH_URL" ]; then
    echo "ERROR: Could not determine AUTH_URL from keystone endpoints"
    exit 1
  fi

  mkdir -p "$CUSTOMER_DIR"

  cat > "${CUSTOMER_DIR}/clouds.yaml" << 'HEADER'
clouds:
HEADER

  for tenant in "${TENANTS[@]}"; do
    USERNAME="${tenant}-admin"
    PASSWORD=$(generate_password 32)

    echo ""
    echo ">>> Creating project: ${tenant}"

    $OS project create "$tenant" \
      --domain default \
      --description "Test tenant: ${tenant}" \
      2>/dev/null || echo "  (project already exists)"

    $OS user create "$USERNAME" \
      --domain default \
      --project "$tenant" \
      --password "$PASSWORD" \
      --description "Admin user for ${tenant}" \
      2>/dev/null || echo "  (user already exists, resetting password)"

    $OS user set "$USERNAME" --password "$PASSWORD" 2>/dev/null || true

    $OS role add --project "$tenant" --user "$USERNAME" member 2>/dev/null || true
    $OS role add --project "$tenant" --user "$USERNAME" admin 2>/dev/null || true

    echo "  Project: ${tenant}  User: ${USERNAME}  Roles: member, admin"

    cat >> "${CUSTOMER_DIR}/clouds.yaml" << EOF
  ${tenant}:
    auth:
      auth_url: ${AUTH_URL}
      project_name: ${tenant}
      project_domain_name: Default
      username: ${USERNAME}
      user_domain_name: Default
      password: ${PASSWORD}
    region_name: RegionOne
    interface: internal
    identity_api_version: 3
EOF
  done

  chmod 0640 "${CUSTOMER_DIR}/clouds.yaml"

  # Create tenant networks and subnets
  # Point the OpenStack client at the tenant clouds.yaml
  export OS_CLIENT_CONFIG_FILE="${CUSTOMER_DIR}/clouds.yaml"

  echo ""
  echo "============================================================"
  echo "  CREATING TENANT NETWORKS AND SUBNETS"
  echo "============================================================"

  for tenant in $(yq '.clouds | keys | .[]' "${CUSTOMER_DIR}/clouds.yaml"); do
    echo ""
    echo ">>> Creating network and subnet for: ${tenant}"

    openstack --os-cloud="${tenant}" network create \
      --project="${tenant}" \
      --provider-network-type=geneve \
      --internal \
      --enable-port-security \
      --enable \
      "${tenant}-network" 2>/dev/null || echo "  (network already exists)"

    openstack --os-cloud="${tenant}" subnet create \
      --project="${tenant}" \
      --dhcp \
      --network="${tenant}-network" \
      --subnet-range=192.168.50.0/24 \
      --gateway=192.168.50.1 \
      "${tenant}-subnet" 2>/dev/null || echo "  (subnet already exists)"

    echo "  Created: ${tenant}-network / ${tenant}-subnet (192.168.50.0/24)"
  done

  # Restore default clouds.yaml search path for admin commands
  unset OS_CLIENT_CONFIG_FILE
}

# ==========================================================================
# Main
# ==========================================================================

# --------------------------------------------------------------------------
# Action: destroy
# --------------------------------------------------------------------------
if [ "$ACTION" = "destroy" ]; then
  echo "============================================================"
  echo "  DESTROYING ALL TEST TENANTS"
  echo "============================================================"
  echo ""
  echo ">>> Destroying tenant resources, users, and projects..."

  for tenant in "${TENANTS[@]}"; do
    destroy_tenant "$tenant"
  done

  rm -f "${CUSTOMER_DIR}/clouds.yaml" 2>/dev/null || true

  echo ""
  echo "============================================================"
  echo "  DESTROY COMPLETE"
  echo "============================================================"
  echo ""
  echo "All test tenant projects, users, and resources have been removed."
  exit 0
fi

# --------------------------------------------------------------------------
# Action: reset (destroy + create)
# --------------------------------------------------------------------------
if [ "$ACTION" = "reset" ]; then
  echo "============================================================"
  echo "  RESETTING TEST TENANTS"
  echo "============================================================"
  echo ""
  echo ">>> Destroying existing tenant resources and projects..."

  for tenant in "${TENANTS[@]}"; do
    destroy_tenant "$tenant"
  done

  rm -f "${CUSTOMER_DIR}/clouds.yaml" 2>/dev/null || true

  echo ""
  echo ">>> All test tenants removed. Recreating..."
fi

# --------------------------------------------------------------------------
# Action: create (also reached by reset after destroy)
# --------------------------------------------------------------------------
if [ "$ACTION" = "create" ]; then
  echo "============================================================"
  echo "  CREATING TEST TENANTS"
  echo "============================================================"
fi

create_tenants

echo ""
echo "============================================================"
echo "  DONE"
echo "============================================================"
echo ""
echo "Tenant credentials written to: ${CUSTOMER_DIR}/clouds.yaml"
echo ""
echo "Test with:"
echo "  openstack --os-cloud=acme-corp token issue"
echo "  openstack --os-cloud=acme-corp network list"
