# Setting Service Overrides for Nodes

In cloud environments, it is sometimes necessary to define specific configuration values for unique nodes. This is particularly important for nodes with different CPU types, nodes that pass-through accelerators, and other unique hardware or configuration requirements. This document provides a comprehensive guide on how to define unique configurations for service-specific overrides using Kubernetes and OpenStack.

## Label-Based Overrides

Label-based overrides allow you to configure service-specific settings for an environment by defining a node or label to anchor on and specifying what will be overridden. In the following example, we override configuration values based on the "openstack-compute-cpu-type" label.

### Example: Helm Label Overrides YAML

The following YAML example demonstrates how to set label-based overrides for a cloud deployment that will have two different cpu types, enables some additional scheduler filters by default, and defines a set of shared CPUs that can be used on a given compute host for heterogeneous computing.

| cpu-types   | config overrides |
| ----------- | ---------- |
| default     | Sets an alias for the p2000 GPU for passthrough. Enables additional scheduler filters |
| amd-3900    | Sets a single reserved core for the host. Sets a PCI device specification in support of the p2000 GPU for passthrough. |
| intel-12700 | Sets a set of shared CPUs (used to ensure nova only schedules to P-Cores). |

``` yaml title="Configuration Overrides using Labels"
conf:
  nova:
    filter_scheduler:
      enabled_filters: >-
        ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,
        ServerGroupAffinityFilter,PciPassthroughFilter
      available_filters: nova.scheduler.filters.all_filters
    pci:
      alias: >-
        {"vendor_id": "10de", "product_id": "1c30", "device_type": "type-PCI", "name": "p2000"}
  overrides:
    nova_compute:  # Chart + "_" + Daemonset (nova_compute)
      labels:
        - label:
            key: openstack-compute-cpu-type  # Defines a KEY
            values:
              - "amd-3900"  # Defines a VALUE
          conf:
            nova:
              DEFAULT:
                reserved_host_cpus: "1"
              pci:
                device_spec: >-
                  {"vendor_id": "10de", "product_id": "1c30"}
        - label:
            key: openstack-compute-cpu-type  # Defines a KEY
            values:
              - "intel-12700"  # Defines a VALUE
          conf:
            nova:
              compute:
                cpu_shared_set: "0-15"
```

!!! note "PCI-Passthrough and Filters Notice"

    The above overrides are used to [passthrough a PCI](openstack-pci-passthrough.md) device in support of a GPU type. For more information on GPU passthrough, and how to interact with some of the [advanced scheduling](https://docs.openstack.org/nova/latest/admin/scheduling.html) filter capabilities found in OpenStack, have a look at the official upstream documentation.

#### Label Overrides Explanation

In the above example, two configurations are defined for nodes with the `openstack-compute-cpu-type` label. The system will override the default settings based on the value of this label:

1. For nodes with the label `openstack-compute-cpu-type` and the value of `amd-3900`: the configuration sets `reserved_host_cpus` to "1" in the **default** section.
2. For nodes with the label `openstack-compute-cpu-type` and the value of `intel-12700`: the configuration sets `cpu_shared_set` to "0-15" in the **compute** section.

If a node does not match any of the specified label values, the deployment will proceed with the default configuration.

### Adding Node Labels

To apply the label to a node, use the following `kubectl` command:

``` shell
kubectl label node ${NODE_NAME} ${KEY}=${VALUE}
```

Replace `${NODE_NAME}`, `${KEY}`, and `${VALUE}` with the appropriate node name, key, and value.

## Node-Specific Overrides

Node-specific overrides allow you to configure options for an individual host without requiring additional labeling.

### Example: Helm Node Override YAML

The following YAML example demonstrates how to set node-specific overrides:

``` yaml title="Configuration Overrides using Hosts"
conf:
  overrides:
    nova_compute:  # Chart + "_" + Daemonset (nova_compute)
      hosts:
        - name: ${NODE_NAME}  # Name of the node
          conf:
            nova:
              compute:
                cpu_shared_set: "8-15"
```

#### Node Overrides Explanation

In this example, the configuration sets the `cpu_shared_set` to "8-15" for a specific node identified by `${NODE_NAME}`.

Now, lets also look at a specific example of using pci device address to pass to nova.
Once you have validated that IOMMU is enbled:

```shell title="Get device id"
   lspci -nn | grep -i nvidia
   > 3f:00.0 3D controller [0302]: NVIDIA Corporation GA103 [10de:2321] (rev a1)
   > 56:00.0 3D controller [0302]: NVIDIA Corporation GA103 [10de:2321] (rev a1)
```
In this example, `3f:00.0` and `56:00.0` is the address of the PCI device. The veendor ID is `10de` (for nvidia) and the product ID is `2321`.

You can also confirm that the device is available for PCI passthrough:
```shell
   ls -ld /sys/kernel/iommu_groups/*/devices/*3f:00.?/
```
We can now deploy the configuration override in nova like so:

```yaml title="Configuration Overrides using Hosts"
conf:
  nova:
    pci:
      alias:
        type: multistring
        values:
          - '{"vendor_id": "10de", "product_id": "2321", "device_type": "type-PCI", "name": "h100", "numa_policy": "preferred"}'
          - '{"vendor_id": "10de", "product_id": "1389", "device_type": "type-PCI", "name": "h100", "numa_policy": "preferred"}'
    filter_scheduler:
      enabled_filters: >-
        ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter,AggregateInstanceExtraSpecsFilter,NUMATopologyFilter,PciPassthroughFilter
      available_filters: nova.scheduler.filters.all_filters
  overrides:
    nova_compute:  # Chart + "_" + Daemonset (nova_compute)
      hosts:
        - name: "compute001.h100.example.com"
          conf:
            nova:
                pci:
                  alias:
                    type: multistring
                    values:
                      - '{"vendor_id": "10de", "product_id": "2321", "device_type": "type-PCI", "name": "h100", "numa_policy": "preferred"}'
                      - '{"vendor_id": "10de", "product_id": "1389", "device_type": "type-PCI", "name": "h100", "numa_policy": "preferred"}'
                  device_spec: >-
                    [{"address": "0000:3f:00.0"}, {"address": "0000:56:00.0"}]
                filter_scheduler:
                  enabled_filters: >-
                    ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter,AggregateInstanceExtraSpecsFilter,NUMATopologyFilter,PciPassthroughFilter
                  available_filters: nova.scheduler.filters.all_filters
```

## Deploying Configuration Changes

Once the overrides are in place, simply rerun the `helm` deployment command to apply the changes:

``` shell
helm upgrade --install <release_name> <chart-path> -f <values_file.yaml>
```

## Conclusion

By using label-based and/or node-specific overrides, you can customize the configuration of your Kubernetes and OpenStack environment to meet the specific needs of your environment. This approach ensures that each node operates with the optimal settings based on its hardware and role within the cluster.
