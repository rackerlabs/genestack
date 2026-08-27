#!/bin/bash
# ==========================================================================
# manage-test-tenants.sh
#
# Create, destroy, or reset a test tenant account with networks, subnets,
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
export HOME=/home/ubuntu
source ${HOME}/.venvs/genestack/bin/activate
set -a
source /opt/genestack/scripts/genestack.rc
set +a
OS="openstack --os-cloud=default"

TENANTS=("acme-corp")
CUSTOMER_DIR=${HOME}/customers
SUBNET_CIDR="192.168.50.0/24"

# --------------------------------------------------------------------------
# Helper: delete all resources in a tenant project, then the user and project
# --------------------------------------------------------------------------
destroy_tenant() {
  local tenant="$1"

  export OS_CLIENT_CONFIG_FILE="${HOME}/.config/openstack/clouds.yaml"

  PROJECT_ID=$($OS project show "$tenant" -f json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null) || true

  if [ -z "$PROJECT_ID" ]; then
    echo "  (project ${tenant} not found, skipping)"
    return
  fi

  echo "  Cleaning up ${tenant} (${PROJECT_ID})..."

  # Database Instances
  TENANT_DBS=$($OS database instance list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_DBS; do
    echo "    Deleting database instance $id..."
    $OS database instance delete "$id" --force 2>/dev/null || true
  done

  # Servers
  TENANT_SERVERS=$($OS server list --project "$PROJECT_ID" -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(s["ID"]) for s in json.load(sys.stdin)]' 2>/dev/null) || true
  for id in $TENANT_SERVERS; do
    echo "    Deleting server $id..."
    $OS server delete "$id" --force --wait 2>/dev/null || true
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

  unset OS_CLIENT_CONFIG_FILE
}

# --------------------------------------------------------------------------
# Helper: create tenants, users, networks, subnets, clouds.yaml
# --------------------------------------------------------------------------
create_tenants() {

  export OS_CLIENT_CONFIG_FILE="${HOME}/.config/openstack/clouds.yaml"

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
    PASSWORD="${USERNAME}-pwd"

    echo ""
    echo ">>> Creating project: ${tenant}"

    $OS project create "$tenant" \
      --domain default \
      --description "Test tenant: ${tenant}" \
      2>/dev/null || echo "  ===> project already exists"

    $OS user create "$USERNAME" \
      --domain default \
      --project "$tenant" \
      --password "$PASSWORD" \
      --description "Admin user for ${tenant}" \
      2>/dev/null || echo "  ===> user already exists, resetting password"

    $OS user set "$USERNAME" --password "$PASSWORD" 2>/dev/null || true

    $OS role add --project "$tenant" --user "$USERNAME" member 2>/dev/null || true
    $OS role add --project "$tenant" --user "$USERNAME" admin 2>/dev/null || true

    unset OS_CLIENT_CONFIG_FILE

    echo "  Project: ${tenant}  User: ${USERNAME}  Roles: member, admin"

    cat >> "${CUSTOMER_DIR}/clouds.yaml" << CLOUDS_YAML_EOF
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
CLOUDS_YAML_EOF

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

    if openstack network list 2>&1 | grep ${tenant}-net > /dev/null 2>&1; then
      echo "  ===> network already exists"
    else
      openstack --os-cloud="${tenant}" network create \
        --project="${tenant}" \
        --provider-network-type=geneve \
        --internal \
        --enable-port-security \
        --enable \
        "${tenant}-net" 2>/dev/null
    fi

    if openstack subnet list 2>&1 | grep ${tenant}-subnet > /dev/null 2>&1; then
      echo "  ===> subnet already exists"
    else
      openstack --os-cloud="${tenant}" subnet create \
        --project="${tenant}" \
        --dhcp \
        --network="${tenant}-net" \
        --subnet-range=${SUBNET_CIDR} \
        --gateway="${SUBNET_CIDR:0:10}.1" \
        --dns-nameserver 1.1.1.1 \
        --dns-nameserver 8.8.8.8 \
        "${tenant}-subnet" 2>/dev/null
    fi

    # Trove (and any service that needs floating IPs / external reach) requires
    # the user-facing subnet to be attached to a router with an external gateway.
    # Without this, `openstack database instance create --is-public` fails with:
    #   Subnet ... is not associated with router.
    if openstack router list 2>&1 | grep ${tenant}-router > /dev/null 2>&1; then
      echo "  ===> router already exists"
    else
      openstack --os-cloud="${tenant}" router create \
        --project="${tenant}" \
        --external-gateway flat \
        "${tenant}-router" 2>/dev/null
    fi

    openstack --os-cloud="${tenant}" router add subnet \
      "${tenant}-router" "${tenant}-subnet" 2>/dev/null \
      || echo "  ===> subnet already attached to router"

    echo "  Network: ${tenant}-net / ${tenant}-subnet (${SUBNET_CIDR}) / ${tenant}-router → flat"
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

  #rm -f "${CUSTOMER_DIR}/clouds.yaml" 2>/dev/null || true

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

  #rm -f "${CUSTOMER_DIR}/clouds.yaml" 2>/dev/null || true

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
