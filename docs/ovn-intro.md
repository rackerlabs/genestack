# The purpose of this introduction

This introduction attempts to explain the basic operation of OVN and OVS,
particularly in the context of _Genestack_. However, you should refer to the
canonical upstream documentation for individual projects as necessary.

# Assumed background information

In sticking to introducing OVN in _Genestack_, the following got written with
some assumed knowledge:

- Some software-defined networking (SDN) concepts
- Some OpenStack concepts
- Some database management system (DBMS) concepts

In most cases, you will probably have to decide whether you want or need to do
further out-of-band reading based on the context in which these come up. In
some cases, a cursory explanation gets provided in passing.

# Basic background information and terminology

- You can find information on the general OVN architecture in
  `ovn-architecture(7)`, which you can find in PDF, HTML, or plain text
  [here](https://docs.ovn.org/en/latest/ref/index.html)
- While it probably contains some outdated information, you may wish to watch
  [Introduction to OVN - OVS Conference 2015](https://www.youtube.com/watch?v=v1xkJjnuzhk)
    - three OVN contributors created this presentation
    - the basic architecture hasn't changed
- _Genestack_ installs OVN with _Kube-OVN_.
    - this includes OVS, described later.
- To complete the architecture reading, you should read the
  [Kube-OVN architecture](https://kubeovn.github.io/docs/stable/en/reference/architecture/)
  documentation.
- Reading and understanding the two canonical architecture documentation
  references above will give you more information than shown here, but this
  attempts to provide a high-level overview, and covers in particular how we
  use the single OVN installation from _Kube-OVN_ for both OpenStack and
  Kubernetes.
- A _software-defined networking controller_ provides centralized management
  for software defined networks, particularly in defining rules for how to move
  network packets.
- OVN functions as a software-defined networking controller.
- OVN has good documentation:
  [Open Virtual Network (OVN) Documentation](https://docs.ovn.org/en/latest/)
    - The [OVN reference guide](https://docs.ovn.org/en/latest/ref/index.html)
      typically gets installed as the UNIX manual pages
        - although you will not find the manual pages in the _Genestack_ pods.
- OVN calls its northbound clients _Cloud Management Systems_, often
  abbreviated as **CMS**.
- OVN in _Genestack_ has two CMSes:
    - the _Kubernetes_ cluster
    - _OpenStack Neutron_
- [_Open vSwitch_](https://www.openvswitch.org/) provides software-defined switches.
    - This usually gets abbreviated as **OVS**.
    - It provides L2 switches in software.
    - In _Genestack_, OVN takes care of the OVS switch programming.
    - See more detailed treatment of OVS below.
- OVN works with OVS to:
    - program OVS switches
    - provide a higher layer of abstraction than OVS.
        - In particular, OVN provides _logical entities_
- OVN ultimately has OVS at the far south end of its data flow
    - and exists to provide a logical higher layer of abstraction than OVS

## Basic OVN operation and architecture

- This section covers basic OVN operation abstracted from the CMS.
- We install OVN as for Kubernetes with _Kube-OVN_
    - so a section will follow on the details of installation by/for Kubernetes.
- Remember, _Genestack_ uses OVN with two CMSes:
    - OpenStack
    - Kubernetes

    so a section will follow with details for each respective CMS. OVN design
    allows for use of more than one CMS with for an OVN installation.

- So, this section contains an abstract description of OVS operation, followed
  by installation details and per-CMS details in following sections.

### the OVN plugin

- Every CMS has an **OVN plugin**.
    - In _Genestack_, OpenStack and Kubernetes, as the two CMSes, **both** use
      their OVN plugins on the single OVN installation.
- Some details on how this works will follow in sections and subsections below.
- _OpenStack Neutron_ has
  [_networking-ovn_](https://docs.openstack.org/networking-ovn/latest/) for the
  OVN plugin.
    - This gets developed in Neutron as a first-party ML2 plugin for using OVN
    - So _Genestack_ implicitly uses this.
- The plugin allows the CMS to control OVN for its needs.
    - e.g., creating a network in Neutron will result in _networking-ovn_,
      the OpenStack OVN plugin, writing a logical switch into the NB DB.
    - One of the main functions of the OVN plugin is to translate network
      components from the CMS into _logical entities_ based on standard
      networking concepts such as switches and routers into the OVN north
      database

### Central OVN components

- OVN has three central components below the CMS/OVN plugin architecturally:
  - the _ovn-northd_ daemon
  - The north database, often referred to as **NB** or NB DB.
  - The south database, often referred to as **SB** or SB DB.
  - As a group, these often informally get referred to collectively as **OVN
    central**.
- OVN doesn't generally vary in implementation below the CMS/OVN plugin
    - The CMS/OVN plugin must get implemented separately for each CMS.
    - However, _Kube-OVN_, in use in _Genestack_, actually has made some minor
      modifications as described
      [here](https://kubeovn.github.io/docs/stable/en/reference/ovs-ovn-customized/)
        - so you might need to know about that relative to stock OVN.

#### OVN databases and _ovn-northd_

- As mentioned, OVN has the NB and SB.
    - both are centrally located in the OVN architecture
    - It has no other databases (unless you count the OVS databases at the far
      south end of the data flow)

##### OVSDB DBMS

- OVSDB started as the DBMS for OVS, which also uses it.
- The OVS developers (who also developed OVN) originally designed OVSDB for OVS.
- NB and SB run **OVSDB** as the DBMS.
    - OVS does as well.
- As an aside, in various sources, the term "OVSDB" sometimes gets used in a
  way that makes it look like an application layer network protocol, a
  database, or a DBMS.
     - When used like a protocol, it refers to accessing the OVSDB by the OVSDB
       procotol
     - etc. (e.g., used as a database, refers to an OVSDB DBMS database).
- OVSDB works transactionally, like InnoDB for MySQL or MariaDB.
    - So you can expect [ACID](https://en.wikipedia.org/wiki/ACID) semantics
      or behavior
    - However, it lacks many features of larger general-purpose DBMSes
        - e.g., sharding
- OVSDB uses the Raft algorithm for high availability (HA).

###### Raft algorithm

- In **Raft** HA algorithms, a cluster elects a leader.
- All writes go only to the leader.
- If you lose a leader, a new leader gets elected.
- It takes a majority of nodes connected together to elect a new leader.
- The cluster remains fully functional as long as you have a majority of nodes
  connected together.
    - This allows the cluster to maintain consistency.
    - A connected minority of nodes will not elect a leader and will not take
      writes
        - so a reunited cluster can consistently reconcile the data from
          all nodes because anything written to a majority of nodes should
          get written to all nodes
- The cluster functions in read-only mode when you don't have a leader.

##### _ovn-northd_

- _ovn-northd_ translates logical entities from the NB DB into logical flows,
  and writes the logical flows into the SB DB
- So, _ovn-northd_ talks with the NB and SB DBs.
- _ovn-northd_ doesn't talk with anything south of the SB DB, but the logical
  flows it writes there influence the southbound _ovn-controller_ component

##### OVN NB

- The CMS or CMSes (e.g., _OpenStack_ and _Kubernetes_) drives OVN with its OVN
  plugin
- The OVN plugins write OVN logical entities directly into the NB DB
- The NB contains OVN's logical entities
  - written there by the OVN plugin, based on actions taken by the CMS
  - e.g., logical switches, logical routers, etc.
  - It generally doesn't contain much of anything else.
- OVN plugins perform CRUD-type (create, read, update, delete) operations on
  the NB DB directly.
- _ovn-northd_ automatically acts on the state of the database, so the OVN
  plugin doing CRUD operations plays a major and direct role in driving OVN's
  operation.
    - So the OVN plugin doesn't do anything like API calls or use a message
      queue. It modifies the NB DB, and OVN continually treats the NB DB as
      canonical. _ovn-northd_ will start propagating updates applied by the OVN
      plugin or by anything else to the NB DB southward (SB DB) automatically
      and immediately.

##### OVN SB

- The OVN SB contains OVN logical flows based on the logical entities in the NB
  DB.
- The SB DB gets read by the _ovn-controller_ component described below.
- The SB DB holds information on the physical infrastructure
    - e.g., the existence of compute nodes and k8s nodes

### Distributed OVN components

#### OVS

- While included here as an architectural component of OVN, you can use OVS
  without OVN.
- A _network flow_ refers to a sequence of packets from a source to a
  destination that share some characteristics, like protocol, such as TCP or
  UDP, destination address, port number, and other such things.
- OVS resembles Linux-bridge in providing L2 switches in software
    - but OVS switches have greater programmability with the OpenFlow protocol.

    - OVS switches get programmed with [_OpenFlow_](https://en.wikipedia.org/wiki/OpenFlow), which define the network flows.
- OVS runs on all forwarding-plane nodes
    - "Forwarding plane" from SDN terminology also sometimes gets called the
      data-plane
    - e.g., all Kubernetes nodes in _Genestack_ and Kubernetes clusters using
      _Kube-OVN_.
- OVN manages the OVS switches.
- (Incidentally, OVS came first, and the OVS developers also wrote OVN as the
  logical continuation of OVS)

#### _ovn-controller_

- The [_ovn-controller(8)_](https://www.ovn.org/support/dist-docs/ovn-controller.8.html) component runs on anywhere OVS runs in any
  or all types of OVN installations.
- The _ovn-controller_ reads logical flows from the SB DB and implements with
  OpenFlow flows on OVS.
- _ovn-controller_ also reports hardware information to the SB DB.

## OVN installation via _Kube-OVN_ in _Genestack_

- _Genestack_ installs OVN via _Kube-OVN_ "for" the Kubernetes cluster.
- _Genestack_ does not install OVN separately for _OpenStack_.
- You should see the [_Kube-OVN architecture page_](https://kubeovn.github.io/docs/stable/en/reference/architecture/)
  for more detailed explanation

### `ovn-central` in _Kube-OVN_ and _Genestack_

- In _Kube-OVN_ and _Genestack_,
  [OVN central](https://kubeovn.github.io/docs/stable/en/reference/architecture/#ovn-central):
    - as described in the documentation, "runs the control plane components of OVN, including ovn-nb, ovn-sb, and ovn-northd."
    - runs in the `kube-system` namespace
    - runs on three pods:
        - with a name starting with `ovn-central`, and
        - labelled `app=ovn-central`
    - each pod runs one copy of each of the three OVN central components:
        - NB
        - DB
        - _ovn-northd_
    - so the informal name "OVN central" for these centralized components
    matches what you find running on the pods.
    - these pods get labelled with what each pod serves as the master for:
        - so you find one each of the following labels across the three pods:
            - `ovn-nb-leader=true`
            - `ovn-northd-leader=true`
            - `ovn-sb-leader=true`

          although one pod might have more than one of the labels.

            - these labels indicate which pod has the leader for the service
              in question.
    - With the raft HA algorithm described previously, OVN should continue
      working normally when losing one of these pods.
    - Losing two of these pods, with one still running, should result in OVN
      working in read-only mode.

### `kube-ovn-controller`

- [`kube-ovn-controller` pods](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-controller)

    the linked documentation describes, in part (see the documentation link for
    further details):

    > This component performs the translation of all resources within Kubernetes
    > to OVN resources and acts as the control plane for the entire Kube-OVN
    > system. The kube-ovn-controller listens for events on all resources
    > related to network functionality and updates the logical network within
    > the OVN based on resource changes.

### `kube-ovn-monitor`

- [`kube-ovn-monitor`](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-monitor)

    the linked documentation describes it:

    > This component collects OVN status information and the monitoring metrics

### per-node components

- Each _Kubernetes_ node has pods for OVN as well.

#### Components on all nodes

A number of components run on all nodes as a _DaemonSet_.

##### `ovs-ovn` pods

- [`ovs-ovn` pods](https://kubeovn.github.io/docs/stable/en/reference/architecture/#ovs-ovn)

    the linked documentation describes it:

    > ovs-ovn runs as a DaemonSet on each node, with openvswitch, ovsdb, and
    > ovn-controller running inside the Pod. These components act as agents for
    > ovn-central to translate logical flow tables into real network
    > configurations

##### `kube-ovn-cni` pods

- [`kube-ovn-cni`](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-cni) pods:

    the linked documentation describes it, in part  (see the documentation link
    for further details):

    > This component runs on each node as a DaemonSet, implements the CNI
    > interface, and operates the local OVS to configure the local network.
    >
    > This DaemonSet copies the kube-ovn binary to each machine as a tool for
    > interaction between kubelet and kube-ovn-cni. This binary sends the
    > corresponding CNI request to kube-ovn-cni for further operation. The
    > binary will be copied to the /opt/cni/bin directory by default.
    >
    > kube-ovn-cni will configure the specific network to perform the
    > appropriate traffic operations

    - see the documentation in full for more details

##### `kube-ovn-pinger` pods

- [`kube-ovn-pinger` pods](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-pinger)

    the linked documentation describes it:

    > This component is a DaemonSet running on each node to collect OVS status
    > information, node network quality, network latency, etc. The monitoring
    > metrics collected can be found in Metrics.

##### `kube-ovn-speaker`

- Included only for completeness. _Genestack_ does not use these by default.

#### `ovn-metadata-agent` on compute-nodes only

- `ovn-metadata-agent` pods:
    - run only on compute nodes
    - uniquely amongst all pods mentioned, _Genestack_ installs these from the
      _OpenStack Helm_ chart, and they don't come from _Kube-OVN_
    - These provide the metadata service associated with _Openstack Neutron_
      for instances.

### OVN and OpenStack

- _networking-ovn_ serves as the OVN plugin for _OpenStack Neutron_.
- As mentioned above, _OpenStack Neutron_ has
  [_networking-ovn_](https://docs.openstack.org/networking-ovn/latest/) for the
  OVN plugin.
    - This gets developed in Neutron as a first-party ML2 plugin for using OVN
- To drive an OVN installation via _networking-ovn_, Neutron only requires:
    - NB DB connection information
    - SB DB connection information
- _Genestack_ supplies _Neutron_ with the NB and SB DB connection information
    - So you see and find OVN components installed for Kubernetes via
      _Kube-OVN_ as described above instead of what you would find
      for a conventional OVN installation installed for and servicing OpenStack
      as its sole CMS.
- Neutron has the ability to automatically repair the OVN database to match
  Neutron
    - the setting `neutron_sync_mode` in `neutron.conf` or override
      `conf.neutron.ovn.neutron_sync_mode` in _Genestack_ or _OpenStack Helm_
      overrides control whether Neutron does this.
    - **_Genestack_ turns `neutron_sync_mode` off because it doesn't work when
      you use a second CMS on the same OVN installation**
        - presumably because _Neutron_ can't assume everything in the NB should
          belong to it to modify; in particular, entries that appear extraneous
          from the perspective of Neutron may belong to another CMS
            - In particular, a fresh _Genestack_ installation already shows 6
              unknown ACLs when Neutron runs this check
