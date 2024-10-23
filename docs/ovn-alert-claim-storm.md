This page explains the `OVN claim storm` alert in _Genestack_.

# Background information

_OVN_ has a distributed architecture without a central controller. The
_ovn-controller_ process on each chassis, in OVN terminology, meaning every k8s
node since _Genestack_ uses _Kube-OVN_, runs the same control logic, and
coordination happens through the OVN south database, but this introduces some of
the complexity of a distributed system to what often acts and appears like
centralized control.

OVN makes use of some ports not bound to any particular chassis, especially on
the gateway nodes. OVN may move those ports to a different chassis if a gateway
node goes down, or BFD (bi-directional forwarding detection) shows poor link
quality for a chassis. In some edge cases, _ovn-controller_ on different nodes
might each determine that they should have a port, and each chassis will claim
the port as quickly as it can. That doesn't normally or usually happen, and
could have some range of edge case root causes, perhaps a NIC malfunctioning in
a way that escapes detection by BFD (bi-directional forwarding detection). The
architecture of OVN seems to make it hard to ensure that this condition could
*never* occur, even if it rarely occurs, and OVN itself implements a rate-limit
of 0.5s, so that no chassis will try to claim the same port more than once every
0.5s, as seen in
[this commit](https://github.com/ovn-org/ovn/commit/4dc4bc7fdb848bcc626becbd2c80ffef8a39ff9a).

However, a typical production-grade _Genestack_ installation will probably have
at least 3 gateway nodes, and each public IP CIDR block added individually to
the installation will have an associated `cr-lrp` on the gateway nodes, not
bound to any particular chassis and so free to move between the gateway nodes.
These ports allow OpenStack nova instances without a floating IP to access the
Internet via NAT, which allows them to, say, pull operating system patches, etc.
without needing to assign a floating IP so that an instance only needs a
floating IP to make services available on a public Internet address. So,
consider 3 gateway nodes and 5 CIDR blocks, and a 0.5 s rate limit per port per
node. In the worst case, with each node trying to claim every port not bound to
a chassis as quickly as possible, this example could have each port getting
claimed about six times per second, and a load of 30 claims per second to commit
to the to the OVN south DB. (In fact, it only seems to take one bad node to
shoot this up to around the theoretical maximum, since the bad node might claim
it as often as possible, and every other node has equal claim.) In this
scenario, the affected ports themselves move between chassis too quickly to
actually work, and the OVN south DB itself gets overloaded. In that case,
instances without floating IPs would not have Internet access, and the high load
on the south DB would likely result in provisioning failures for new OpenStack
nova instances and new k8s pods.

# Symptoms and identification

The alert will normally catch this condition, however, for reference and to
identify the individual nodes with the problem:

## network agents `Alive` status

`openstack network agent list` usually has output like below (aside from the
made up UUIDs and node names):

```
+--------------------------------------+------------------------------+------------------------+-------------------+-------+-------+----------------------------+
| ID                                   | Agent Type                   | Host                   | Availability Zone | Alive | State | Binary                     |
+--------------------------------------+------------------------------+------------------------+-------------------+-------+-------+----------------------------+
| deadbeef-dead-beef-dead-deadbeef0001 | OVN Controller agent         | node01.domain.name     |                   | :-)   | UP    | ovn-controller             |
| deadbeef-dead-beef-dead-deadbeef0002 | OVN Controller agent         | node02.domain.name     | nova              | :-)   | UP    | ovn-controller             |
| deadbeef-dead-beef-dead-deadbeef0003 | OVN Metadata agent           | node02.domain.name     | nova              | :-)   | UP    | neutron-ovn-metadata-agent |
| deadbeef-dead-beef-dead-deadbeef0004 | OVN Controller agent         | node03.domain.name     | nova              | :-)   | UP    | ovn-controller             |
| deadbeef-dead-beef-dead-deadbeef0005 | OVN Metadata agent           | node03.domain.name     | nova              | :-)   | UP    | neutron-ovn-metadata-agent |
| deadbeef-dead-beef-dead-deadbeef0006 | OVN Controller agent         | node04.domain.name     |                   | :-)   | UP    | ovn-controller             |
| deadbeef-dead-beef-dead-deadbeef0007 | OVN Controller agent         | node05.domain.name     | nova              | :-)   | UP    | ovn-controller             |
| deadbeef-dead-beef-dead-deadbeef0008 | OVN Metadata agent           | node05.domain.name     | nova              | :-)   | UP    | neutron-ovn-metadata-agent |
| deadbeef-dead-beef-dead-deadbeef0009 | OVN Controller agent         | node06.domain.name     | nova              | :-)   | UP    | ovn-controller             |
```

For minor technical reasons, these probably don't technically qualify as real
Neutron agents, but in either case, this information gets queried from the
OVN south DB, which gets overloaded, so the output of this command will likely
show `XXX` [sic] under the alive column, although they do continue to show
state `UP`.

Since this happens because of the south DB, this command doesn't help identify
affected nodes. All agents will likely show `XXX` for `Alive`.

## log lines

The alert checks log lines, but you will have to identify which gate nodes
have the issue.

The log lines happen on the `ovs-ovn` pods of the gateway nodes, and in full,
look like this:

```
2024-09-05T16:38:54.711Z|19953|binding|INFO|Claiming lport cr-lrp-deadbeef-dead-beef-dead-deadbeef0001 for this chassis.
2024-09-05T16:38:54.711Z|19954|binding|INFO|cr-lrp-deadbeef-dead-beef-dead-deadbeef0001: Claiming de:ad:be:ef:de:01 1.0.1.0/24
2024-09-05T16:39:38.870Z|19955|binding|INFO|Claiming lport cr-lrp-ddeadbeef-dead-beef-dead-deadbeef0002 for this chassis.
2024-09-05T16:39:38.870Z|19956|binding|INFO|cr-lrp-deadbeef-dead-beef-dead-deadbeef0002: Claiming de:ad:be:ef:de:02 1.0.2.0/24
2024-09-05T16:40:32.813Z|19957|binding|INFO|Claiming lport cr-lrp-deadbeef-dead-beef-dead-deadbeef0003 for this chassis.
2024-09-05T16:40:32.813Z|19958|binding|INFO|cr-lrp-deadbeef-dead-beef-dead-deadbeef0003: Claiming de:ad:be:ef:de:03 1.0.3.0/24
2024-09-05T16:41:52.669Z|19959|binding|INFO|Claiming lport cr-lrp-deadbeef-dead-beef-dead-deadbeef0004 for this chassis.
2024-09-05T16:41:52.669Z|19960|binding|INFO|cr-lrp-deadbeef-dead-beef-dead-deadbeef0004: Claiming de:ad:be:ef:de:04 1.0.4.0/24
2024-09-05T16:42:33.762Z|19961|binding|INFO|Claiming lport cr-lrp-deadbeef-dead-beef-dead-deadbeef0004 for this chassis.
```

you will probably see these densely packed and continuously generating with no
other log lines between them with an interval of less than 1 second between
consecutive port bindings.

Log lines like this happen during normal operation, but the ports don't tend
to move around more than once every 5 minutes, so you may see a block like this
for every `cr-lrp` port, and so one for every CIDR block of public IPs you use,
but during a claim storm, you will see the same ports and CIDRs getting bound
continuously and consecutively.

## Remediation

This likely happens as an aggravation of a pre-existing problem, so it may take
some investigation to identify any particular root cause, and draining and
rebooting an affected node may resolve the issue temporarily, or seemingly
permanently enough if the issue occurred due to something transient and
unidentifiable.

Some tips and recommendations:

- ensure you ran `host-setup.yaml` as indicated in the _Genestack_ installation
  documentation which adjusts some kernel networking variables.
    - This playbook works idempotently, and you can run it again on the nodes
      to make sure, and mostly see `OK` tasks instead of `changed`.

    As an example, if you used `infra-deploy.yaml`, on your launcher node,
    you might run something like:

    ```
    sudo su -l

    cd /opt/genestack/ansible && \
    source ../scripts/genestack.rc && \
    ansible-playbook playbooks/host-setup.yml \
    -i /etc/genestack/inventory/openstack-flex-inventory.ini \
    --limit openstack-flex-node-1.cluster.local
    ```

    adjusted for your installation and however you needed to run the playbook.
    (Root on the launcher node created by `infra-deploy.yaml` normally has
    a venv, etc. for Ansible when you do a root login as happens with
    `sudo su -l`.)

- Ensure you have up-to-date kernels.
    - In particular, a bug in Linux 5.15-113 and 5.15-119 resolved in Linux 6.8
      resulted in a problem electing OVN north and south database (NB and SB)
      leaders, although that probably shouldn't directly trigger this issue.
- Ensure you have the best and most up-to-date drivers for your NICs.
- Check BFD
    - As mentioned, OVN uses BFD to help determine when it needs to move ports.

    You might run:

    ```
    kubectl ko vsctl <gateway node> show
    ```

    which shows BFD status on ports in-line to the OVSDB-centric overview
    of OVS for the node, and/or:

    ```
    kubectl ko appctl <gateway node> bfd/show
    ```

    to check directly and only BFD.

    (assuming you have installed the `Kube-OVN` kubectl plugin as described
    in _docs/ovn-troubleshooting.md_'s _Kube-OVN kubectl plugin_ section) and
    investigate any potential BFD issues.

- Check the health and configuration of NIC(s), bonds, etc. at the operating
  system level
- Check switch and switch port configuration.
- If you have a separate interface allowing you to reach a gateway node via SSH,
  you can down the interface(s) with the Geneve tunnels on individual gateway
  nodes one at a time and observe whether downing the interfaces of any
  particular node(s) stops the claim storm.
    - OVN will take care of moving the ports to another gateway node if you
      have multiple gateway nodes. When possible to do this without losing your
      connection (you could perhaps even use the server OOB console), you
      effectively temporarily take one gateway node out of rotation.)
- Drain and reboot any suspect (or all, one at time, if necessary)
  gateway node(s):

  ```
  kubectl drain <gateway-node> --ignore-daemonsets --delete-local-data --force
  # reboot the node
  kubectl uncordon <gateway-node> # after return from reboot
  ```

- Since the issue has strong chance of having occurred as an aggravation of an
  existing, possibly even otherwise relatively benign problem, you should
  perform other general and generic troubleshooting such as reading system
  logs, `dmesg` output, hardware errors reported by DRAC, iLO, or other OOB
  management solutions, etc.
