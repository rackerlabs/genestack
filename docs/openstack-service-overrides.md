# Setting Service Overrides for Nodes

Running a cloud will sometimes require defining specific configuration values for unique nodes; for example nodes with different CPU types, Nodes will pass-through accelerators, etc. This short doc covers how to define unique configuration for service specific overrides.

## Label Based Overrides

It is possible to configure service specific overrides for an environment by simply defining a node or label to anchor on
and what will be overridden. In this ecample we are overriding the configuration values based on the "openstack-compute-cpu-type" type.

``` yaml title="Helm Label Overrides YAML"
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

The above example creates two new possibilities when the label `openstack-compute-cpu-type` is used. The value of this label type will need to match one of the provided options in the override condition. If there's no match, the deployment system will run in default mode, without any of the override content.

To label the node to use this example, simple set the value for the node or set of nodes accordingly.

``` shell title="Adding Node Labels"
kubectl label node ${NODE_NAME} ${KEY}=${VALUE}
```

Once all of the nodes are labeled, run the `helm` deployment commands to push the changes into the environment.

## Node Specific Overrides

It is also possible to override specific options on one specific host by defining a host level override.

``` yaml title="Helm Node Override YAML"
conf:
  overrides:
    nova_compute:  # Chart + "_" + Daemonset (nova_compute)
      hosts:
        - name: ${NODE_NAME}  # name of the node
          conf:
            nova:
              compute:
                cpu_shared_set: "8-15"
```

The node specific value does not require any additional labeling. Once the config is in place, simply rerun the `helm` deployment command to push the configuration into the environment.
