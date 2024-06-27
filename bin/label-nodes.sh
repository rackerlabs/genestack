#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <inventory_file>"
    exit 1
fi
INVENTORY_FILE="$1"

# Define the function to label nodes
label_nodes() {
    local group=$1
    local label=$2
    
    if grep -q "$group:" $INVENTORY_FILE; then
        local nodes=($(grep -A 1 "children:" $INVENTORY_FILE | grep -A 1 "  $group:" | grep -Eo "^\s+\S+" | tr -d ' '))
        for node in "${nodes[@]}"; do
            if [[ $node != "|" ]]; then
                kubectl label node $node $label --overwrite
                echo "Labeled node $node with $label"
            fi
        done
    else
        echo "Group $group does not exist in the inventory file."
    fi
}

# Label the storage nodes identified by ceph_storage_nodes
label_nodes "ceph_storage_nodes" "role=storage-node"

# Label the openstack controllers identified by openstack_control_plane
label_nodes "openstack_control_plane" "openstack-control-plane=enabled"

# Label the openstack compute nodes identified by openstack_compute_nodes
label_nodes "openstack_compute_nodes" "openstack-compute-node=enabled"

# Label the openstack storage nodes identified by cinder_storage_nodes
label_nodes "cinder_storage_nodes" "openstack-storage-node=enabled"

# Label network nodes identified by ovn_network_nodes
label_nodes "ovn_network_nodes" "openstack-network-node=enabled"

# Label all workers - Identified by kube_node excluding kube_control_plane
if grep -q "kube_node:" $INVENTORY_FILE; then
    kube_control_plane_nodes=($(grep -A 1 "children:" $INVENTORY_FILE | grep -A 1 "  kube_control_plane:" | grep -Eo "^\s+\S+" | tr -d ' '))
    all_kube_nodes=($(grep -A 1 "children:" $INVENTORY_FILE | grep -A 1 "  kube_node:" | grep -Eo "^\s+\S+" | tr -d ' '))

    for node in "${all_kube_nodes[@]}"; do
        if [[ ! " ${kube_control_plane_nodes[@]} " =~ " ${node} " ]]; then
            kubectl label node $node node-role.kubernetes.io/worker=worker --overwrite
            echo "Labeled node $node with node-role.kubernetes.io/worker=worker"
        fi
    done
else
    echo "Group kube_node does not exist in the inventory file."
fi

kubectl get nodes -o json | jq '[.items[] | {"NAME": .metadata.name, "LABELS": .metadata.labels}]'
