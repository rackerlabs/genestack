# Label all of the nodes in the environment

To use the K8S environment for OpenStack all of the nodes MUST be labeled. The following Labels will be used within your environment.
Make sure you label things accordingly.

!!! note

    The labeling of nodes is automated as part of the `setup-kubernetes.yml` playbook based on ansible groups.
    For understanding the use of k8s labels is defined as following, automation and documented deployment
    steps build ontop of the labels referenced here:

    The following example assumes the node names can be used to identify their purpose within our environment.
    That may not be the case in reality. Adapt the following commands to meet your needs.

## Genestack Labels

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
|:-----|--|:----------------:|:------|
| **role** | str | `storage-node` | The "role" is general purpose, and currently only used when deploying the ceph cluster with rook |
| **openstack-control-plane** | str| `enabled` | Defines which nodes will run the OpenStack Control Plane |
| **openstack-compute-node** | str|`enabled` | Defines which nodes will run OpenStack Compute |
| **openstack-network-node** | str|`enabled` | Defines which nodes will run OpenStack Networking |
| **openstack-storage-node** | str|`enabled` | Defines which nodes will run OpenStack Storage |
| **node-role.kubernetes.io/worker** |str| `worker` | Defines which nodes are designated kubernetes workers |

!!! example

    Here's an example labeling all of the nodes: the subshell commands are using the node name to identify how to appropriately distribute the workloads throughout the environment.

    ``` shell
    # Label the storage nodes - optional and only used when deploying ceph for K8S infrastructure shared storage
    kubectl label node $(kubectl get nodes | awk '/ceph/ {print $1}') role=storage-node

    # Label the openstack controllers
    kubectl label node $(kubectl get nodes | awk '/controller/ {print $1}') openstack-control-plane=enabled

    # Label the openstack compute nodes
    kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

    # Label the openstack network nodes
    kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

    # Label the openstack storage nodes
    kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') openstack-storage-node=enabled

    # With OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
    kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

    # Label all workers - Recommended and used when deploying Kubernetes specific services
    kubectl label node $(kubectl get nodes | awk '/worker/ {print $1}')  node-role.kubernetes.io/worker=worker
    ```

### Validate node labels

After labeling everything it's good to check the layout and ensure correctness.

``` shell
# Verify the nodes are operational and labled.
kubectl get nodes -o wide --show-labels=true
```

!!! tip "Make the node layout pretty"

    ``` shell
    # Here is a way to make it look a little nicer:
    kubectl get nodes -o json | jq '[.items[] | {"NAME": .metadata.name, "LABELS": .metadata.labels}]'
    ```
