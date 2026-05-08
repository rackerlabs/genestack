## OVN Annotations for Ironic-Enabled Deployment

This guide configures OVN annotations for deploying Ironic bare metal provisioning alongside OpenStack standard deployment (non-ironic). Ironic requires additional bridge, VLAN, and network mappings beyond standard OVN deployments.

### Overview of OVN Annotations

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
| :--- | -- | :--: | :--- |
| **ovn.openstack.org/int_bridge** | str | `br-int` | The name of the integration bridge that will be used. |
| **ovn.openstack.org/bridges** | str | `br-ex,br-pxe` | **Required for Ironic:** Include `br-pxe` bridge for PXE provisioning network. |
| **ovn.openstack.org/ports** | str | `br-ex:bond0,br-pxe:vlan126` | **Required for Ironic:** Map each bridge to physical interface or VLAN (format: `bridge:interface`). |
| **ovn.openstack.org/vlans** | str | `vlan126:bond0:126:1500` | **Required for Ironic:** Create VLAN interface for PXE (format: `name:parent:vlan_id:mtu`). |
| **ovn.openstack.org/mappings** | str | `physnet1:br-ex,physnet2:br-pxe` | **Required for Ironic:** Map Neutron provider networks to bridges. |
| **ovn.openstack.org/availability_zones** | str | `az1` | Colon-separated list of Availability Zones. |
| **ovn.openstack.org/gateway** | str | `enabled` | Mark node as an OVN gateway for external traffic. |

## Applying Ironic Annotations

When deploying Ironic for bare metal provisioning, apply the key annotations (bridges, ports, vlans, mappings) shown in the overview table above to required controller and network nodes if not already exists.

### Set `ovn.openstack.org/int_bridge`

Set the name of the OVS integration bridge we'll use. In general, this should be **br-int**, and while this setting is implicitly configured we're explicitly defining what the bridge will be on these nodes. This step mirrors standard deployments and can be skipped if already configured."

``` shell
kubectl annotate \
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/int_bridge='br-int'
```

### Set `ovn.openstack.org/bridges`

Set the name of the OVS bridges we'll use. These are the bridges you will use on your hosts within OVS. The option is a string and comma separated. You can define as many OVS type bridges you need or want for your environment.

!!! note

    The Ironic functional example here annotates all nodes; however, not all nodes have to have the same setup. If the `ovn.openstack.org/bridges` is already configured, use `--overwrite` when annotating the nodes.

``` shell
# First, set the required bridges including br-pxe
kubectl annotate \
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/bridges='br-ex,br-pxe'
```
 
### Set `ovn.openstack.org/ports`

Set the port mapping for OVS interfaces to a local physical interface on a given machine. This option uses a colon between the OVS bridge and the physical interface, `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined by separating values with a comma.

!!! note

    For setting up Ironic, the port mapping should reference the provisioning vlan interface (e.g., `br-ex:bond0,br-pxe:vlanXYZ`) rather than to a physical interface. If the `ovn.openstack.org/ports` is already configured, use `--overwrite` when annotating the nodes.

```shell
# Update vlanXYZ with your interface name for provisioning network
kubectl annotate \
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/ports='br-ex:bond0,br-pxe:vlanXYZ'
```

### Set `ovn.openstack.org/vlans` (Optional)

Create Linux VLAN subinterfaces on the host before OVN attaches them to an OVS bridge. This is useful when the host must keep the parent interface while OVN consumes a tagged child interface such as `bond0.XYZ`.

```shell
# Create the provisioning VLAN interface
kubectl annotate \ 
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/vlans='vlanXYZ:bond0:XYZ:1500'
```


### Set `ovn.openstack.org/mappings`

Set the Neutron bridge mapping. This maps the Neutron interfaces to the ovs bridge names. These are colon delimitated between `NEUTRON_INTERFACE:OVS_BRIDGE`. Multiple bridge mappings can be defined here and are separated by commas.

!!! note

    Set the Neutron bridge mapping for Ironic provisioning network. Neutron interfaces are string value and can be anything you want. The `NEUTRON_INTERFACE` value defined will be used when you create provider type networks after the cloud is online. If the `ovn.openstack.org/mappings` is already configured, use `--overwrite` when annotating the nodes.

``` shell
# Map to Neutron provider networks
kubectl annotate \
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/mappings='physnet1:br-ex,physnet2:br-pxe'
```

### Set `ovn.openstack.org/availability_zones`

Set the OVN availability zones which inturn creates neutron availability zones. Multiple network availability zones can be defined and are colon separated which allows us to define all of the availability zones a node will be able to provide for, `nova:az1:az2:az3`.

``` shell
kubectl annotate \
        nodes \
        -l openstack-control-plane=enabled -l openstack-network-node=enabled \
        ovn.openstack.org/availability_zones='az1'
```

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

### Key Differences from Standard OVN

- **Provisioning Bridge (`br-pxe`):** Ironic requires a dedicated bridge for PXE boot traffic
- **Provisioning VLAN:** The provisioning network must be isolated on a specific VLAN interface
- **Provider Network Mapping:** The provisioning network must be explicitly mapped to Neutron
