#!/bin/bash

# We need to create the ports with shell scripts
# the ansible module currently doesn't provide
# --host argument

set -xe

# Obtain the network_id and secgroup_id from and
# cloud name from ansible task
NET_ID=$1
SECGRP_ID=$2
CLOUD_NAME=$3

export OS_CLOUD=$CLOUD_NAME

# Obtain the list of kubernetes nodes with
# "openstack-control-plane=enabled" label
CONTROLLER_IP_PORT_LIST=()
CTRLS=$(kubectl get nodes -l openstack-control-plane=enabled -o name | awk -F"/" '{print $2}')
for node in $CTRLS
do
  node_short=$(echo "$node" | awk -F"." '{print $1}')
  PORTNAME=octavia-health-manager-port-$node_short
  if ! PORT_DATA=$(openstack port show "$PORTNAME" -c fixed_ips -f json); then
    PORT_DATA=$(openstack port create "$PORTNAME" --security-group "$SECGRP_ID" \
                                                  --device-owner Octavia:health-mgr \
                                                  --host="$node" \
                                                  --network "$NET_ID" \
                                                  -c fixed_ips \
                                                  -f json)
  fi
  for IP in $(echo "$PORT_DATA" | awk 'BEGIN { FS = "\"" } /ip_address/ { print $(NF - 1) }'); do
    CONTROLLER_IP_PORT_LIST+=("$IP:5555")
  done
done

readarray -t sorted < <(for item in "${CONTROLLER_IP_PORT_LIST[@]}"; do echo "${item}"; done | sort)
echo $(IFS=,; echo "${sorted[*]}") > /tmp/octavia_hm_controller_ip_port_list
