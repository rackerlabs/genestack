#!/bin/bash

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") INSTANCE_ID [COMMAND ...]

  Opens an SSH session to a Trove guest VM. With no COMMAND, an interactive
  shell is opened. With a COMMAND, it is executed in the guest and the exit
  code is propagated.

  NOTE: COMMAND is passed through as-is and re-parsed by the Nova host and
  guest shells. You are responsible for quoting/escaping complex commands so
  they survive those extra shell layers.

options:
  -h    Show this help.

examples:
  # interactive shell
  $(basename "$0") INSTANCE_ID

  # run a command in the guest
  $(basename "$0") INSTANCE_ID ls -alh /etc/mysql
EOF
}

while getopts ":h" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        \?) echo "unknown option: -$OPTARG" >&2; usage; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

INSTANCE_ID=$1
shift || true
# Any remaining arguments are treated as a command to run inside the guest VM.
# When no command is given, an interactive shell is opened as before.
GUEST_CMD="$*"

[[ -n "$INSTANCE_ID" ]] || { usage; exit 2; }

SAVED_OS_CLIENT_CONFIG_FILE=$OS_CLIENT_CONFIG_FILE
export OS_CLIENT_CONFIG_FILE="${HOME}/.config/openstack/clouds.yaml"
OS_CLOUD="${OS_CLOUD:-default}"

cleanup() {
    export OS_CLIENT_CONFIG_FILE=$SAVED_OS_CLIENT_CONFIG_FILE
}

trap cleanup EXIT

source /opt/genestack/scripts/genestack.rc

TROVE_MGMT_NET_ID=$(openstack network show trove-mgmt-net -f value -c id 2>/dev/null)

SERVER_ID=$(openstack --os-cloud "$OS_CLOUD" database instance show \
              "$INSTANCE_ID" -f value -c server_id 2>&1) \
    || { echo "could not look up trove instance $INSTANCE_ID ($SERVER_ID)"; exit 1; }
[[ -n "$SERVER_ID" ]] \
    || { echo "instance $INSTANCE_ID has no server_id yet (still BUILD?)"; exit 1; }

NOVA_HOST=$(openstack --os-cloud "$OS_CLOUD" server show "$SERVER_ID" \
              -f value -c "OS-EXT-SRV-ATTR:host" 2>&1) \
    || echo "could not resolve compute host for server $SERVER_ID ($NOVA_HOST)"

GUEST_IP=$(openstack server show ${SERVER_ID} -f json 2>/dev/null | \
              jq -r '.addresses."trove-mgmt-net"[0]' ) \
    || { echo "no port found for server $SERVER_ID on network $TROVE_MGMT_NET"; exit 1; }

[[ -n "$GUEST_IP"   ]] || { echo "could not determine guest IP"; exit 1; }
[[ -n "$NOVA_HOST" ]] || { echo "could not determine compute host"; exit 1; }

# Interactive sessions (no command) get a TTY. For one-off commands we skip the
# TTY so stdout/stderr and the exit code propagate cleanly.
if [[ -z "$GUEST_CMD" ]]; then
    SSH_TTY_OPT="-tt"
else
    SSH_TTY_OPT=""
fi

# The guest command (if any) is passed through as-is. Because it is re-parsed
# by the Nova host and guest shells, the caller is responsible for any quoting
# needed for complex commands.
NOVA_HOST_CMD=$(cat << EOF
sudo ip netns exec ovnmeta-${TROVE_MGMT_NET_ID} \
ssh ${SSH_TTY_OPT} -i ~/.ssh/trove_ssh_key \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    debian@${GUEST_IP} ${GUEST_CMD:+-- ${GUEST_CMD}}
EOF
)

cat >&2 <<EOF
target:
  instance = ${INSTANCE_ID:-<n/a>}
  server   = ${SERVER_ID:-<n/a>}
  node     = $NOVA_HOST
  guest_ip = $GUEST_IP
  command  = ${GUEST_CMD:-<interactive shell>}
EOF

ssh ${SSH_TTY_OPT} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=true \
    -o IdentityFile=~/.ssh/id_rsa \
    ubuntu@${NOVA_HOST} "${NOVA_HOST_CMD}"
