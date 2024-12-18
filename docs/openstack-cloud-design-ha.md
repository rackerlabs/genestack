# Host Aggregates

[Host Aggregates](https://docs.openstack.org/nova/latest/admin/aggregates.html){:target="_blank"}  are a way of grouping hosts in an OpenStack cloud.  This allows you to create groups of certain types of hosts and then steer certain classes of VM instances to them.

Host Aggregates[^1] are a mechanism for partitioning hosts in an OpenStack cloud, or a [Region](openstack-cloud-design-regions.md) of an OpenStack cloud, based on arbitrary characteristics. Examples where an administrator may want to do this include where a group of hosts have additional hardware or performance characteristics.

![Host Aggregates](assets/images/Host-Aggregates.png)

Each node can have multiple aggregates, each aggregate can have multiple key-value pairs, and the same key-value pair can be assigned to multiple aggregates. This information can be used in the scheduler to enable advanced scheduling or to define logical groups for migration.  In general, Host Aggregates can be thought of as a way to segregate compute resources _behind the scenes_ to control and influence where VM instances will be placed.

## Host Aggregates in Nova

Host aggregates are not explicitly exposed to users. Instead administrators map flavors to host aggregates. Administrators do this by setting metadata on a host aggregate, and setting matching flavor extra specifications. The scheduler then endeavors to match user requests for instances of the given flavor to a host aggregate with the same key-value pair in its metadata. Hosts can belong to multiple Host Aggregates, depending on the attributes being used to define the aggregate.

A common use case for host aggregates is when you want to support scheduling instances to a subset of compute hosts because they have a specific capability. For example, you may want to allow users to request compute hosts that have NVMe drives if they need access to faster disk I/O, or access to compute hosts that have GPU cards to take advantage of GPU-accelerated code. Examples include:

- Hosts with GPU compute resources
- Hosts with different local storage capabilities (e.g. SSD vs NVMe)
- Different CPU manufacturers (e.g. AMD vs Intel)
- Different CPU microarchitectures (e.g. Skylake vs Raptor Cove)

![Multiple Host Aggregates](assets/images/Multiple-Host-Aggregates.png)

### Host Aggregates vs. Availability Zones

While Host Aggregates themselves are hidden from OpenStack cloud users, Cloud administrators are able to optionally expose a host aggregate as an [Availability Zone](openstack-cloud-design-az.md). Availability zones differ from host aggregates in that they are explicitly exposed to the user, and hosts membership is exclusive -- hosts can only be in a single availability zone.

!!! Warning
    It is not allowed to move instances between Availability Zones. If adding a host to an aggregate or removing a host from an aggregate would cause an instance to move between Availability Zones (including moving from or moving to the default AZ) then the operation will be fail.

### Host Aggregates in Genestack

!!! Genestack
    Genestack is designed to use [Host Aggregates](openstack-host-aggregates.md) to take advantage of various compute host types.

## Aggregates and Placement

The [Placement](https://docs.openstack.org/placement/latest/){:target="_blank"} service also has a concept of [Aggregates](https://specs.openstack.org/openstack/nova-specs/specs/rocky/implemented/alloc-candidates-member-of.html).  However, these are not the same thing as Host Aggregates in Nova. Placement Aggregates are defined purely as groupings of related resource providers. As compute nodes in Nova are represented in Placement as resource providers, they can be added to a Placement Aggregate as well.

## Host Aggregates and Glance

The primary way that Glance can influence placement and work with Host Aggregates is via [Metadata](https://docs.openstack.org/glance/latest/user/metadefs-concepts.html){:target="_blank"}.

You can map flavors and images to Host Aggregates by setting metadata on the Host Aggregate, and then set Glance image metadata properties to correlate to the host aggregate metadata. Placement can then use this metadata to schedule instances when the required filters are enabled.

!!! Note
    Metadata that you specify in a Host Aggregate limits the use of that host to any instance that has the same metadata specified in its flavor or image.

[^1]: Host aggregates started out as a way to use Xen hypervisor resource pools, but have since been generalized to provide a mechanism to allow administrators to assign key-value pairs to groups of machines.
