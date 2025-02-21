#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2046
set -e

# NOTE(cloudnull): This script is intended to be run on a system that has
#                  multiple physical network interfaces. The script will
#                  disable the hardware offload for the interfaces and set
#                  the RX and TX queue sizes to 90% of the maximum value
#                  to avoid packet loss.
#
#                  This script was written because the default values for
#                  the RX and TX queue sizes are often too low practical
#                  applications and has been observed to cause packet loss
#                  in some cases, when the system is under heavy load.

function ethernetDevs () {
    # Returns all physical devices
    ip -details -json link show | jq -r '.[] |
        if .linkinfo.info_kind // .link_type == "loopback" or (.ifname | test("idrac+")) then
            empty
        else
            .ifname
        end
    '
}

function functionSetMax () {
    if grep -q "0x1af4" /sys/class/net/$1/device/vendor; then
        echo "Skipping virtio device $1"
        return
    fi
    echo "Setting queue max $1"
    # The RX value is set to 90% of the max value to avoid packet loss
    ethtool -G $1 rx $(ethtool --json -g $1 | jq '.[0] | ."rx-max" * .9 | round')
    # The TX value is set to the max value
    ethtool -G $1 tx $(ethtool --json -g $1 | jq '.[0] | ."tx-max"')
}

function functionHWTCOffloadOff () {
    if [[ $(ethtool --json -k $1 | jq '.[] | ."hw-tc-offload"') != "null" ]]; then
        echo "Disabling hw tc offload $dev"
        ethtool -K $1 hw-tc-offload off
    fi
}

jq --version || (echo "jq is not installed. Attempting to install jq" && apt update && apt -y install jq)

ethernetDevs | while read -r dev; do
    functionSetMax $dev
    functionHWTCOffloadOff $dev
done
