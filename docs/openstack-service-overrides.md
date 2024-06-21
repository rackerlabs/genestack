# Setting Service Overrides for Nodes

In cloud environments, it is sometimes necessary to define specific configuration values for unique nodes. This is particularly important for nodes with different CPU types, nodes that pass-through accelerators, and other unique hardware or configuration requirements. This document provides a comprehensive guide on how to define unique configurations for service-specific overrides using Kubernetes and OpenStack.

## Label-Based Overrides

Label-based overrides allow you to configure service-specific settings for an environment by defining a node or label to anchor on and specifying what will be overridden. In the following example, we override configuration values based on the "openstack-compute-cpu-type" label.

### Example: Helm Label Overrides YAML

The following YAML example demonstrates how to set label-based overrides:

``` yaml title="Configuration Overrides using Labels"
conf:
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
        - label:
            key: openstack-compute-cpu-type  # Defines a KEY
            values:
              - "intel-12700"  # Defines a VALUE
          conf:
            nova:
              compute:
                cpu_shared_set: "0-15"
```

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

## Deploying Configuration Changes

Once the overrides are in place, simply rerun the `helm` deployment command to apply the changes:

``` shell
helm upgrade --install <release_name> <chart-path> -f <values_file.yaml>
```

## Conclusion

By using label-based and/or node-specific overrides, you can customize the configuration of your Kubernetes and OpenStack environment to meet the specific needs of your environment. This approach ensures that each node operates with the optimal settings based on its hardware and role within the cluster.
