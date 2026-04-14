### Longhorn Maintenance: 1.8.0 to 1.9.1

## Validation

Kubernetes 1.33.4 satisfies the upstream Longhorn requirement of Kubernetes v1.25+ for upgrades to Longhorn v1.8.0 or newer.
Upstream explicitly supports upgrading Longhorn v1.9.1 from v1.8.x.
Upstream node-selector guidance for v1.9.1 confirms that both user-deployed components and system-managed components must be constrained, and warns that instance-manager changes may not apply immediately while volumes remain attached.

## Goal

Upgrade Genestack Longhorn from 1.8.0 to 1.9.1 while ensuring Longhorn pods and replicas only run on nodes labeled longhorn.io/storage-node=enabled.

## Prep

# Deployment Node

Verify Kubernetes and current Longhorn state:
    kubectl version
    kubectl -n longhorn-system get pods -o wide
    kubectl -n longhorn-system get nodes.longhorn.io
    kubectl -n longhorn-system get settings.longhorn.io system-managed-components-node-selector -o yaml

Inventory current node labels and current Longhorn placement:
    kubectl get nodes -L longhorn.io/storage-node,openstack-compute-node,openstack-storage-node
    kubectl get pv -o custom-columns=PV:.metadata.name,CLAIM_NS:.spec.claimRef.namespace,CLAIM:.spec.claimRef.name,SC:.spec.storageClassName,VOLUME:.spec.csi.volumeHandle
    kubectl -n longhorn-system get replicas.longhorn.io -o custom-columns=REPLICA:.metadata.name,VOLUME:.spec.volumeName,NODE:.spec.nodeID,STATE:.status.currentState

Confirm volumes are healthy before maintenance:
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,OWNER:.status.ownerID

If any important volume is faulted, stop and resolve that first.

# Select Storage Nodes

Apply the Longhorn storage label only to nodes that are allowed to host Longhorn pods and volume replicas:
    # kubectl label node <node-a> longhorn.io/storage-node=enabled --overwrite
    # kubectl label node <node-b> longhorn.io/storage-node=enabled --overwrite

Verify:
    kubectl get nodes -L longhorn.io/storage-node

# Prevent Longhorn from Using Unlabeled Nodes

On each node that should no longer host Longhorn replicas, disable Longhorn scheduling:
    # kubectl -n longhorn-system patch nodes.longhorn.io <node-name> --type merge -p '{"spec":{"allowScheduling":false}}'

In the Longhorn UI, request replica eviction from those nodes.
Longhorn UI -> Node
Select the node
Edit Node and Disks
Set Scheduling to Disable
Set Eviction Requested to Enable
Save

Watch replica movement until no replicas remain on disallowed nodes:
    kubectl -n longhorn-system get replicas.longhorn.io -o custom-columns=REPLICA:.metadata.name,VOLUME:.spec.volumeName,NODE:.spec.nodeID,STATE:.status.currentState --watch

After replicas are gone, remove the node from Longhorn UI if it should not remain a Longhorn node.
Longhorn UI -> Node
Select the node
Confirm no replicas remain
Delete

# Update Longhorn Overrides

Create or update /etc/genestack/helm-configs/longhorn/longhorn.yaml with:
    # global:
    #   nodeSelector:
    #     longhorn.io/storage-node: "enabled"

    # defaultSettings:
    #   systemManagedComponentsNodeSelector: "longhorn.io/storage-node:enabled"

    # longhornManager:
    #   nodeSelector:
    #     longhorn.io/storage-node: "enabled"

    # longhornDriver:
    #   nodeSelector:
    #     longhorn.io/storage-node: "enabled"

    # longhornUI:
    #   nodeSelector:
    #     longhorn.io/storage-node: "enabled"

global.nodeSelector constrains the main chart-managed workloads.
defaultSettings.systemManagedComponentsNodeSelector is required for system-managed components such as instance-manager, CSI plugin, and engine-image.
Explicit component selectors are included to make upgrade behavior predictable.

# Bump the Chart Version

Edit /etc/genestack/helm-chart-versions.yaml:
    # charts:
    #   longhorn: 1.9.1

## Execute

Run the upgrade:
    /opt/genestack/bin/install-longhorn.sh

## Post-Maint

Confirm pods are running only on allowed nodes:
    kubectl -n longhorn-system get pods -o wide --sort-by=.spec.nodeName

Confirm the setting was applied:
    kubectl -n longhorn-system get settings.longhorn.io system-managed-components-node-selector -o yaml

Expected:
    # value: longhorn.io/storage-node:enabled

Confirm Longhorn nodes not intended for storage are unschedulable or absent:
    kubectl -n longhorn-system get nodes.longhorn.io -o yaml | egrep 'name:|allowScheduling:'

Confirm volumes remain healthy:
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

## Troubleshooting

# If System-Managed Pods Stay on the Wrong Nodes

System-managed node-selector changes may not apply immediately while volumes are attached.

If needed, detach remaining volumes or stop workloads that keep them attached.

Re-save the System Managed Components Node Selector setting in the Longhorn UI.
Longhorn UI -> Setting
General
System Managed Components Node Selector
Set to longhorn.io/storage-node:enabled
Save

Re-check pod placement:
    kubectl -n longhorn-system get pods -o wide --sort-by=.spec.nodeName

## Sources

https://longhorn.io/docs/1.9.1/deploy/upgrade/longhorn-manager/
https://longhorn.io/docs/1.9.1/advanced-resources/deploy/node-selector/
https://longhorn.io/docs/1.9.1/references/settings/
https://longhorn.io/docs/1.11.1/important-notes/
