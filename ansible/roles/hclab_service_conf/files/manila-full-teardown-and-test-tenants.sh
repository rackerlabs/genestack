#!/bin/bash
# ==========================================================================
# manila-full-teardown.sh
#
# Tears down ALL Manila resources: Helm release, K8s objects, share server
# VMs, service network/subnet, router, security groups, keypair, and image.
#
# Run as: ubuntu@controller
# Requires: genestack venv, admin cloud credentials
# ==========================================================================

# --------------------------------------------------------------------------
# Environment setup
# --------------------------------------------------------------------------
source /home/ubuntu/.venvs/genestack/bin/activate
set -a
source /opt/genestack/scripts/genestack.rc
set +a
export HOME=/home/ubuntu
OS="openstack --os-cloud=default"

echo "============================================================"
echo "  MANILA FULL TEARDOWN"
echo "============================================================"

# --------------------------------------------------------------------------
# 1) Uninstall Manila Helm release and delete ALL k8s resources
# --------------------------------------------------------------------------
echo ""
echo ">>> [1/7] Removing Manila Helm release..."
helm -n openstack uninstall manila --wait 2>/dev/null || echo "  (no helm release found)"

echo ">>> [1/7] Deleting Manila K8s jobs..."
kubectl -n openstack delete job \
  manila-db-sync \
  manila-ks-endpoints \
  manila-ks-service \
  manila-ks-user \
  --ignore-not-found=true 2>/dev/null || true

echo ">>> [1/7] Deleting Manila K8s secrets..."
for secret in \
  manila-admin \
  manila-db-admin \
  manila-db-password \
  manila-db-user \
  manila-etc \
  manila-keystone-admin \
  manila-keystone-user \
  manila-rabbitmq-admin \
  manila-rabbitmq-password \
  manila-rabbitmq-user \
  manila-service-keypair \
  manila-user-credentials; do
  kubectl -n openstack delete secret "$secret" --ignore-not-found=true 2>/dev/null || true
done

echo ">>> [1/7] Deleting Manila Helm release secrets..."
kubectl -n openstack delete secret -l name=manila,owner=helm --ignore-not-found=true 2>/dev/null || true

echo ">>> [1/7] Deleting Manila configmaps..."
kubectl -n openstack delete cm manila-bin --ignore-not-found=true 2>/dev/null || true

# --------------------------------------------------------------------------
# 2) Delete Manila share servers (VMs) if any exist
# --------------------------------------------------------------------------
echo ""
echo ">>> [2/7] Deleting Manila share server VMs..."
MANILA_SERVERS=$($OS server list --all-projects -f json 2>/dev/null \
  | python3 -c '
import json, sys
servers = json.load(sys.stdin)
for s in servers:
    name = s.get("Name", "").lower()
    if "manila" in name or "share" in name:
        print(s["ID"])
' 2>/dev/null) || true

if [ -n "$MANILA_SERVERS" ]; then
  for sid in $MANILA_SERVERS; do
    echo "  Deleting server $sid..."
    $OS server delete "$sid" --wait 2>/dev/null || true
  done
else
  echo "  (no Manila VMs found)"
fi

# --------------------------------------------------------------------------
# 3) Delete ports on manila-service-network
# --------------------------------------------------------------------------
echo ""
echo ">>> [3/7] Deleting ports on manila-service-network..."
MANILA_PORTS=$($OS port list --network manila-service-network -f json 2>/dev/null \
  | python3 -c 'import json,sys; [print(p["ID"]) for p in json.load(sys.stdin)]' 2>/dev/null) || true

if [ -n "$MANILA_PORTS" ]; then
  for pid in $MANILA_PORTS; do
    echo "  Deleting port $pid..."
    $OS router remove port manila-share-router "$pid" 2>/dev/null || true
    $OS port delete "$pid" 2>/dev/null || true
  done
else
  echo "  (no ports found)"
fi

# --------------------------------------------------------------------------
# 4) Delete manila-service-subnet and manila-service-network
# --------------------------------------------------------------------------
echo ""
echo ">>> [4/7] Deleting manila-service-network and subnet..."

SUBNET_ID=$($OS subnet show manila-service-subnet -f json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null) || true

if [ -n "$SUBNET_ID" ]; then
  ROUTER_IDS=$($OS router list -f json 2>/dev/null \
    | python3 -c 'import json,sys; [print(r["ID"]) for r in json.load(sys.stdin)]' 2>/dev/null) || true
  for rid in $ROUTER_IDS; do
    $OS router remove subnet "$rid" "$SUBNET_ID" 2>/dev/null || true
  done
  $OS subnet delete manila-service-subnet 2>/dev/null || echo "  (subnet already gone)"
else
  echo "  (subnet not found)"
fi

$OS network delete manila-service-network 2>/dev/null || echo "  (network already gone)"

# --------------------------------------------------------------------------
# 5) Delete Manila router
# --------------------------------------------------------------------------
echo ""
echo ">>> [5/7] Deleting Manila router(s)..."

ROUTER_INFO=$($OS router show manila-share-router -f json 2>/dev/null) || true
if [ -n "$ROUTER_INFO" ]; then
  IFACE_SUBNETS=$(echo "$ROUTER_INFO" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for iface in d.get("interfaces_info", []):
    print(iface["subnet_id"])
' 2>/dev/null) || true

  for sub in $IFACE_SUBNETS; do
    echo "  Removing subnet $sub from manila-share-router..."
    $OS router remove subnet manila-share-router "$sub" 2>/dev/null || true
  done

  $OS router unset --external-gateway manila-share-router 2>/dev/null || true

  echo "  Deleting manila-share-router..."
  $OS router delete manila-share-router 2>/dev/null || true
else
  echo "  (no manila-share-router found)"
fi

# --------------------------------------------------------------------------
# 6) Delete Manila security groups
# --------------------------------------------------------------------------
echo ""
echo ">>> [6/7] Deleting Manila security groups..."
MANILA_SGS=$($OS security group list --project admin -f json 2>/dev/null \
  | python3 -c '
import json, sys
for sg in json.load(sys.stdin):
    if "manila" in sg.get("Name", "").lower():
        print(sg["ID"])
' 2>/dev/null) || true

if [ -n "$MANILA_SGS" ]; then
  for sgid in $MANILA_SGS; do
    echo "  Deleting security group $sgid..."
    $OS security group delete "$sgid" 2>/dev/null || true
  done
else
  echo "  (no Manila security groups found)"
fi

# --------------------------------------------------------------------------
# 7) Delete Manila OpenStack keypair, Glance image, and quota marker
# --------------------------------------------------------------------------
echo ""
echo ">>> [7/7] Deleting Manila keypair, image, and quota marker..."
$OS keypair delete manila-service-keypair 2>/dev/null || echo "  (keypair already gone)"
$OS image delete manila-service-image 2>/dev/null || echo "  (image already gone)"
rm -f /etc/genestack/.manila_quotas_applied && echo "  Removed quota marker" || true

echo ""
echo "============================================================"
echo "  MANILA TEARDOWN COMPLETE"
echo "============================================================"
echo ""
echo "Next step: run the manila_preconf ansible role to re-deploy"
