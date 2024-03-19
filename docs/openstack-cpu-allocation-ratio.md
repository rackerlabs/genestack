# Nova CPU allocation Guide

By default openstack helm provide cpu allocation of 3:1. For a production deployment, cpu allocation ratio need to be decided based on multiple factors like:

1. Workload type: Different workloads have different CPU utilization patterens. For example, web servers might have bursty utilization, while database might have more consistent.
2. Peformance Requirments: Consider the performace requirment of the workloads. Some applications may require dedicated CPU resource to meet required performace SLA, whereas other can share resources.
3. Overhead: Account for the overhead introduced by the operating system, hypervidor and virtulization layer. Sometime compute node are used as hyperconserved nodes as well. This can impact the effective allocation ratio.
4. Peak vs Average Usage: Determin whether to set allocation ratios based on peak or average CPU usage. Peak usages ensure there are enough resources available durig period of high demand, but it may result in underutilization during off-peak hours.
5. Growth and Scalability: Consider future growth and scalability needs when setting CPU allocation ratios. Allocating too liberally may result in wasted resources while allocating too conservatively may lead to resource shortage as the deployment scale.

Lets consider below two use case to calculate CPU allocation for our deployment with HPE DL380 Server.

### Case 1: CPU allocation ratio for shared CPU

Workload type: Considering a flavor with 8 vCPU for workload which will meet its peak demand and required performace.

Max VM per host: Considering max of 60 VM of such flavor can be hosted on a single hypervisor as per our scaling/growth forcast.

CPUs on hypervisor: HPE DL380 have 72 PCPU.


Example :
``` shell
  Total physical CPU (PCPU) = 72
  No. of vCPU per flavor (VCPU)  = 8
  No. of Instance per hypervisor (VM) = 60
  Overhead on CPU (OCPU) = 8
  Formula to calculate CPU allocation ratio:

   CAR = VM * VCPU / (PCPU - OPCU)
   CAR = 60 * 8 / (72 - 8)
       = 480/64
       = ~8
```
So here we get approx CPU allocation ratio of 8.1.

### Case 2: Shared workload with CPU pining:

There may be requirement to run CPU pinned VM along with floating instances (shared cpus). In such case CPU allocation for  compute node will be different from rest of nodes. Lets see how to get cpu allocation for such type of compute nodes:

Example :
``` shell
  No. of CPU dedicated for CPU pinning (RCPUP) : 16
  CPU allocation ratio:

  CAR = VM * VCPU / (PCPU - RCPUP - OCPU)
  CAR = 60 * 8 / (72 - 16 - 8)
      = 480/48
      = 10
```
So, here cpu allocation will be 10.1 on host hosting cpu pinned instances and floating instances.

Please note , above is  an example only. For your use case it is required to considering flavor's CPU specifications based on application benchmark requirments, its peak utilization and scaling needs of future.
