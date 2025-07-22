# Purpose

This page contains various troubleshooting tasks.

## Find node for an instance

You might want to check that the node has the required pods running, or do other
troubleshooting tasks.

This will tell you what node an instance runs on.

``` shell
openstack server show ${INSTANCE_UUID} -c hypervisor_hostname
```

## Kube-OVN kubectl plugin

- Kube-OVN has a `kubectl` plugin.
- You can see documentation at [the Kube-OVN documentation](https://kubeovn.github.io/docs/v1.13.x/en/)
- You should install it from wherever you would like to use `kubectl` from, as described
      [here](https://kubeovn.github.io/docs/v1.13.x/en/ops/kubectl-ko/#plugin-installation)
  - However, you will also find it already on installed on _Genestack_ Kubernetes
      nodes, so you can use it with `kubectl` there, if desired.
- You can use this to run many OVS commands for a particular node
  - if, for instance, you've found a node for a particular instances as
      discussed above

You can get help like:

``` shell
kubectl ko help
```

``` shell
kubectl ko {subcommand} [option...]
Available Subcommands:
  [nb|sb] [status|kick|backup|dbstatus|restore]     ovn-db operations show cluster status, kick stale server, backup database, get db consistency status or restore ovn nb db when met 'inconsistent data' error
  nbctl [ovn-nbctl options ...]    invoke ovn-nbctl
  sbctl [ovn-sbctl options ...]    invoke ovn-sbctl
  vsctl {nodeName} [ovs-vsctl options ...]   invoke ovs-vsctl on the specified node
  ofctl {nodeName} [ovs-ofctl options ...]   invoke ovs-ofctl on the specified node
  dpctl {nodeName} [ovs-dpctl options ...]   invoke ovs-dpctl on the specified node
  appctl {nodeName} [ovs-appctl options ...]   invoke ovs-appctl on the specified node
  tcpdump {namespace/podname} [tcpdump options ...]     capture pod traffic
  trace ...    trace ovn microflow of specific packet
    trace {namespace/podname} {target ip address} [target mac address] {icmp|tcp|udp} [target tcp/udp port]    trace ICMP/TCP/UDP
    trace {namespace/podname} {target ip address} [target mac address] arp {request|reply}                     trace ARP request/reply
  diagnose {all|node} [nodename]    diagnose connectivity of all nodes or a specific node
  env-check    check the environment configuration
  tuning {install-fastpath|local-install-fastpath|remove-fastpath|install-stt|local-install-stt|remove-stt} {centos7|centos8}} [kernel-devel-version]    deploy kernel optimisation components to the system
  reload    restart all kube-ovn components
```

For instance,

```shell
kubectl ko vsctl ${K8S_NODE_NAME} show
```

works as if had ran `ovs-vsctl show` when logged into the `ovs-ovn` or
    `kube-ovn-cni` pod for the specified node.

Usefully, you can check the status of the NB and SB:

```shell
kubectl ko nb status
kubectl ko sb status
```

and check `dbstatus`:

```shell
kubectl ko nb dbstatus
```

See the full documentation for more details, for _Kube-OVN_, OVN, and OVS,
as applicable.

## List all pods on a node

- You may want to list all pods on a node. You may have found an instance above
  and now want to check the pods on the host.
  - you can use `kubectl ko` to run OVS commands for particular nodes as
        described above without identifying the node for a pod manually as
        described here.
- This will show all pods running on a given _Kubernetes_ node.
- You can use this to see if a node has all of the pods it should running,
  or to see their status, or find them to check their logs.
- As described in the "Introduction and Overview" page, you find several pods
  on a node relevant to operation of OVN, OVS, and Neutron, like:
  - `kube-ovn-cni`
  - `kube-ovn-pinger`
  - `ovs-ovn`
  - `neutron-ovn-metadata-agent-default`
    - this one only runs on compute nodes
  - other pods that run on all nodes or all computes not directly to OVN.
    - (e.g., `kube-proxy`, and several others.)

You can use a command like:

```shell
kubectl get pods --all-namespaces --field-selector spec.nodeName=${NODE}
```

where you can use a value found from following steps like those outlined in
"Find node for an instance" to see what node you wanted to list the pods for,
and use that instead of `$node`, if, for instance, you wanted to check on the
node that has a particular instance.

## Finding OVN and OVS pods

- In addition to the list of pods on each node for OVS and OVN operation,
  _Kube-OVN_ has several centralized pods, which all run in the `kube-system`
  namespace, that you should ensure as running normally
  when troubleshooting:
  - `ovn-central` pods
  - `kube-ovn-controller` pods
  - `kube-ovn-monitor` pods
    - although this only collects metrics, so may not adversely affect
          normal operation
- You may want to find the OVS and OVN pods to use commands on or
  in them.
  - but, as noted above, you can often use `kubectl ko` to execute
      relevant commands for a particular node without manually identifying
      it as show here, and it seems less confusing to stick with running OVS
      and OVN commands that way.
    - additionally, note that OVS appears the same from the Kubernetes
          node itself, `ovs-ovn` pods, and `kube-ovn-cni` pods, but the
          Kubernetes nodes themselves don't have the OVS and OVN commands,
          while the pods do.
      - (e.g., same process IDs, same UUID identifiers. OVS runs on the
               Kubernetes nodes without a pod, but appears visible in
               certain pods.)
- Nodes have OVS pods as indicated above in the "List all pods on a node"
  section
  - only compute nodes have `neutron-ovn-metadata-agent` pods, but you should
      find `kube-ovn-cni`, `kube-ovn-pinger`, and `ovs-ovn` on all nodes.
- _Kube-OVN_ has some central pods that don't run per node:
  - You can find these all in the `kube-system` namespace
  - ovn-central
    - these have the NB and SB DB and _ovn-northd_ as described in
          the "Introduction and Overview" page.
  - kube-ovn-controller
    - acts as control plane for _Kube-OVN_
  - kube-ovn-monitor
    - collects OVN status information and the monitoring metrics
- You can list pods for a node as shown above in "List all pods on a node".

You can list OVN-central pods like:

```shell
kubectl -n kube-system get pod -l app=ovn-central
```

## Getting a shell or running commands on the OVS/OVN pods

- As mentioned, you will probably find it easier to use `kubectl ko` to run
  OVS and OVN commands instead of finding pods.
  - For some rare cases, you may wish to do something like run `ovsdb-client`
      to dump the OVSDB (although or do some other thing not supported directly from
      `kubectl ko`.
- You may want to check the status of OVS or OVN pods for a node found by
  following steps like "Find node for an instance" and "List all pods on a
  node" above, if you have networking trouble with an instance
  - to see if it has all necessary pods running, or check logs for a pod
- Within the `ovs-ovn` and `kube-ovn-cni` pods for a node, you can use OVS
  commands if needed.

You can get a shell in the `ovs-ovn` pod like:

``` shell
kubectl -n kube-system exec -it ovs-ovn-XXXXX -- /bin/bash
```

You will probably have 5 lower case letters in place of `XXXXX` because each
node has a copy of this pod. You may also have used an OVN central pod instead
of an `ovs-ovn-XXXXX` pod.

Additionally, while mostly not shown here, many OVS commands can and do
simply return results, so you might not want or need to spawn an interactive
shell as above. As an example:

``` shell
kubectl -n kube-system exec -it ovs-ovn-XXXX -- ovs-vsctl list manager
```

gives you the output just like you would get if you executed it from an
interactive shell.

You can find all OVS and OVN commands from bin directories in the pod like this:

``` shell
dpkg -l | perl -lane '$package=$F[1];
  next unless /ovn/ or /openv/;
  chomp(@FILES = `dpkg -L $package`);
  for (@FILES) {
     next unless /bin/;
    -f and print
  }'
```

These rarely change, so the list produced will look similar to this:

``` shell
/usr/bin/ovs-appctl
/usr/bin/ovs-docker
/usr/bin/ovs-ofctl
/usr/bin/ovs-parse-backtrace
/usr/bin/ovs-pki
/usr/bin/ovsdb-client
/usr/sbin/ovs-bugtool
/usr/bin/ovs-dpctl
/usr/bin/ovs-dpctl-top
/usr/bin/ovs-pcap
/usr/bin/ovs-tcpdump
/usr/bin/ovs-tcpundump
/usr/bin/ovs-vlan-test
/usr/bin/ovs-vsctl
/usr/bin/ovsdb-tool
/usr/sbin/ovs-vswitchd
/usr/sbin/ovsdb-server
/usr/bin/ovn-ic
/usr/bin/ovn-northd
/usr/bin/ovn-appctl
/usr/bin/ovn-ic-nbctl
/usr/bin/ovn-ic-sbctl
/usr/bin/ovn-nbctl
/usr/bin/ovn-sbctl
/usr/bin/ovn-trace
/usr/bin/ovn_detrace.py
/usr/bin/ovn-controller
```

- Different commands work in different pods
  - You can expect `ovs-{app,of,vs}ctl` to work in `ovs-ovn` pods, but not
      `ovn-*` commands, mostly. Similarly, in `ovn-central` pods, some `ovn-*`
      commands will work, but OVS commands probably won't.

full usage of these goes beyond the scope of this page. However, you can find
more information:

- You can read the [OVS manual pages online](https://docs.openvswitch.org/en/latest/ref/#man-pages)
- You can read the
  [OVN manual pages online](https://docs.ovn.org/en/latest/ref/index.html)

## Run ovs-vsctl list manager

For an OVS pod, you can check that it has a manager connection. Nodes
should have an OVS manager connection for normal operation.

```shell
kubectl ko vsctl ${NODE} list manager
```

``` yaml
_uuid               : 43c682c2-a6c3-493f-9f6c-079ca55a5aa8
connection_mode     : []
external_ids        : {}
inactivity_probe    : []
is_connected        : true
max_backoff         : []
other_config        : {}
status              : {bound_port="6640", n_connections="2", sec_since_connect="0", sec_since_disconnect="0"}
target              : "ptcp:6640:127.0.0.1"
```

## Run ovs-vsctl show

This shows various useful output, such as ports on the bridges, including:

- `br-int`, which has the tap devices (instance network interfaces)
- `br-ext`, usually for the public Internet

``` shell
kubectl ko vsctl ${NODE} show
```

As an aside, you can just list the bridges without the more verbose output
of `ovs-vsctl show`:

``` shell
kubectl ko vsctl ${NODE} list-br
```

You will probably have a `br-int` for things like instance tap devices, and
`br-ex` for a public Internet connection, but the names could vary depending on
how you installed _Genestack_.

## Find the tap devices for an instance

KVM creates tap devices for the instance NICs. You might want to identify the
tap device on the correct bridge from the output of `ovs-vsctl show` described
above. In that case, you need to find the name of the tap device and which
Kubernetes node you can find it on. You can also `tcpdump` the interface from
the Kubernetes node when you find it this way.

This shows you the instance name as used by KVM, which does not match the nova
UUID, and the Kubernetes node as the hypervisor hostname:

``` shell
openstack server show ${UUID} -c OS-EXT-SRV-ATTR:instance_name -c hypervisor_hostname -f json
```

Thereafter, you can get the tap devices from `virsh` in the
`libvirt-libvirt-default` pod for the Kubernetes node, using the `instance_name`
from the previous command by first getting the domain ID:

``` shell
kubectl -n openstack exec libvirt-libvirt-default-25vcr -- virsh domid instance-000014a6
```

and then the tap devices for the domain ID:

``` shell
kubectl -n openstack exec libvirt-libvirt-default-25vcr -- virsh domiflist 1025
```

`virsh domiflist` also provides the MAC address.

Then, you can see that the integration bridge has ports:

``` shell
kubectl ko ${NODE} ofctl show br-int | grep -iE 'tap28144317-cd|tap3e6fb108-a4'
```

where the tap devices from `grep` com from the `virsh domiflist`. You should
also see the MAC addresses match. If `grep` finds this, you have identified
the network interface(s) for the instance on the integration bridge on the
correct Kubernetes node.

This information will tell you what to look for regarding the instance in OVS,
and you can see these in the output of `ip a sh` on the compute node itself:

``` shell
ip a sh
```

and you can use `tcpdump` on it there, e.g., `tcpdump -i tap28144317-cd`.

## Use the the MySQL command line client for the DB

Neutron has a pretty comprehensive API, but you might want or need to see the
database sometimes. In very bad cases, you may need to adjust the schema.

You need to use a node with access to the service network (with the Kubernetes
cluster IPs), e.g., use one of your Kubernetes nodes

If you don't have it, you will need to install a `mysql` command line client
(on a Kubernetes node or a node on the Kubernetes service network):

``` shell
# On Ubuntu
sudo apt install mariadb-client-core-10.6
```

Then you can connect to the database:

``` shell
mysql -u root \
-p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
-h mariadb-cluster-primary.openstack.svc.cluster.local
```

Make sure to change `svc.cluster.local` if you have set the name of your cluster
away from this default value.

Maria has databases for Neutron, etc, so you may want `use neutron;` after
starting the client, or add `neutron` to the MySQL command.

``` sql
use neutron;
```

From here, you can use MySQL client commands on the database.
