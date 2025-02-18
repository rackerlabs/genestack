#!/bin/bash
cd testing || exit
yes y | ssh-keygen -q -f ./key -N ""
openstack --os-cloud default stack create --wait -t build.yaml --environment ~/env.yaml testing
nodes=$(openstack --os-cloud default stack output show testing all_out -f value -c output_value)

cleanlist="${nodes//[\[\]\'\,]/}" # 'Remove brackets, single quotes, and commas
ips=("$cleanlist")                  # Convert the cleaned string into a Bash array

# Define the machine names
machine_names=("controller1" "controller2" "controller3")

# Initialize the YAML content
yaml_content="all:\n  hosts:"

# Generate the 'hosts' section using the Bash array
for i in "${!machine_names[@]}"; do
  yaml_content+="\n    ${machine_names[$i]}.openstacklocal:\n      ansible_host: '${ips[$i]}'"
done

# Add the 'children' section
yaml_content+="\n  children:"
yaml_content+="\n    k8s_cluster:"
yaml_content+="\n      vars:"
yaml_content+="\n        cluster_name: cluster.local"
yaml_content+="\n        kube_ovn_iface: ens3"
yaml_content+="\n        kube_ovn_default_interface_name: ens3"
yaml_content+="\n        kube_ovn_central_hosts: \"{{ groups['ovn_network_nodes'] }}\""
yaml_content+="\n      children:"
yaml_content+="\n        kube_control_plane:"
yaml_content+="\n          hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n            ${name}.openstacklocal: null"
done

yaml_content+="\n        etcd:"
yaml_content+="\n          hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n            ${name}.openstacklocal: null"
done

yaml_content+="\n        kube_node:"
yaml_content+="\n          hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n            ${name}.openstacklocal: null"
done

yaml_content+="\n        openstack-control-plane:"
yaml_content+="\n          hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n            ${name}.openstacklocal: null"
done

yaml_content+="\n        ovn_network_nodes:"
yaml_content+="\n          hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n            ${name}.openstacklocal: null"
done

yaml_content+="\n        storage_nodes:"
yaml_content+="\n          children:"
yaml_content+="\n            ceph_storage_nodes:"
yaml_content+="\n              hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n                ${name}.openstacklocal: null"
done

yaml_content+="\n            cinder_storage_nodes:"
yaml_content+="\n              hosts: {}"
yaml_content+="\n            openstack-compute-node:"
yaml_content+="\n              hosts:"
for name in "${machine_names[@]}"; do
  yaml_content+="\n                ${name}.openstacklocal: null"
done

echo -e "$yaml_content" > ./inventory.yaml

sleep 5m

# Prep all nodes
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.yaml --private-key ./key fix-root.yaml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.yaml --private-key ./key deploy.yaml
