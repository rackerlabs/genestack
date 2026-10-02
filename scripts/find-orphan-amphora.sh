#!/usr/bin/env bash

set -euo pipefail

OS_CLOUD="${OS_CLOUD:-Default}"
CLI=(openstack "--os-cloud=${OS_CLOUD}")
MGMT_NET="${MGMT_NET:-lb-mgmt-net}"
AGGREGATE="${AGGREGATE:-}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/octavia-orphan-audit-${TIMESTAMP}}"

OCTAVIA_IDS="${OUTPUT_DIR}/octavia-compute-ids.txt"
MGMT_SERVER_IDS="${OUTPUT_DIR}/mgmt-server-ids.txt"
REPORTED_IDS="${OUTPUT_DIR}/reported-ids.txt"
REPORT="${OUTPUT_DIR}/orphans.tsv"
CLEANUP="${OUTPUT_DIR}/cleanup.sh"

mkdir -p \
    "${OUTPUT_DIR}/servers" \
    "${OUTPUT_DIR}/ports"

touch \
    "$MGMT_SERVER_IDS" \
    "$REPORTED_IDS"

command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq is required" >&2
    exit 1
}

###############################################################################
# Report headers
###############################################################################

printf 'COMPUTE_ID\tNAME\tSTATUS\tHOST\tCREATED\tMGMT_IP\tMAC\tPORT_ID\tPORT_NAME\n' \
    > "$REPORT"

cat > "$CLEANUP" <<'EOF'
#!/usr/bin/env bash

#
# Octavia orphan cleanup commands
#
# REVIEW EVERY ENTRY BEFORE RUNNING.
#
# Nothing below is enabled automatically.
#

EOF

chmod +x "$CLEANUP"

###############################################################################
# Current Octavia inventory
###############################################################################

echo "Collecting current Octavia amphora records..."

"$CLI" loadbalancer amphora list --long -f json \
    | jq -r '.[] | .compute_id // empty' \
    | sort -u \
    > "$OCTAVIA_IDS"

OCTAVIA_COUNT="$(wc -l < "$OCTAVIA_IDS")"

echo "Current Octavia compute IDs: ${OCTAVIA_COUNT}"
echo

###############################################################################
# Function to record an orphan candidate
###############################################################################

record_candidate() {
    local compute_id="$1"
    local port_id="${2:-}"
    local source="$3"

    #
    # Avoid duplicates.
    #
    if grep -Fxq "$compute_id" "$REPORTED_IDS"; then
        return
    fi

    if ! SERVER_JSON=$("$CLI" server show "$compute_id" -f json 2>/dev/null); then
        echo "WARNING: Nova server disappeared before inspection: $compute_id"
        return
    fi

    echo "$compute_id" >> "$REPORTED_IDS"

    SERVER_NAME="$(jq -r '.name // empty' <<<"$SERVER_JSON")"
    SERVER_STATUS="$(jq -r '.status // empty' <<<"$SERVER_JSON")"
    SERVER_CREATED="$(jq -r '.created // empty' <<<"$SERVER_JSON")"

    SERVER_HOST="$(jq -r '
        .["OS-EXT-SRV-ATTR:host"] //
        .host //
        empty
    ' <<<"$SERVER_JSON")"

    #
    # Save complete Nova details.
    #
    "$CLI" server show "$compute_id" -f yaml \
        > "${OUTPUT_DIR}/servers/${compute_id}.yaml"

    PORT_NAME=""
    PORT_MAC=""
    PORT_IPS=""

    if [[ -n "$port_id" ]]; then
        if PORT_JSON=$("$CLI" port show "$port_id" -f json 2>/dev/null); then

            PORT_NAME="$(jq -r '.name // empty' <<<"$PORT_JSON")"
            PORT_MAC="$(jq -r '.mac_address // empty' <<<"$PORT_JSON")"

            PORT_IPS="$(jq -r '
                (.fixed_ips // []) as $ips
                |
                if ($ips | type) == "array" then
                    [
                        $ips[]
                        | if type == "object"
                          then (.ip_address // empty)
                          else tostring
                          end
                    ] | join(",")
                else
                    $ips | tostring
                end
            ' <<<"$PORT_JSON")"

            #
            # Save complete Neutron port details.
            #
            "$CLI" port show "$port_id" -f yaml \
                > "${OUTPUT_DIR}/ports/${port_id}.yaml"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$compute_id" \
        "$SERVER_NAME" \
        "$SERVER_STATUS" \
        "$SERVER_HOST" \
        "$SERVER_CREATED" \
        "$PORT_IPS" \
        "$PORT_MAC" \
        "$port_id" \
        "$PORT_NAME" \
        >> "$REPORT"

    echo
    echo "================================================================"
    echo "ORPHAN AMPHORA CANDIDATE"
    echo "================================================================"
    echo "Discovery:      $source"
    echo
    echo "Nova server:    $compute_id"
    echo "Name:           $SERVER_NAME"
    echo "Status:         $SERVER_STATUS"
    echo "Compute host:   $SERVER_HOST"
    echo "Created:        $SERVER_CREATED"

    if [[ -n "$port_id" ]]; then
        echo
        echo "Neutron port:   $port_id"
        echo "Port name:      $PORT_NAME"
        echo "Management IP:  $PORT_IPS"
        echo "MAC address:    $PORT_MAC"
    fi

    echo
    echo "Server details:"
    echo "  ${OUTPUT_DIR}/servers/${compute_id}.yaml"

    if [[ -n "$port_id" ]]; then
        echo "Port details:"
        echo "  ${OUTPUT_DIR}/ports/${port_id}.yaml"
    fi

    echo
    echo "VERIFY:"
    echo "  $CLI loadbalancer amphora list --long -f json \\"
    echo "    | jq --arg id \"$compute_id\" '.[] | select(.compute_id == \$id)'"
    echo
    echo "DELETE NOVA SERVER:"
    echo "  $CLI server delete $compute_id"
    echo

    #
    # Add reviewable cleanup entry.
    #
    {
        echo
        echo "########################################################################"
        echo "# Candidate: $compute_id"
        echo "# Name:      $SERVER_NAME"
        echo "# Host:      $SERVER_HOST"
        echo "# Mgmt IP:   $PORT_IPS"
        echo "# Port:      $port_id"
        echo "# Source:    $source"
        echo "#"
        echo "# Verify Octavia does NOT reference this compute_id:"
        echo "#"
        echo "# $CLI loadbalancer amphora list --long -f json \\"
        echo "#   | jq --arg id \"$compute_id\" '.[] | select(.compute_id == \$id)'"
        echo "#"
        echo "# Delete the Nova server after verification:"
        echo "#"
        echo "# $CLI server delete $compute_id"
        echo "########################################################################"
    } >> "$CLEANUP"
}

###############################################################################
# Pass 1:
# Neutron lb-mgmt-net -> Nova server -> Octavia compute_id
###############################################################################

echo "Scanning Neutron management network: ${MGMT_NET}"

while read -r PORT_ID; do
    [[ -z "$PORT_ID" ]] && continue

    if ! PORT_JSON=$("$CLI" port show "$PORT_ID" -f json 2>/dev/null); then
        continue
    fi

    DEVICE_ID="$(jq -r '
        .device_id //
        .["Device ID"] //
        empty
    ' <<<"$PORT_JSON")"

    [[ -z "$DEVICE_ID" ]] && continue

    #
    # Ignore health-manager/worker/controller plumbing.
    # Only continue when device_id is a real Nova server.
    #
    if ! "$CLI" server show "$DEVICE_ID" >/dev/null 2>&1; then
        continue
    fi

    echo "$DEVICE_ID" >> "$MGMT_SERVER_IDS"

    #
    # Known Octavia amphora.
    #
    if grep -Fxq "$DEVICE_ID" "$OCTAVIA_IDS"; then
        continue
    fi

    record_candidate \
        "$DEVICE_ID" \
        "$PORT_ID" \
        "lb-mgmt-net"
done < <(
    "$CLI" port list \
        --network "$MGMT_NET" \
        -f value \
        -c ID
)

###############################################################################
# Pass 2:
# Dedicated aggregate -> Nova -> Octavia
#
# Optional, enabled by setting AGGREGATE.
###############################################################################

if [[ -n "$AGGREGATE" ]]; then

    echo
    echo "Scanning dedicated aggregate: ${AGGREGATE}"

    while read -r HOST; do
        [[ -z "$HOST" ]] && continue

        echo "  Host: $HOST"

        while read -r SERVER_ID; do
            [[ -z "$SERVER_ID" ]] && continue

            #
            # Octavia knows about this VM.
            #
            if grep -Fxq "$SERVER_ID" "$OCTAVIA_IDS"; then
                continue
            fi

            #
            # Already found via lb-mgmt-net.
            #
            if grep -Fxq "$SERVER_ID" "$REPORTED_IDS"; then
                continue
            fi

            #
            # Try to locate its management port.
            #
            PORT_ID=""

            while read -r CANDIDATE_PORT; do
                [[ -z "$CANDIDATE_PORT" ]] && continue

                PORT_NETWORK_ID="$(
                    "$CLI" port show "$CANDIDATE_PORT" -f json 2>/dev/null \
                        | jq -r '.network_id // empty'
                )"

                MGMT_NETWORK_ID="$(
                    "$CLI" network show "$MGMT_NET" -f value -c id
                )"

                if [[ "$PORT_NETWORK_ID" == "$MGMT_NETWORK_ID" ]]; then
                    PORT_ID="$CANDIDATE_PORT"
                    break
                fi

            done < <(
                "$CLI" port list \
                    --device-id "$SERVER_ID" \
                    -f value \
                    -c ID
            )

            record_candidate \
                "$SERVER_ID" \
                "$PORT_ID" \
                "aggregate:${AGGREGATE}"

        done < <(
            "$CLI" server list \
                --all-projects \
                --host "$HOST" \
                -f value \
                -c ID
        )

    done < <(
        "$CLI" aggregate show "$AGGREGATE" -f json \
            | jq -r '.hosts[]?'
    )
fi

###############################################################################
# Finalize
###############################################################################

sort -u -o "$MGMT_SERVER_IDS" "$MGMT_SERVER_IDS"
sort -u -o "$REPORTED_IDS" "$REPORTED_IDS"

ORPHAN_COUNT="$(wc -l < "$REPORTED_IDS")"
MGMT_COUNT="$(wc -l < "$MGMT_SERVER_IDS")"

echo
echo "================================================================"
echo "OCTAVIA ORPHAN AUDIT SUMMARY"
echo "================================================================"
echo "Octavia amphora records:         $OCTAVIA_COUNT"
echo "Nova servers via ${MGMT_NET}:    $MGMT_COUNT"
echo "Orphan candidates:               $ORPHAN_COUNT"
echo
echo "Audit directory:"
echo "  $OUTPUT_DIR"
echo
echo "Candidate report:"
echo "  $REPORT"
echo
echo "Reviewable cleanup commands:"
echo "  $CLEANUP"

if (( ORPHAN_COUNT > 0 )); then
    echo
    echo "Candidates:"
    echo

    column -t -s $'\t' "$REPORT" 2>/dev/null || cat "$REPORT"

    exit 2
fi

echo
echo "No orphan amphora candidates found."

exit 0
