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
| **ovn.openstack.org/ports** | str | `br-ex:bond1` | Comma separated list of bridge mappings. Maps values from the **bridges** annotation to physical devices or bonds on a given node.  |
| **ovn.openstack.org/bonds** | str | `br-ex:bond0:eno1+eno3:balance-tcp:active` | Comma separated list of bond definitions. Format: `bridge:bondname:member1+member2:mode:lacp`. Creates OVS bonds with specified members. |
| **ovn.openstack.org/bond-options** | str | `bond0:mii-monitor-interval=100,lacp-time=fast` | Comma separated list of additional bond options. Format: `bondname:option1=value1,option2=value2`. Supports MII monitoring, LACP timing, and other OVS bond parameters. |
| **ovn.openstack.org/vlans** | str | `bond0.126:bond0:126:1500` | Comma separated list of host VLAN interfaces that **ovn-setup** should create before attaching ports. Format: `interface_name:parent_interface:vlan_id:mtu`. |
| **ovn.openstack.org/mappings** | str | `physnet1:br-ex` | Comma separated list of neutron mappings. Maps a value that will be used in neutron to a value found in the **ports** or **bonds** annotation. Every provider network name listed in this annotation will have a unique mac address generated per-host. |
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

Set the port mapping for OVS interfaces to a local physical interface on a given machine. This option uses a colon between the OVS bridge and the physical interface, `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined by separating values with a comma.

!!! note

    If using bonds, the port mapping should reference the bond name (e.g., `br-ex:bond0`) instead of individual physical interfaces. See the bonds section below for configuring bonded interfaces.

``` shell
kubectl annotate \
        nodes \
        -l openstack-compute-node=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/ports='br-ex:bond1'
```

### Set `ovn.openstack.org/vlans` (Optional)

Create Linux VLAN subinterfaces on the host before OVN attaches them to an OVS bridge. This is useful when the host must keep the parent interface while OVN consumes a tagged child interface such as `bond0.126`.

**Format:** `interface_name:parent_interface:vlan_id:mtu`

**Parameters:**
- `interface_name`: Name of the VLAN interface to create, for example `bond0.126`
- `parent_interface`: Existing host interface that carries the VLAN, for example `bond0`
- `vlan_id`: Numeric VLAN tag
- `mtu`: MTU to apply to the VLAN interface

**Example: External uplink on VLAN 126**
``` shell
kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/vlans='bond0.126:bond0:126:1500'

kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/ports='br-ex:bond0.126'
```

!!! note

    `ovn.openstack.org/vlans` only creates the host VLAN device. You should still reference that interface through `ovn.openstack.org/ports` so it can be attached to the correct bridge.

### Set `ovn.openstack.org/bonds` (Optional)

Configure OVS bonds for link aggregation and redundancy. This annotation creates bonded interfaces using multiple physical network interfaces.

**Format:** `bridge:bondname:member1+member2+member3:mode:lacp`

**Parameters:**
- `bridge`: The OVS bridge to attach the bond to (e.g., `br-ex`)
- `bondname`: Name of the bond interface (e.g., `bond0`)
- `members`: Physical interfaces to include in the bond, separated by `+` (e.g., `eno1+eno3`)
- `mode`: Bond mode - `balance-slb` (source MAC) or `balance-tcp` (TCP/UDP ports for LACP)
- `lacp`: LACP mode - `off`, `active`, or `passive`

**Example: LACP Bond**
``` shell
kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/bonds='br-ex:bond0:eno1+eno3:balance-tcp:active'
```

**Example: Multiple Bonds**
``` shell
kubectl annotate \
        nodes \
        node1 \
        ovn.openstack.org/bonds='br-ex:bond0:eno1+eno3:balance-tcp:active,br-provider:bond1:eno5+eno7:balance-slb:off'
```

### Set `ovn.openstack.org/bond-options` (Optional)

Configure additional bond options for fine-tuning bond behavior. This annotation is used in conjunction with `ovn.openstack.org/bonds`.

**Format:** `bondname:option1=value1,option2=value2`

**Supported Options:**
- `mii-monitor-interval`: MII link monitoring interval in milliseconds (e.g., `100`)
- `bond-detect-mode`: Link detection method - `miimon` or `carrier`
- `lacp-time`: LACP heartbeat rate - `fast` (1 second) or `slow` (30 seconds)
- `lacp-fallback-ab`: Enable fallback to active-backup if LACP fails - `true` or `false`
- `updelay`: Delay in milliseconds before enabling a link after it comes up
- `downdelay`: Delay in milliseconds before disabling a link after it goes down
- `rebalance-interval`: Rebalancing interval in milliseconds (for `balance-slb` mode)

**Example: LACP with MII Monitoring**
``` shell
kubectl annotate \
        nodes \
        -l openstack-network-node=enabled \
        ovn.openstack.org/bond-options='bond0:mii-monitor-interval=100,lacp-time=fast,bond-detect-mode=miimon'
```

**Example: Multiple Bonds with Different Options**
``` shell
kubectl annotate \
        nodes \
        node1 \
        ovn.openstack.org/bond-options='bond0:mii-monitor-interval=100,lacp-time=fast,bond1:updelay=500,downdelay=500'
```

!!! tip "OVS Bond Modes"

    - **balance-slb**: Source Load Balancing - distributes traffic based on source MAC address. Does not require LACP support on the switch.
    - **balance-tcp**: Balances based on L3/L4 headers (IP addresses and TCP/UDP ports). Requires LACP (`lacp=active` or `lacp=passive`).

    For 802.3ad LACP bonding, use `mode=balance-tcp` with `lacp=active`.

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
NOTE: In the following example, we will apply the 'ovn.openstack.org/gateway' to dedicated network nodes.  You will want to change the node filter to the specific nodes you wish to use as ovn gateway nodes.

``` shell
kubectl annotate \
        nodes \
        $(kubectl get nodes | awk '/network/ {print $1}') \
        ovn.openstack.org/gateway='enabled'
```

## Run the OVN integration

With all of the annotations defined, we can now apply the network policy with the following command.

``` shell
kubectl apply -k /etc/genestack/kustomize/ovn/overlay
```

After running the setup, nodes will have the label `ovn.openstack.org/configured` with a date stamp when it was configured.
If there's ever a need to reconfigure a node, simply remove the label and the DaemonSet will take care of it automatically.

### Reconfiguring Nodes

The OVN setup includes intelligent state management that safely handles configuration changes:

**State Tracking:**
- Previous configuration is stored in per-node ConfigMaps named `ovn-state-<nodename>`
- The setup script compares previous state with new annotations
- Changes are applied incrementally to prevent network disruption

**Safe Port Migration:**
When changing port assignments (e.g., moving from `eno1` to `eno3`), the setup will:
1. Remove the old port (`eno1`) from the bridge
2. Add the new port (`eno3`) to the bridge
3. Update the state ConfigMap

This prevents network loops that could occur if both ports were simultaneously connected to the bridge.

**To reconfigure a node:**

1. Update the node annotations with new configuration
2. Remove the configured label:
   ``` shell
   kubectl label node <node-name> ovn.openstack.org/configured-
   ```
3. The DaemonSet will detect the unlabeled node and reapply configuration
4. Old ports/bonds will be cleaned up, new configuration applied

**Example: Changing from single interface to bonded interfaces**

``` shell
# Update annotations
kubectl annotate nodes node1 --overwrite \
    ovn.openstack.org/ports='br-ex:bond0' \
    ovn.openstack.org/bonds='br-ex:bond0:eno1+eno3:balance-tcp:active' \
    ovn.openstack.org/bond-options='bond0:mii-monitor-interval=100,lacp-time=fast'

# Trigger reconfiguration
kubectl label node node1 ovn.openstack.org/configured-
```

The setup will remove any existing single interface ports and create the bond configuration.

## Back up the OVN databases

The local `ovn-backup` Helm chart installs a CronJob and ConfigMaps containing
its configuration and backup script. The job runs daily by default, saves
compressed northbound and southbound database backups to an existing PVC, and
can optionally upload backups to Swift and metrics to a Prometheus
Pushgateway.

By default, the chart does not create or manage the PVC. It references
`ovndb-backup`, including a PVC left by the previous Kustomize-based
installation, without adopting it. The claim must exist in the chart's
namespace (`kube-system` for the standard installation). The default is
equivalent to the following; Helm install, upgrade, and uninstall do not alter
the claim's lifecycle:

``` yaml
persistence:
  create: false
  claimName: ovndb-backup
```

To use a different existing claim:

``` yaml
persistence:
  claimName: my-ovn-backups
```

The chart does not create the ServiceAccount, Swift Secret, Pushgateway, or
Kube-OVN resources. Before installing it, the `ovn` ServiceAccount and
Kube-OVN tooling must already exist in `kube-system`, and nodes selected by
`kube-ovn/role: master` must be able to mount the backup volume.

The chart can instead create the PVC using the same `claimName` value as
its name. For example:

``` yaml
persistence:
  create: true
  claimName: ovndb-backup
  storageClass: general
  size: 10Gi
  accessMode: ReadWriteOnce
```

Chart-created PVCs have the `helm.sh/resource-policy: keep` annotation and
survive Helm uninstall. A retained PVC is then outside the normal release
lifecycle and a later installation does not automatically adopt it. Reference
the retained claim with `persistence.create: false`, or explicitly handle its
Helm ownership before trying to create it through another release.

To manage storage entirely outside Helm, apply a PVC independently. These
settings use the Genestack defaults inherited from the previous installation:

``` yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ovndb-backup
  namespace: kube-system
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: general
```

``` shell
kubectl apply -f ovndb-backup-pvc.yaml
```

Then leave `persistence.create: false` and reference it:

``` yaml
persistence:
  create: false
  claimName: ovndb-backup
```

This keeps the PVC lifecycle entirely outside Helm. Helm's keep annotation
only prevents Helm from deleting a chart-created PVC. It does not prevent
independent deletion of the PVC or its storage. PersistentVolume reclaim
policy (`Delete` or `Retain`) is configured on the PV or StorageClass, not on
the PVC; this chart does not manage StorageClasses, PVs, or reclaim policy.

The storage class must support volumes on Kube-OVN master nodes. With
`ReadWriteOnce`, a volume may need to detach and reattach if successive jobs
run on different master nodes; choose storage and scheduling appropriate for
the cluster.

Site overrides are read from
`/etc/genestack/helm-configs/ovn-backup/*.yaml`. For example, create
`/etc/genestack/helm-configs/ovn-backup/ovn-backup-helm-overrides.yaml`:

``` yaml
schedule: "0 2 * * *"
persistence:
  claimName: ovndb-backup
backup:
  retentionDays: 14
prometheus:
  enabled: false
  pushgatewayUrl: http://prometheus-pushgateway.prometheus.svc.cluster.local:9091
  jobName: ovn-backup
swift:
  enabled: false
  authUrl: https://swift.example.com/auth/v1.0
  user: account:user
  container: my-ovn-backups
  existingSecret: ovn-backup-swift-tempauth-account
```

Set `swift.authUrl` and `swift.user` in the Helm overrides to supply `ST_AUTH`
and `ST_USER`. To enable uploads, set `swift.enabled: true` and create the
referenced Secret in `kube-system`. The Secret only needs to contain `ST_KEY`:

``` shell
kubectl --namespace kube-system create secret generic \
  ovn-backup-swift-tempauth-account \
  --from-literal=ST_KEY='replace-with-actual-key'
```

Previously created Secrets containing `ST_AUTH`, `ST_USER`, and `ST_KEY` can
remain in place because the updated CronJob reads only `ST_KEY` from the
Secret. The authentication URL and username must still be configured through
`swift.authUrl` and `swift.user` in the Helm overrides.

Swift upload uses the existing script's `kubectl exec` workflow against the
`openstack-admin-client` pod in the `openstack` namespace. That pod and its
Swift client must exist, and the `ovn` ServiceAccount must be authorized to
exec into it. No Swift Secret is required while `swift.enabled` is `false`.

Install or upgrade the release from the Genestack checkout:

``` shell
sudo /opt/genestack/bin/install-ovn-backup.sh
```

Additional Helm flags can be passed to the script, for example
`--set schedule='0 4 * * *'`. Inspect the release and scheduled workload with:

``` shell
helm --namespace kube-system status ovn-backup
helm --namespace kube-system get values ovn-backup
kubectl --namespace kube-system get cronjob ovn-snapshot-cron
```

To test a backup without waiting for the schedule, create a one-off Job and
inspect its logs and the PVC contents:

``` shell
JOB_NAME="ovn-backup-test-$(date +%s)"
kubectl --namespace kube-system create job \
  --from=cronjob/ovn-snapshot-cron "${JOB_NAME}"
kubectl --namespace kube-system logs --follow "job/${JOB_NAME}"
kubectl --namespace kube-system exec "job/${JOB_NAME}" -- find /backup -type f
kubectl --namespace kube-system delete job "${JOB_NAME}"
```

Backups and the configured log file remain on the PVC. Helm removal does not
remove externally managed storage, a chart-created PVC retained by the keep
policy, or the optional Secret. The chart assumes one fixed CronJob in
`kube-system`; it does not provision other dependencies or validate
cross-namespace Swift access.

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
