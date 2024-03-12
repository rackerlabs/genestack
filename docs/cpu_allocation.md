
#CPU allocation Guide

By default openstack helm provide cpu allocation of 3:1. For a production deployment, cpu allocation ratio need to be decided based on multiple factors like  hardware configuration of compute node (number of CPU core available ), required  performance of workload, goal of efficient usage of available resource etc. 
We are using  HPE DL380 Gen9 Servers with 2 CPU socket and 18 cores per CPU socket and 2 threads per core to get cpu allocation for our deployment. We are considering below two cases here


Case 1 : CPU allocation ratio for shared CPU  

Type of workload :  Whether workload is CPU intensive or not? if yes, then you need  to decide number of cpu cores for such workload. Create flavor according to workload cpu requirement.

Number of VM per host: An forecast of number of VM per compute to be hosted with given flavor.

Number  of CPU on Host: Number of cores available on the compute node.

Example :

Here we have HPE DL380 Gen9 Servers with 2 CPU socket and 18 cores per CPU socket and 2 threads per core: 

Total physical CPU (PCPU) = 72

No. of vCPU per flavor (VCPU)  = 8

No. of Instance per hypervisor (VM) = 100

Formula to calculate CPU allocation ratio (CAR) = VM * VCPU / PCPU

          CAR = 100 * 8 / 72
                  = 800/72
                  = ~11/1

So here we get approx CPU allocation ratio of 11:1.

 

Case 2: Shared workload with CPU pining: 

There may be requirement to run CPU pinned VM along with floating instances (shared cpus). In such case CPU allocation for  compute node will be different from rest of nodes. Lets see how to get cpu allocation for such type of compute nodes:

Example :

No. of CPU dedicated for CPU pinning (RCPUP) : 16

CPU allocation ratio:   CAR = VM * VCPU / (PCPU - RCPUP)

CAR = 100 * 8 / (72 - 16)
    = 800/56
    = ~14/1

So, here cpu allocation will be 14:1 on host hosting cpu pinned instances and floating instances.
