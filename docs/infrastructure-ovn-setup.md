# Deploy Open vSwitch OVN

!!! note

    We're not deploying Openvswitch, however, we are using it. The implementation on Genestack is assumed to be done with Kubespray which deploys OVN as its networking solution. Because those components are handled by our infrastructure there's nothing for us to manage / deploy in this environment. OpenStack will leverage OVN within Kubernetes following the scaling/maintenance/management practices of kube-ovn.

## Configure OVN for OpenStack

Post deployment we need to setup neutron to work with our integrated OVN environment. To make that work we have to annotate or nodes. Within the following commands we'll use a lookup to label all of our nodes the same way, however, the power of this system is the ability to customize how our machines are labeled and therefore what type of hardware layout our machines will have. This gives us the ability to use different hardware in different machines, in different availability zones. While this example is simple your cloud deployment doesn't have to be.

## OVN Annotations

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
|:-----|--|:----------------:|:------|
| **ovn.openstack.org/int_bridge** | str | `br-int` | The name of the integration bridge that will be used. |
| **ovn.openstack.org/bridges** | str | `br-ex` | Comma separated list of bridges that will be created and plugged into OVS for a given node. |
| **ovn.openstack.org/ports** | str | `br-ex:bond1` | Comma separated list of bridge mappings. Maps values from the **bridges** annotation to physical devices on a given node.  |
| **ovn.openstack.org/mappings** | str | `physnet1:br-ex` | Comma separated list of neutron mappings. Maps a value that will be used in neutron to a value found in the **ports** annotation. |
| **ovn.openstack.org/availability_zones** | str | `az1` | Colon separated list of Availability Zones a given node will serve. |
| **ovn.openstack.org/gateway** | str| `enabled` | If set to `enabled`, the node will be marked as a gateway. |

### Gather the network enabled nodes

Set the annotations needed within the environment to meet the needs of your workloads on the hardware you have.

!!! tip "Post Deployment"

    Review the OVN Operations Guide for more information on how to manage your OVN environment post deployment. The guide can be found [here](ovn-kube-ovn-openstack.md). The guide will help you understand how to manage your OVN environment and how to troubleshoot issues that may arise.

### Set `ovn.openstack.org/int_bridge`

Set the name of the OVS integration bridge we'll use. In general, this should be **br-int**, and while this setting is implicitly configured we're explicitly defining what the bridge will be on these nodes.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/int_bridge='br-int'
```

### Set `ovn.openstack.org/bridges`

Set the name of the OVS bridges we'll use. These are the bridges you will use on your hosts within OVS. The option is a string and comma separated. You can define as many OVS type bridges you need or want for your environment.

!!! note

    The functional example here annotates all nodes; however, not all nodes have to have the same setup.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/bridges='br-ex'
```

### Set `ovn.openstack.org/ports`

Set the port mapping for OVS interfaces to a local physical interface on a given machine. This option uses a colon between the OVS bridge and the and the physical interface, `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined by separating values with a comma.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/ports='br-ex:bond1'
```

### Set `ovn.openstack.org/mappings`

Set the Neutron bridge mapping. This maps the Neutron interfaces to the ovs bridge names. These are colon delimitated between `NEUTRON_INTERFACE:OVS_BRIDGE`. Multiple bridge mappings can be defined here and are separated by commas.

!!! note

    Neutron interfaces are string value and can be anything you want. The `NEUTRON_INTERFACE` value defined will be used when you create provider type networks after the cloud is online.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/mappings='physnet1:br-ex'
```

### Set `ovn.openstack.org/availability_zones`

Set the OVN availability zones which inturn creates neutron availability zones. Multiple network availability zones can be defined and are colon separated which allows us to define all of the availability zones a node will be able to provide for, `nova:az1:az2:az3`.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/availability_zones='az1'
```

!!! note

    Any availability zone defined here should also be defined within your **neutron.conf**. The "az1" availability zone is assumed by Genestack; however, because we're running in a mixed OVN environment, we define where we're allowed to execute OpenStack workloads ensuring we're not running workloads in an environment that doesn't have the network resources to support it.

    Additionally, an availability zone can be used on different nodes and used to define where gateways reside. If you have multiple availability zones, you will need to define where the gateways will reside within your environment.

### Set `ovn.openstack.org/gateway`

Define where the gateways nodes will reside. There are many ways to run this, some like every compute node to be a gateway, some like dedicated gateway hardware. Either way you will need at least one gateway node within your environment.

``` shell
kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/gateway='enabled'
```

## Run the OVN integration

With all of the annotations defined, we can now apply the network policy with the following command.

``` shell
kubectl apply -k /etc/genestack/kustomize/ovn
```

After running the setup, nodes will have the label `ovn.openstack.org/configured` with a date stamp when it was configured.
If there's ever a need to reconfigure a node, simply remove the label and the DaemonSet will take care of it automatically.

!!! tip "Setup your OVN backup"

    To upload backups to Swift with tempauth, edit
    /etc/genestack/kustomize/ovn-backup/base/ovn-backup.config to set
    `SWIFT_TEMPAUTH_UPLOAD' "true"`, edit the other related options
    appropriately (i.e., set the CONTAINER) and fill the ST_AUTH, ST_USER, and
    ST_KEY as appropriate for the Swift CLI client in the `swift-tempauth.env`
    file and then run:

    ``` shell
    kubectl apply -k /etc/genestack/kustomize/ovn-backup/base \
    --prune -l app=ovn-backup \
    --prune-allowlist=core/v1/Secret \
    --prune-allowlist=core/v1/ConfigMap
    ```

    If you need to change variables in the future, you can edit the relevant
    files and use `kubectl` with these prune options to avoid accumulating
    old ConfigMaps and Secrets from successive `kubectl apply` operations, but
    you can omit the pruning options if desired.

### Centralize `kube-ovn-controller` pods

By default, _Kubespray_ deploys _Kube-OVN_ allowing [`kube-ovn-controller` pods](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-controller), which play a central role, to distribute across various kinds of cluster nodes.  In _Genestack_, this would include compute nodes and other kinds of nodes. By contrast, `ovn-central` pods, which also play a crucial central role, run only on nodes labelled `"kube-ovn/role": "master"`. A _Genestack_ installation will typically have control functions centralized on a small set of nodes, which you may have different resource allocations and different redundancy and uptime requirements for relative to other types of nodes, so you can set the `kube-ovn-controller` pods to run in the same location as [`ovn-central`](https://kubeovn.github.io/docs/stable/en/reference/architecture/#ovn-central) on _Kube-OVN_ master nodes (which most likely simply match your k8s cluster control nodes unless you've customized it):

``` shell
kubectl -n kube-system patch deployment kube-ovn-controller -p '{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "kube-ovn/role": "master",
          "kubernetes.io/os": "linux"
        }
      }
    }
  }
}
'
```

This helps keep critical control functions on a known set of nodes.
