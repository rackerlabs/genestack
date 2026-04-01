# Masakari Host-Monitor

## Overview
The Host-Monitor is a component of OpenStack Masakari, which provides VM High Availability (VMHA). Its job is to detect failures of compute hosts (hypervisors) and trigger recovery actions for the VMs running on them.

With this feature when a hypervisor failure has been detected by the other Hypervisor nodes, Masakari will initiate a recovery workflow to evacuate VM's to another available host, depending on the 'Segment' host recovery strategy.

## Basic Flow

Compute host fails
       ↓
masakari-hostmonitor detects failure
       ↓
Notification sent to masakari-api
       ↓
masakari-engine processes it
       ↓
Nova evacuates VMs to another host


## Kubernetes driver
Used when OpenStack runs on Kubernetes.

The monitor queries the Kubernetes API to check node status.


## Evacuation Strategies

* auto - evacuate all the VMs with no destination node for nova scheduler.
* rh_priority - evacuate all the VMs by using reserved-host recovery method firstly. If failed, then using auto recovery method.
* reserved_host - evacuate all the VMs with reserved hosts as the destination nodes for nova scheduler.
* auto_priority - evacuate all the VMs by using auto recovery method firstly. If failed, then using reserved-host recovery method.

## Limitations
* Any VMs with host evacuation capability will need to be using a “shared storage” disk or VM will fail to evacuate and recover.
* Instance recovery might cause VM to go to error state if VM doesn’t have proper resources on the new host, having designated failover segments is suggested.

## Setup of Masakari Host Segments

Setting up a Masakari segment and adding hosts (for OpenStack instance HA auto-recovery) involves a few clear steps using the openstack CLI

```bash
openstack segment create <SEGMENT_NAME> \
  --recovery-method auto \
  --service-type COMPUTE
```

### Segment fields explained:
--recovery-method auto → enables automatic VM recovery
--service-type COMPUTE → for Nova compute nodes

## Add Hosts to the Segment

```bash
openstack segment host create <SEGMENT_NAME> <HOSTNAME> \
  --type COMPUTE \
  --control-attributes ssh
```

### Parameters:
<HOSTNAME> → must match Nova compute hostname
--type COMPUTE → for compute nodes
--control-attributes ssh → Masakari uses SSH fencing (common setup)

## Verify

```bash
openstack segment host list <SEGMENT_NAME>
```

## Skyline Dashboard
An Openstack Administrator has the ability to manage segments and hosts via the (Instance HA) tab in the Administrator dashboard view
