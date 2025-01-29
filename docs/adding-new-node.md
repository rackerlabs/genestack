# Adding New Worker Node

## Adding the node in k8s

In order to add a new worker node, we follow the steps as outlined by the kubespray project.
Lets assume we are adding one new worker node: `computegpu001.p40.example.com` and add to relevant sections.

1. Add the node to your ansible inventory file

```shell
   vim /etc/genestack/inventory/inventory.yaml
```

2. Ensure hostname is correctly set and hosts file has 127.0.0.1 entry

3. Run scale.yaml to add the node to your cluster

```shell
   source /opt/genestack/scripts/genestack.rc
   ansible-playbook scale.yml --limit compute-12481.rackerlabs.dev.local --become
```

Once step 3 competes succesfully, validate that the node is up and running in the cluster

```shell
   kubectl get nodes | grep compute-12481.rackerlabs.dev.local
```

### PreferNoSchedule Taint

`PreferNoSchedule` is a preference or "soft" version of `NoSchedule`. The
control plane will try to avoid placing a Pod that does not tolerate the taint
on the node, but it is not guaranteed. This is useful if you want to herd
pods away from specific nodes without preventing them from being scheduled
on entirely. For example, tainting compute nodes is generally recommended so
there is less opportunity for competition of system resources between local
pods and the Nova VMs therein.

!!! tip "Setting this is a matter of architerural preference:"

    ```shell
    kubectl taint nodes compute-12481.rackerlabs.dev.local key1=value1:PreferNoSchedule
    ```

## Adding the node in openstack

Once the node is added in k8s cluster, adding the node to openstack service is simply a matter of labeling the node with the right
labels and annotations.

1. Export the nodes to add

```shell
   export NODES='compute-12481.rackerlabs.dev.local'
```

2. For compute node add the following labels

```shell
   # Label the openstack compute nodes
   kubectl label node compute-12481.rackerlabs.dev.local openstack-compute-node=enabled

   # With OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
   kubectl label node compute-12481.rackerlabs.dev.local openstack-network-node=enabled
```

3. Add the right annotations to the node

```shell
   kubectl annotate \
        nodes \
        ${NODES} \
        ovn.openstack.org/int_bridge='br-int'

   kubectl annotate \
        nodes \
        ${NODES} \
        ovn.openstack.org/bridges='br-ex'

   kubectl annotate \
        nodes \
        ${NODES} \
        ovn.openstack.org/ports='br-ex:bond1'

   kubectl annotate \
        nodes \
        ${NODES} \
        ovn.openstack.org/mappings='physnet1:br-ex'

   kubectl annotate \
        nodes \
        ${NODES} \
        ovn.openstack.org/availability_zones='az1'
```

4. Verify all the services are up and running

```shell
   kubectl get pods -n openstack -o wide | grep "computegpu"
```

At this point the compute node should be up and running and your `openstack` cli command should list the compute node under hosts.

## For PCI passthrough

If you are adding a new node to be a PCI passthrough compute, say for exposing GPU to the vm, at this stage you will have to
setup your PCI Passthrough configuration. Follow steps from:  [Configuring PCI Passthrough in OpenStack](openstack-pci-passthrough.md)

Once the PCI setup is complete follow the instructions from: [Adding Host Aggregates](openstack-host-aggregates.md) to setup host
aggregates for the group of PCI devices. This helps us control the image/flavor/tennant build restriction on a given aggregate to
better use underlying GPU resources.

Once the host aggregate is setup follow the instructions from: [Genestack flavor documentation](openstack-flavors.md) to setup the right flavor.
