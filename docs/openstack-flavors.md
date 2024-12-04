# Create Flavors

Flavors in OpenStack are pre-defined configurations of compute, memory, and storage resources for virtual machines. They allow administrators to offer a range of instance sizes to users. Below are the default flavors typically expected in an OpenStack cloud. These flavors can be customized based on your specific requirements. For more detailed information on managing flavors, refer to the [upstream admin documentation](https://docs.openstack.org/nova/latest/admin/flavors.html).

## Flavor Anatomy

Our flavors follow a simple to understand flow which lets a user better understand what they're getting at a glance.

``` mermaid
flowchart LR
    id1{{NAME}} o-.-o id2{{GENERATION}} o-.-o id3{{CPU}} o-.-o id4{{MEMORY}}
```

### Flavor Naming

The current naming conventions are all strings and fall under one of four classes.

| Key | Description |
| --- | ----------- |
| gp | General Purpose |
| co | Compute Optimized |
| ao | Accelerator Optimized |
| mo | Memory Optimized |

### Flavor Generation

The generation slot is an integer that starts at 0. Within the Rackspace OpenStack this value is tied to the hardware generation being supported by the flavor itself.

### Flavor CPU

The CPU slot is an integrate representing the number of vCPU a flavor will provide to an instance.

### Flavor Memory

The Memory slot is an integrate representing the gigabytes of RAM a flavor will provide to an instance.

## Flavor Resource Breakdown

The flavors used within our Genestack environment have been built to provide the best possible default user experience. Our flavors create an environment with the following specifications.

| Name | GB | vCPU | Local Disk (GB) | Ephemeral Disk (GB) | Swap Space (MB) | Max Network Bandwidth (Gbps) |
| ---- | -- | ---- | --------------- | ------------------- | --------------- | ---------------------------- |
| gp.0.1.2 | 2 | 1 | 10 | 0 | 0 | 2 |
| gp.0.1.4 | 4 | 1 | 10 | 0 | 0 | 4 |
| gp.0.2.2 | 2 | 2 | 40 | 0 | 1024 | 2 |
| gp.0.2.4 | 4 | 2 | 40 | 0 | 1024 | 4 |
| gp.0.2.6 | 6 | 2 | 40 | 0 | 1024 | 4 |
| gp.0.2.8 | 8 | 2 | 40 | 0 | 1024 | 6 |
| gp.0.4.4 | 4 | 4 | 80 | 64 | 4096 | 4 |
| gp.0.4.8 | 8 | 4 | 80 | 64 | 4096 | 6 |
| gp.0.4.12 | 12 | 4 | 80 | 64 | 4096 | 6 |
| gp.0.4.16 | 16 | 4 | 80 | 64 | 4096 | 8 |
| gp.0.8.16 | 16 | 8 | 160 | 128 | 8192 | 8 |
| gp.0.8.24 | 24 | 8 | 160 | 128 | 8192 | 10 |
| gp.0.8.32 | 32 | 8 | 160 | 128 | 8192 | 10 |
| gp.0.16.64 | 64 | 16 | 240 | 128 | 8192 | 10 |
| gp.0.24.96 | 96 | 24 | 240 | 128 | 8192 | 10 |
| gp.0.32.128 | 128 | 32 | 240 | 128 | 8192 | 10 |
| gp.0.48.192 | 192 | 48 | 240 | 128 | 8192 | 10 |
| mo.1.2.12 | 12 | 2 | 80 | 0 | 0 | 6 |
| mo.1.2.16 | 16 | 2 | 80 | 0 | 0 | 8 |
| mo.1.4.20 | 20 | 4 | 80 | 0 | 0 | 10 |
| mo.1.4.24 | 24 | 4 | 80 | 0 | 0 | 10 |
| mo.1.4.32 | 32 | 4 | 80 | 0 | 0 | 10 |
| mo.1.8.64 | 64 | 8 | 80 | 0 | 0 | 10 |

## Flavor Properties

Flavor properties provide some additional configuration to highlight placement and create hardware functionality.

| Property | Value | Description |
| ---------|-------|-------------|
| hw:mem_page_size | any | Defines how hughpages are used within the instance type, our default is auto, acceptible options could also be `small` or `large` |
| hw:cpu_max_threads | 1 | Sets the max number of threads per-core used within the instances. |
| hw:cpu_max_sockets | 2 | Sets the max number of sockets used within the instances. While any integer is acceptible, the highest recommended maximum is 4. |
| :category | String | Display property used within skyline to group flavor classes. Our options are `general_purpose`, `memory_optimized`, and `compute_optimized`. |
| :architecture | x86_architecture | Display property used within skyline to group flavor classes. Our option is currently limited to `x86_architecture` |
| quota:vif_inbound_peak | int | Defines the maximum allowed inbound (ingress) bandwidth on the network interface, representing the peak throughput for incoming data to the instance. The speed limit values are specified in kilobytes/second |
| quota:vif_inbound_burst | int | Specifies the maximum burst rate for inbound traffic. The burst is the allowance for temporary spikes in traffic, higher than the average rate but still within the maximum peak limit. The burst value is in kilobytes |
| quota:vif_inbound_average | int | Sets the average allowable bandwidth for inbound traffic over a sustained period. This is typically the sustained rate at which the instance can receive data, usually lower than the peak and burst rates. The speed limit values are specified in kilobytes/second |
| quota:vif_outbound_peak | int | Defines the maximum bandwidth allowed for outbound (egress) traffic on the network interface. Similar to inbound, it sets the peak limit for data leaving the instance. The speed limit values are specified in kilobytes/second |
| quota:vif_outbound_burst | int | Specifies the maximum burst rate for outbound traffic, allowing short-term spikes in the outgoing traffic, similar to the inbound burst rate. The burst value is in kilobytes |
| quota:vif_outbound_average | int | Sets the average bandwidth for outbound traffic over time, ensuring that the sustained outgoing traffic rate does not exceed this value over a longer period. The speed limit values are specified in kilobytes/second |


----

??? example "Example Creation of Flavors Built for Production"

    ``` shell
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 2048 --vcpu 1 --disk 10 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="250000" --property "quota:vif_inbound_burst"="250000" --property "quota:vif_inbound_average"="125000" --property "quota:vif_outbound_peak"="250000" --property "quota:vif_outbound_burst"="250000" --property "quota:vif_outbound_average"="125000" gp.0.1.2
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 4096 --vcpu 1 --disk 10 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="500000" --property "quota:vif_inbound_burst"="500000" --property "quota:vif_inbound_average"="250000" --property "quota:vif_outbound_peak"="500000" --property "quota:vif_outbound_burst"="500000" --property "quota:vif_outbound_average"="250000" gp.0.1.4
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 2048 --vcpu 2 --disk 40 --ephemeral 0 --swap 1024 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="250000" --property "quota:vif_inbound_burst"="250000" --property "quota:vif_inbound_average"="125000" --property "quota:vif_outbound_peak"="250000" --property "quota:vif_outbound_burst"="250000" --property "quota:vif_outbound_average"="125000" gp.0.2.2
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 4096 --vcpu 2 --disk 40 --ephemeral 0 --swap 1024 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="500000" --property "quota:vif_inbound_burst"="500000" --property "quota:vif_inbound_average"="250000" --property "quota:vif_outbound_peak"="500000" --property "quota:vif_outbound_burst"="500000" --property "quota:vif_outbound_average"="250000" gp.0.2.4
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 6144 --vcpu 2 --disk 40 --ephemeral 0 --swap 1024 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="500000" --property "quota:vif_inbound_burst"="500000" --property "quota:vif_inbound_average"="312500" --property "quota:vif_outbound_peak"="500000" --property "quota:vif_outbound_burst"="500000" --property "quota:vif_outbound_average"="312500" gp.0.2.6
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 8192 --vcpu 2 --disk 40 --ephemeral 0 --swap 1024 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="750000" --property "quota:vif_inbound_burst"="750000" --property "quota:vif_inbound_average"="375000" --property "quota:vif_outbound_peak"="750000" --property "quota:vif_outbound_burst"="750000" --property "quota:vif_outbound_average"="375000" gp.0.2.8
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 4096 --vcpu 4 --disk 80 --ephemeral 64 --swap 4096 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="500000" --property "quota:vif_inbound_burst"="500000" --property "quota:vif_inbound_average"="250000" --property "quota:vif_outbound_peak"="500000" --property "quota:vif_outbound_burst"="500000" --property "quota:vif_outbound_average"="250000" gp.0.4.4
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 8192 --vcpu 4 --disk 80 --ephemeral 64 --swap 4096 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="750000" --property "quota:vif_inbound_burst"="750000" --property "quota:vif_inbound_average"="375000" --property "quota:vif_outbound_peak"="750000" --property "quota:vif_outbound_burst"="750000" --property "quota:vif_outbound_average"="375000" gp.0.4.8
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 12288 --vcpu 4 --disk 80 --ephemeral 64 --swap 4096 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="750000" --property "quota:vif_inbound_burst"="750000" --property "quota:vif_inbound_average"="437500" --property "quota:vif_outbound_peak"="750000" --property "quota:vif_outbound_burst"="750000" --property "quota:vif_outbound_average"="437500" gp.0.4.12
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 16384 --vcpu 4 --disk 80 --ephemeral 64 --swap 4096 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1000000" --property "quota:vif_inbound_burst"="1000000" --property "quota:vif_inbound_average"="500000" --property "quota:vif_outbound_peak"="1000000" --property "quota:vif_outbound_burst"="1000000" --property "quota:vif_outbound_average"="500000" gp.0.4.16
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 16384 --vcpu 8 --disk 160 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1000000" --property "quota:vif_inbound_burst"="1000000" --property "quota:vif_inbound_average"="500000" --property "quota:vif_outbound_peak"="1000000" --property "quota:vif_outbound_burst"="1000000" --property "quota:vif_outbound_average"="500000" gp.0.8.16
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 24576 --vcpu 8 --disk 160 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="687500" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="687500" gp.0.8.24
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 32768 --vcpu 8 --disk 160 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="750000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="750000" gp.0.8.32
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 65536 --vcpu 16 --disk 240 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="875000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="875000" gp.0.16.64
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 98304 --vcpu 24 --disk 240 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="937500" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="937500" gp.0.24.96
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 131072 --vcpu 32 --disk 240 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="1000000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="1000000" gp.0.32.128
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 196608 --vcpu 48 --disk 240 --ephemeral 128 --swap 8192 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=general_purpose" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="1062500" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="1062500" gp.0.48.192
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 12288 --vcpu 2 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="750000" --property "quota:vif_inbound_burst"="750000" --property "quota:vif_inbound_average"="437500" --property "quota:vif_outbound_peak"="750000" --property "quota:vif_outbound_burst"="750000" --property "quota:vif_outbound_average"="437500" mo.0.2.12
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 16384 --vcpu 2 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1000000" --property "quota:vif_inbound_burst"="1000000" --property "quota:vif_inbound_average"="500000" --property "quota:vif_outbound_peak"="1000000" --property "quota:vif_outbound_burst"="1000000" --property "quota:vif_outbound_average"="500000" mo.0.2.16
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 20480 --vcpu 4 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="625000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="625000" mo.0.4.20
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 24576 --vcpu 4 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="687500" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="687500" mo.0.4.24
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 32768 --vcpu 4 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="750000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="750000" mo.0.4.32
    openstack --os-cloud default flavor create --description "Useful Information for users" --ram 65536 --vcpu 8 --disk 80 --ephemeral 0 --swap 0 --property "hw:mem_page_size=any" --property "hw:cpu_max_threads=1" --property "hw:cpu_max_sockets=2" --property ":category=memory_optimized" --property ":architecture=x86_architecture" --property "quota:vif_inbound_peak"="1250000" --property "quota:vif_inbound_burst"="1250000" --property "quota:vif_inbound_average"="875000" --property "quota:vif_outbound_peak"="1250000" --property "quota:vif_outbound_burst"="1250000" --property "quota:vif_outbound_average"="875000" mo.0.8.64
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

### Example: Network Bandwidth Limits

This example configures a flavor to use network traffic bandwidth limits for outbound and inbound traffic

``` shell
openstack --os-cloud default flavor create gp.0.8.24 \
          --public \
          --ram 24576 \
          --disk 160 \
          --vcpus 8 \
          --ephemeral 128 \
          --swap 8192
```

Now, set the following properties: `vif_inbound_average`, `vif_inbound_burst`, `vif_inbound_peak`, `vif_outbound_average`, `vif_outbound_burst`, and `vif_outbound_peak`. These values define the respective limits for network traffic. The speed limits are specified in kilobytes per second (kB/s), while the burst values are also specified in kilobytes.

```shell
openstack --os-cloud default flavor set gp.0.8.24 \
    --property "quota:vif_inbound_peak"="1250000" \
    --property "quota:vif_inbound_burst"="1250000" \
    --property "quota:vif_inbound_average"="687500" \
    --property "quota:vif_outbound_peak"="1250000" \
    --property "quota:vif_outbound_burst"="1250000" \
    --property "quota:vif_outbound_average"="687500"
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
          --property pci_passthrough:alias=p2000:1 \
          --property hw:hide_hypervisor_id='true'
```

!!! note

    The `pci_passthrough` property assumes that the **p2000** alias has been set up on your compute node. Review the [service-specific overrides](openstack-service-overrides.md) setup for more on custom compute configurations and refer to the [Genestack documentation](openstack-pci-passthrough.md) on leveraging passthrough devices.

!!! note

    The `hw:hide_hypervisor_id` will hide the Hypervisor ID from an instances. This useful in a lot of environments, see the [upstream documentation](https://bugs.launchpad.net/nova/+bug/1841932) for more information.

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
