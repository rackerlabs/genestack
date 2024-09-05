# Host Aggregates

In OpenStack host aggregates is a way to partition the cloud, or a region of OpenStack cloud into groups based on some characteristics.
For example, we want a group of high performing SSD storage nodes into a group such that a specific ssd flavor can only be build into
these hosts. Host aggregates are not exposed to the end user, instead, cloud admins map different scheduling or flavor or image to a host
aggregate. Host aggregates can also be tied to an avalibility zone (AZ) in OpenStack.

To create a host aggregate called P40 :
```shell
   openstack aggregate create P40

   openstack aggregate show P40
```

Once the aggregate is created, add the host(s) we want in that aggregate:
```shell
   openstack aggregate add host P40 compute001.example.com
```

## PCI Device Example

Lets take and example where we want a group of GPU hosts to be formed into an aggregate, and use traits and scheudling
to ensure that only GPU specific flavors. In this example, we create a custom trait, then associate hosts to the
aggregate and finally use the trait to restrict flavors with the trait to build on the aggregate.

1. First lets create a host aggrgate called GPU.
```shell
   openstack aggregate create GPU
```

2. Add hosts to the aggregate
```shell
   openstack aggregate add host GPU compute001.example.com
   openstack aggregate add host GPU compute002.example.com
```

3. Create a custom trait called HW_GPU
```shell
   openstack --os-placement-api-version 1.6 trait create CUSTOM_HW_GPU
```

4. For each hypervisor in the aggregate add the trait
```shell
   traits=$(openstack --os-placement-api-version 1.6 resource provider trait list -f value <UUID> | sed 's/^/--trait /')
   openstack --os-placement-api-version 1.6 resource provider trait set $traits --trait CUSTOM_HW_GPU <UUID>
```

5. Set the trait on the aggregate
```shell
   openstack --os-compute-api-version 2.53 aggregate set --property trait:CUSTOM_HW_GPU=required GPU
```

6. Assuming you have a flavor called gpu-flavor1
```shell
   openstack flavor set --property trait:CUSTOM_HW_GPU=required gpu-flavor1
```

7. Set Isolating Aggregate Filtering to enabled in nova.conf
```shell
   [scheduler]
   enable_isolated_aggregate_filtering = true
```
