#!/bin/bash

INSTANCE_ID=$1

OS_CLOUD="${OS_CLOUD:-default}"

source /opt/genestack/scripts/genestack.rc

TROVE_MGMT_NET_ID=$(openstack network show trove-mgmt-net -f value -c id 2>/dev/null)

SERVER_ID=$(openstack --os-cloud "$OS_CLOUD" database instance show \
              "$INSTANCE_ID" -f value -c server_id 2>/dev/null) \
    || die "could not look up trove instance $INSTANCE_ID (deleted? wrong cloud?)"
[[ -n "$SERVER_ID" ]] \
    || die "instance $INSTANCE_ID has no server_id yet (still BUILD?)"

NOVA_HOST=$(openstack --os-cloud "$OS_CLOUD" server show "$SERVER_ID" \
              -f value -c "OS-EXT-SRV-ATTR:host" 2>/dev/null) \
    || die "could not resolve compute host for server $SERVER_ID"

GUEST_IP=$(openstack server show ${SERVER_ID} -f json 2>/dev/null | \
              jq -r '.addresses."trove-mgmt-net"[0]' ) \
    || die "no port found for server $SERVER_ID on network $TROVE_MGMT_NET"

[[ -n "$GUEST_IP"   ]] || die "could not determine guest IP"
[[ -n "$NOVA_HOST" ]] || die "could not determine compute host"

NOVA_HOST_CMD=$(cat << EOF
sudo ip netns exec ovnmeta-${TROVE_MGMT_NET_ID} \
ssh -tt -i ~/.ssh/trove_ssh_key \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    debian@${GUEST_IP}
EOF
)

cat >&2 <<EOF
target:
  instance = ${INSTANCE_ID:-<n/a>}
  server   = ${SERVER_ID:-<n/a>}
  node     = $NOVA_HOST
  guest_ip = $GUEST_IP
EOF

ssh -tt \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=true \
    -o IdentityFile=~/.ssh/id_rsa \
    ubuntu@${NOVA_HOST} "${NOVA_HOST_CMD}"
