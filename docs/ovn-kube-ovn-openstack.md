# OVN Post Deployment Updates

Updates to the OVN environment can be made post deployment. All of the required OVN annotations are applied to the nodes in the cluster and can be changed at any time. However, in order to apply the changes, the label `ovn.openstack.org/configured` must be removed to permit the **ovn-setup** daemonset to reapply the configuration.

!!! tip

    Review the the OVN Deployment Guide for more information on how to manage your OVN environment post deployment. The guide can be found [here](infrastructure-ovn-setup.md).

## Label Overview

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
|:-----|--|:----------------:|:------|
| **ovn.openstack.org/configured** | int | `EPOC` | The EPOC time when the confirguration was last applied |

### `ovn.openstack.org/configured`

When the **ovn-setup** Daemonset runs, the `ovn.openstack.org/configured` label is applied to the nodes in the cluster. This label is used to determine if the configuration has been applied to the node. If the label is present, the **ovn-setup** Daemonset will not reapply the configuration to the node. If the label is removed, the **ovn-setup** Daemonset will reapply the configuration to the node.

## Removing the `ovn.openstack.org/configured` label

To remove the `ovn.openstack.org/configured` label from all nodes.

``` shell
kubectl label nodes ${NODE_NAME} ovn.openstack.org/configured-
```

!!! note "Global Configuration Updates"

    The `ovn-setup` daemonset will reapply the configuration to the nodes in the cluster. If you need to reapply changes to all nodes within the cluster, you can remove the label from all nodes at the same time with the following command:

    ``` shell
    kubectl label nodes --all ovn.openstack.org/configured-
    ```

Once the label is removed, the **ovn-setup** Daemonset will immediately reapply the configuration to the nodes in the cluster automatically.
