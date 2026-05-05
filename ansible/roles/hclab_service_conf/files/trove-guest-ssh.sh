#!/bin/bash
# trove-guest-ssh.sh — log into a Trove guest VM via the per-chassis
# trove-mgmt-bridge pod's network namespace (path-B nsenter pattern).
#
# Trove guest VMs sit on trove-mgmt-net (geneve overlay, no L3 route
# from cluster pods), so reaching them requires nsenter'ing into the
# trove-mgmt-bridge pod that's pinned to the same OVN chassis as the
# guest's compute host. This script wraps the whole chain:
#   instance → server → compute host → bridge pod → guest mgmt IP.
#
# Run from the genestack overseer (needs `kubectl`, `openstack` CLI,
# and ssh-as-ubuntu access to the compute hosts).
#
# USAGE:
#   trove-guest-ssh.sh INSTANCE_ID                          # interactive shell
#   trove-guest-ssh.sh INSTANCE_ID -- COMMAND [ARGS...]     # one-shot
#   trove-guest-ssh.sh --server SERVER_UUID [...]
#   trove-guest-ssh.sh --ip GUEST_MGMT_IP --node NODE [...]
#
# FLAGS:
#   -h, --help        show usage
#   -v, --verbose     log resolution steps to stderr
#       --server ID   skip the database-instance lookup, use this Nova UUID
#       --ip IP       skip the port lookup, use this guest mgmt IP
#       --node NAME   skip the server lookup, use this compute host short name
#                     (e.g. hyperconverged-1)
#
# ENV:
#   OS_CLOUD          os-cloud name                    (default: default)
#   TROVE_KEY         ssh key path on the compute host (default: /home/ubuntu/.ssh/trove_ssh_key)
#   TROVE_MGMT_NET    Neutron network name             (default: trove-mgmt-net)
#
# EXAMPLES:
#   trove-guest-ssh.sh 412daca6-c17b-47ca-a33c-a83cd19a2897
#   trove-guest-ssh.sh 412daca6-... -- sudo systemctl status guest-agent
#   trove-guest-ssh.sh 412daca6-... -- sudo grep -nE 'auth|version' /etc/mysql/my.cnf
#   trove-guest-ssh.sh --ip 172.31.0.174 --node hyperconverged-1 -- docker ps -a
#
# EXIT CODES:
#   0  success (or guest command's exit code passed through)
#   1  argument parse error
#   2  resolution error (no such instance, no port, no bridge pod, ...)
#   3  remote crictl/nsenter failure on the compute host
#   *  whatever the inner ssh / guest command returned

set -euo pipefail

SCRIPT="$(basename "$0")"

# --- arg parsing -------------------------------------------------------------

INSTANCE_ID=""
SERVER_ID=""
GUEST_IP=""
NODE_SHORT=""
COMMAND=()
VERBOSE=0

usage() {
    sed -n '/^# USAGE:/,/^# EXIT CODES:/p' "$0" | sed -E 's/^# ?//'
    exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage 0 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        --server)     SERVER_ID="${2:?--server needs a value}"; shift 2 ;;
        --ip)         GUEST_IP="${2:?--ip needs a value}";       shift 2 ;;
        --node)       NODE_SHORT="${2:?--node needs a value}";   shift 2 ;;
        --)           shift; COMMAND=("$@"); break ;;
        -*)           echo "$SCRIPT: unknown flag: $1" >&2; usage 1 ;;
        *)
            if [[ -z "$INSTANCE_ID" && -z "$SERVER_ID" && -z "$GUEST_IP" ]]; then
                INSTANCE_ID="$1"
            else
                echo "$SCRIPT: unexpected positional arg: $1" >&2
                usage 1
            fi
            shift
            ;;
    esac
done

# --- config ------------------------------------------------------------------

OS_CLOUD="${OS_CLOUD:-default}"
TROVE_KEY="${TROVE_KEY:-/home/ubuntu/.ssh/trove_ssh_key}"
TROVE_MGMT_NET="${TROVE_MGMT_NET:-trove-mgmt-net}"
KUBECTL=(sudo kubectl --kubeconfig=/root/.kube/config)

# Auto-activate the genestack venv so `openstack` resolves on the overseer.
if [[ -z "${VIRTUAL_ENV:-}" && -f /opt/genestack/scripts/genestack.rc ]]; then
    # shellcheck disable=SC1091
    source /opt/genestack/scripts/genestack.rc
fi

log() { (( VERBOSE )) && echo "[$SCRIPT] $*" >&2 || true; }
die() { echo "[$SCRIPT] error: $*" >&2; exit 2; }

for cmd in openstack kubectl ssh python3; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

# --- resolve target ----------------------------------------------------------

# instance → server
if [[ -n "$INSTANCE_ID" && -z "$SERVER_ID" ]]; then
    log "resolving instance $INSTANCE_ID → server_id"
    SERVER_ID=$(openstack --os-cloud "$OS_CLOUD" database instance show \
                  "$INSTANCE_ID" -f value -c server_id 2>/dev/null) \
        || die "could not look up trove instance $INSTANCE_ID (deleted? wrong cloud?)"
    [[ -n "$SERVER_ID" ]] \
        || die "instance $INSTANCE_ID has no server_id yet (still BUILD?)"
fi

# server → guest mgmt IP
if [[ -z "$GUEST_IP" && -n "$SERVER_ID" ]]; then
    log "resolving server $SERVER_ID → mgmt IP on $TROVE_MGMT_NET"
    GUEST_IP=$(
        openstack --os-cloud "$OS_CLOUD" port list \
            --server "$SERVER_ID" \
            --network "$TROVE_MGMT_NET" \
            -f value -c "Fixed IP Addresses" 2>/dev/null \
        | python3 -c '
import sys, ast
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)
data = ast.literal_eval(raw)
print(data[0]["ip_address"])
' 2>/dev/null
    ) || die "no port found for server $SERVER_ID on network $TROVE_MGMT_NET"
fi

# server → compute host
if [[ -z "$NODE_SHORT" && -n "$SERVER_ID" ]]; then
    log "resolving server $SERVER_ID → compute host"
    NOVA_HOST=$(openstack --os-cloud "$OS_CLOUD" server show "$SERVER_ID" \
                  -f value -c "OS-EXT-SRV-ATTR:host" 2>/dev/null) \
        || die "could not resolve compute host for server $SERVER_ID"
    NODE_SHORT="${NOVA_HOST%%.*}"
fi

[[ -n "$GUEST_IP"   ]] || die "could not determine guest IP (try --ip)"
[[ -n "$NODE_SHORT" ]] || die "could not determine compute host (try --node)"

# compute host → bridge pod (pinned via app=trove-mgmt-bridge label)
log "looking up trove-mgmt-bridge pod on $NODE_SHORT"
POD=$(
    "${KUBECTL[@]}" -n openstack get pods -l app=trove-mgmt-bridge \
        -o jsonpath="{.items[?(@.spec.nodeName=='${NODE_SHORT}.cluster.local')].metadata.name}" 2>/dev/null
)
[[ -n "$POD" ]] || die "no trove-mgmt-bridge pod on node $NODE_SHORT"

cat >&2 <<EOF
[$SCRIPT] target:
  instance = ${INSTANCE_ID:-<n/a>}
  server   = ${SERVER_ID:-<n/a>}
  node     = $NODE_SHORT
  bridge   = $POD
  guest_ip = $GUEST_IP
EOF

# --- compose & run remote pipeline -------------------------------------------
# Layers, outside-in:
#   ssh overseer → compute host
#     crictl pid lookup (haproxy container in the bridge pod)
#     sudo nsenter -n
#       sudo -u ubuntu ssh ubuntu@<guest>
#         user's command (or login shell)
#
# The trick is feeding the user's command through three shells (overseer,
# compute host, guest) without losing escaping. Strategy:
#   1. Locally, run printf %q on each user arg → produces a re-evaluable
#      shell-quoted token.
#   2. Embed the joined token string in the remote payload via printf %q
#      again, so the compute host's bash assigns it cleanly to USER_CMD.
#   3. Word-split USER_CMD (unquoted) when invoking inner ssh — each
#      printf-%q'd token becomes one argv entry on its way to the guest.
#   4. ssh joins those argv entries with spaces and sends them to the
#      guest's sshd, which runs them via the user's login shell. The
#      printf-%q escaping survives this last shell evaluation.

if [[ ${#COMMAND[@]} -eq 0 ]]; then
    INNER_TT="-tt"
    OUTER_TT="-tt"
    USER_CMD=""
else
    INNER_TT=""
    OUTER_TT=""
    USER_CMD=$(printf '%q ' "${COMMAND[@]}")
fi

remote_payload=$(cat <<EOF
set -e
POD=$(printf '%q' "$POD")
GUEST_IP=$(printf '%q' "$GUEST_IP")
TROVE_KEY=$(printf '%q' "$TROVE_KEY")
USER_CMD=$(printf '%q' "$USER_CMD")

SANDBOX=\$(sudo crictl pods --name "\$POD" -q | head -1)
[[ -n "\$SANDBOX" ]] || { echo "no crictl sandbox for pod \$POD" >&2; exit 3; }

CONT=\$(sudo crictl ps --name haproxy -q --pod "\$SANDBOX" | head -1)
[[ -n "\$CONT" ]] || { echo "no haproxy container in pod \$POD" >&2; exit 3; }

PID=\$(sudo crictl inspect "\$CONT" \\
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["pid"])')
[[ -n "\$PID" ]] || { echo "no PID for haproxy container \$CONT" >&2; exit 3; }

# USER_CMD is intentionally UNquoted on the inner ssh line: each
# printf-%q'd word becomes its own argv entry passed to ssh.
exec sudo nsenter -t "\$PID" -n -- sudo -u ubuntu ssh $INNER_TT \\
    -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o LogLevel=ERROR \\
    -o ConnectTimeout=10 \\
    -i "\$TROVE_KEY" ubuntu@"\$GUEST_IP" \$USER_CMD
EOF
)

log "ssh'ing to $NODE_SHORT and executing remote payload"
exec ssh $OUTER_TT \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "$NODE_SHORT" "$remote_payload"
