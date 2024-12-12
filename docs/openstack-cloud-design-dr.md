# Disaster Recovery for OpenStack Clouds

## Introduction

When designing and deploying clouds using OpenStack, Disaster Recovery (DR) needs to be forefront in your mind. DR needs to be a part of the design and architecture from the start.  Disasters can strike in various forms, ranging from the failure of a single node to a complete site outage.  While built-in redundancy measures are essential for maintaining the resilience of production-scale OpenStack environments, the effectiveness of the recovery process largely depends on careful planning and a well-defined approach.

## Understanding Disaster Scenarios and  Potential Risks

OpenStack environments are susceptible to a wide array of failure scenarios, each presenting unique challenges and potential risks to the cloud's stability and performance. Depending on the level where the failure occurs, it may be able to be easily mitigated due to redundancy and/or recovery processes, or it may lead to a more serious outage that requires unplanned maintenance.

By gaining a thorough understanding of these scenarios, you can better prepare for and mitigate the impact of such failures on your OpenStack clouds. Some of the layers where most common disaster scenarios include:

### Service Failures

Service failures are when a particular OpenStack service (or supporting service[^1]) becomes unavailable.  These are often attributed to software issues, operating system bugs, or failed OpenStack upgrades. These failures can affect critical cloud services such as Cinder, Nova, Neutron, or Keystone. The impact on instances varies depending on the affected service, with potential consequences ranging from deployment failures to service interruptions.

### Controller Node Failures

Hardware failures can lead to the complete outage of a Controller Node, whether virtual or physical. While Controller Node failures may not directly impact running instances and their data plane traffic, they can disrupt administrative tasks performed through the OpenStack agent. Additionally, the loss of the database hosted on the failed controller can result in the permanent loss of instance or service information.

!!! Note
    This is a different scenario than a Control Plane Failure.  The impact of the failure of a Controller Node will usually be mitigated through Controller Node redundancy in the control plane.  As long as there is no data corruption, service should be uninterrupted during recovery.

### Compute Node Failures

Compute Node failures are the most prevalent issue in OpenStack clouds – mostly because Compute Nodes make up the majority of the cloud, by node type population.  Compute Node failures are often caused by hardware failures, whether disk, RAM, or other hardware failure. The primary risk associated with compute node failures is the potential loss of instances and their disk data if they are using local storage.

!!! Info
    This risk is not unique to OpenStack.  Any cloud (or any compute environment at all) where storage is co-located with compute[^2] has this risk.

### Network Failures

Network failures can stem from various sources, including faulty SFP connectors, cables, NIC issues, or switch failures. These failures can impact both the data and control planes. Data plane NIC failures directly affect the instances using those NICs, while control-plane network failures can disrupt pending tasks such as reboots, migrations, and evacuations.

The easiest way to account for this is to build redundancy at every level of your network:

- **Redundant NICs** for each host → switch connectivity
- **Redundant Connections (e.g. LACP)** for each host → switch connectivity
- **Redundant Top-of-Rack (ToR) or Leaf Switches** for host → switch connectivity
- **Redundant Aggregation or Spine Switches** for switch → switch connectivity

Having this level of redundancy won't eliminate failures, but it can massively limit or even eliminate service outage at a given level of your network, at least until maintenance can replace the affected hardware.

### Instance Failures

OpenStack instances, whether standalone or part of an application node, are prone to failures caused by human errors, host disk failures, power outages, and other issues. Instance failures can result in data loss, instance downtime, and instance deletion, often requiring redeployment of the affected instance or even the entire application stack that instance is part of.

By recognizing and preparing for these potential disaster scenarios, organizations can develop comprehensive disaster recovery strategies that minimize the impact of such events on their OpenStack environments, ensuring greater system resilience and minimizing downtime.

## Ensuring Controller Redundancy in OpenStack

One of the fundamental design considerations in OpenStack is the implementation of a cluster with multiple controllers. A minimum of three controllers is typically deployed to maintain quorum and ensure system consistency in the event of a single server failure. By distributing services across multiple controllers, organizations can enhance the resilience and fault tolerance of their OpenStack environment.

### Controller Deployment Strategies

There are several standard practices for managing controller redundancy in OpenStack:

- **Bare Metal with Containerized Services:** In this approach, each service is hosted in a container on separate bare metal servers. For example, the nova-scheduler service might run on one server, while the keystone service runs on another. This strategy provides isolation between services, potentially enhancing security and simplifying troubleshooting. This is the approach that [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/latest/){:target="_blank"} and [Kolla-Ansible](https://docs.openstack.org/kolla-ansible/latest/){:target="_blank"} take.

- **Replicated Control Plane Services:** All control plane services are hosted together on each of the three or more servers. This replication of services across multiple servers simplifies deployment and management, as each server can be treated as a self-contained unit. In the event of a server failure, the remaining servers in the cluster continue to provide the necessary services, ensuring minimal disruption. This _hyperconverged_ approach is good for smaller OpenStack deployments, but starts to become problematic as the cluster scales. This is another approach that [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/latest/){:target="_blank"} takes, and one that Rackspace is currently using for on-prem OpenStack deployments.

- **Kubernetes-Managed Containerized Workloads:** Kubernetes can be used to manage the OpenStack control plane services as containerized workloads. This approach enables easier scaling of individual services based on demand while offering self-healing mechanisms to automatically recover from failures.  _This is the approach taken by [Genestack](deployment-guide-welcome.md)._

### Load Balancing and High Availability

To ensure high availability and distribute traffic among controller nodes, load balancers such as HAProxy or NGINX are commonly used for most OpenStack web services. In addition, tools like Pacemaker can be employed to provide powerful features such as service high availability, migrating services in case of failures, and ensuring redundancy for the control plane services.

Most deployment tooling currently achieves this via two patterns:

- **Having multiple Controller Nodes:** This is what OpenStack-Ansible and Kolla-Ansible do today.  They have multiple nodes and fail-over services individually when there is a problem and with service workload balancing for some services.  Usually, this is implemented using a software load balancer like [HAProxy](https://www.haproxy.org/){:target="_blank"} or with hardware load balancers.

- **Using a microservices-based approach:** _This is the approach that Genestack takes by deploying the OpenStack services inside of Kubernetes._  Kubernetes provides, autoscaling, load balancing, and failover capabilities for all of the OpenStack services.

### Database and Message Queue Redundancy

Special consideration must be given to mission-critical services like databases and message queues to ensure high availability.

[MariaDB](https://mariadb.org/){:target="_blank"} or [MySQL](https://dev.mysql.com/community/){:target="_blank"} are the standard databases for OpenStack.  To have redundancy, [Galera](https://galeracluster.com/){:target="_blank"} clustering can be used to provide multi-read/write capabilities. Regular database backups should be maintained and transferred to multiple locations outside the cluster for emergency cases.

Message queues  should be configured in a distributed mode for redundancy. The most common message queue used for OpenStack is [RabbitMQ](https://www.rabbitmq.com/){:target="_blank"}, which has [various](https://www.rabbitmq.com/docs/reliability){:target="_blank"} capabilities that can be implemented to provide reliability and redundancy.

In some cases, with larger deployments, services might have to be separated and deployed in their own dedicated infrastructures.  The OpenStack [Large Scale SIG](https://docs.openstack.org/large-scale/index.html){:target="_blank"} provides documentation on various scaling techniques for the various OpenStack services, as well as guidance around when it is appropriate to isolate a service or to scale it independently of other services.

### Controller Redeployment and Backup Strategies

To facilitate rapid redeployment of controllers in the event of a disaster, organizations should maintain backups of the base images used to deploy the controllers. These images should include the necessary packages and libraries for the basic functionality of the controllers.

The backup strategy for Controller Nodes should consist of periodic snapshots of the controllers.  These should be taken and transferred to safe locations to enable quick recovery without losing critical information or spending excessive time restoring backups.

!!! Warning
    You must backup _all_ controller nodes at the same time.  Having "state skew" between the controllers has the potential to render the entire OpenStack deployment inoperable. Additionally, if you need to restore the control plane from a backup, it has the potential to differ from what is _currently running_ in terms of instances, networks, storage allocation, etc.

Implementing robust controller redundancy strategies can enable you to significantly enhance the resilience and fault tolerance of your OpenStack deployment, minimizing the impact of controller failures, and ensuring the smooth operation of their cloud infrastructure.

## Achieving Compute Node Redundancy in OpenStack

Compute nodes are the workhorses of an OpenStack environment, hosting the instances that run various applications and services. To ensure the resilience and availability of these instances, it is crucial to design compute node redundancy strategies that can effectively handle failures and minimize downtime.

Implementing a well-designed Compute Node redundancy strategy will enable you to significantly enhance the resilience and availability of OpenStack instances, minimize user downtime, and ensure the smooth operation of the cloud-based applications and services your users deploy.

### Capacity Planning and Spare Nodes

When designing compute node redundancy, it is essential to consider the capacity of the overcloud compute nodes and the criticality of the instances running on them.

!!! Tip
    A best practice is to always maintain at least one spare compute node to accommodate the evacuation of instances from a node that has failed or that requires maintenance. This is often referred to as the _**N+1**_ strategy.

If multiple compute node groups have different capabilities, such as CPU architectures, SR-IOV, or DPDK, the redundancy design must be more granular to address the specific requirements of each component.

### Host Aggregates and Availability Zones

To effectively manage compute node redundancy, subdivide your nodes into multiple [Host Aggregates (HAs)](openstack-cloud-design-ha.md) and assign one or more spare compute nodes with the same capabilities and resources to each aggregate. These spare nodes must be kept free of load to ensure they can accommodate instances from a failed compute node. WHen you are creating [Availability Zones (AZs)](openstack-cloud-design-az.md) from host aggregates, you allow users to select where their instances are deployed based on their requirements. If a Compute Node fails within an AZ, the instances can be seamlessly evacuated to the spare node(s) within the same AZ. This minimizes disruptions and maintains service continuity.

!!! Tip
    You will want to implement _**N+1**_ for all Host Aggregates and Availability Zones so that each group of compute resources has some redundancy and spare capacity.

### Fencing Mechanism and Instance High-Availability Policies

For mission-critical deployed services that cannot tolerate any downtime due to compute node failures, implementing fencing mechanisms and instance high-availability (HA) policies can further mitigate the impact of such failures.

!!! Info
    OpenStack provides the [Masakari](https://docs.openstack.org/masakari/latest/){:target="_blank"} project to provide Instance High Availability.

Defining specific High Availability (HA) policies for instances enables you to determine the actions to be taken if the underlying host goes down, or the instance crashes. For example, for instances that cannot tolerate downtime, the applicable HA policy in Masakari is "ha-offline," which triggers the evacuation of the instance to another compute node (the spare node.) To enable this functionality, the fencing agent must be enabled in Nova.

Masakari is a great feature, but imposes architectural requirements and limitations that can be at odds with providing a large-scale OpenStack cloud. You may want to consider limiting your cloud to have a smaller-scale "High Availability" Host Aggregate or Availability Zone to limit the architecture impact (as well as the associated costs) of providing this feature.

### Monitoring and Automated Recovery

Continuously monitor the health and status of compute nodes to quickly detect and respond to failures. Having automated recovery mechanisms that can trigger the evacuation of instances from a failed node to a spare node based on predefined policies and thresholds, is one way to cut down on service emergencies. This automation ensures rapid recovery and minimizes the need for manual intervention, reducing the overall impact of compute node failures on the OpenStack environment.  Like with all automation, it can be a delicate balance of risk and reward, so _test everything_ and make sure the added complexity doesn't increase the administrative burden instead of cutting it down.

[^1]: e.g. MySQL/MariaDB, RabbitMQ, etc.
[^2]: There are various hyperconverged architectures that attempt to mitigate this, however co-locating storage with compute via hyperconvergence means that failure of a Compute Node _also_ is failure of a Storage Node, so now you are dealing with _multiple_ failure types.
