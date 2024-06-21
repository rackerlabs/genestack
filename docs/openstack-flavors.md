# Create Flavors

Flavors in OpenStack are pre-defined configurations of compute, memory, and storage resources for virtual machines. They allow administrators to offer a range of instance sizes to users. Below are the default flavors typically expected in an OpenStack cloud. These flavors can be customized based on your specific requirements. For more detailed information on managing flavors, refer to the [upstream admin documentation](https://docs.openstack.org/nova/latest/admin/flavors.html).

``` shell
openstack --os-cloud default flavor create --public m1.extra_tiny --ram 512 --disk 0 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.tiny --ram 1024 --disk 10 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.small --ram 2048 --disk 20 --vcpus 2 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.medium --ram 4096 --disk 40 --vcpus 4 --ephemeral 8 --swap 2048
openstack --os-cloud default flavor create --public m1.large --ram 8192 --disk 80 --vcpus 6 --ephemeral 16 --swap 4096
openstack --os-cloud default flavor create --public m1.extra_large --ram 16384 --disk 160 --vcpus 8 --ephemeral 32 --swap 8192
```

## Use Case Specific Flavors

While having a standard set of flavors is useful, creating use case-specific flavors can greatly enhance the flexibility and efficiency of your cloud environment. Custom flavors allow you to optimize resource allocation for specific workloads, such as high-performance computing, vendor-specific instructions, and hardware pass-through.

### Example: Vendor-Specific Scheduling

This example configures a flavor that requires deployment on a specific CPU vendor.

``` shell
openstack --os-cloud default flavor create intel.medium
          --public \
          --ram 8192 \
          --disk 60 \
          --vcpus 4 \
          --ephemeral 10 \
          --swap 1024
```

Now, set the capabilities property to ensure that the `cpu_info:vendor` is **Intel**.

``` shell
openstack --os-cloud default flavor set intel.medium \
          --property capabilities:cpu_info:vendor='Intel'
```

### Example: NUMA Preferred Affinity Policy

This example configures a flavor to use the preferred PCI NUMA affinity policy for any Neutron SR-IOV interfaces.

``` shell
openstack --os-cloud default flavor create np.medium \
          --public \
          --ram 8192 \
          --disk 60 \
          --vcpus 4 \
          --ephemeral 10 \
          --swap 1024
```

Now, set the hardware property to ensure that `pci_numa_affinity_policy` is **preferred**.

``` shell
openstack --os-cloud default flavor set np.medium \
          --property hw:pci_numa_affinity_policy=preferred
```

### Example: GPU Passthrough

This example configures a flavor for GPU passthrough with a specific GPU alias, such as the NVIDIA P2000.

``` shell
openstack --os-cloud default flavor create gpu-p2000.medium \
          --public \
          --ram 8192 \
          --disk 60 \
          --vcpus 4 \
          --ephemeral 10 \
          --swap 1024
```

Now, set the hardware property to ensure that `pci_passthrough:alias` is **p2000**.

``` shell
openstack --os-cloud default flavor set gpu-p2000.medium \
          --property pci_passthrough:alias=p2000
```

!!! note

    This assumes that the **p2000** alias has been set up on your compute node. Review the [service-specific overrides](openstack-service-overrides.md) setup for more on custom compute configurations and refer to the [upstream documentation](https://docs.openstack.org/nova/latest/admin/pci-passthrough.html) on leveraging passthrough devices.

## Benefits of Custom Flavors

In OpenStack, flavors define the compute, memory, and storage capacity of nova computing instances. To put it simply, a flavor is an available hardware configuration for a server. It defines the size of a virtual server that can be launched and a custom flavor puts you in control of how your hardware is carved up.

### Resource Optimization

Custom flavors help ensure that resources are allocated efficiently. For example, an HPC workload can be assigned a flavor optimized for high CPU usage, while a database application can be assigned a flavor with ample memory.

### Cost Management

By tailoring flavors to specific use cases, you can manage costs more effectively. Users only consume the resources they need, which can reduce overall cloud expenditure.

### Enhanced Performance

Custom flavors can lead to better performance for specialized workloads. By providing the right mix of resources, applications can run more smoothly and efficiently.

### User Satisfaction

Offering a variety of flavors allows users to select configurations that best meet their needs, leading to higher satisfaction and better utilization of the cloud environment.

## Conclusion

Flavors are a fundamental aspect of OpenStack that enable flexible and efficient resource allocation. By creating both standard and use case-specific flavors, administrators can optimize their cloud environment to meet diverse workload requirements. This not only improves performance and cost-efficiency but also enhances the overall user experience.
