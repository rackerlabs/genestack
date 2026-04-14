### Longhorn Maintenance: 1.10.2 to 1.11.1

## Validation

Kubernetes 1.33.4 satisfies the published Longhorn minimum of Kubernetes v1.25+.
Upstream explicitly supports upgrading Longhorn v1.11.1 from v1.10.x.
The latest stable 1.11.x release is 1.11.1.
Upstream recommends manual checks before upgrade. Ensure no important volume is faulted, avoid failed BackingImage objects, and create a Longhorn system backup first.

## Goal

Upgrade Longhorn from 1.10.2 to 1.11.1 while preserving the storage-node placement restrictions already introduced in earlier maintenance.

## Prep

# Deployment Node

Confirm current health:
    kubectl version
    kubectl -n longhorn-system get pods -o wide
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness
    kubectl -n longhorn-system get backingimages.longhorn.io

Confirm selector settings are still correct:
    kubectl get nodes -L longhorn.io/storage-node
    kubectl -n longhorn-system get settings.longhorn.io system-managed-components-node-selector -o yaml

Optional but recommended. Create a Longhorn system backup before the hop.
Longhorn UI -> System Backup
Create
Wait for backup completion before upgrading

## Execute

# Bump the Chart Version

Edit /etc/genestack/helm-chart-versions.yaml:
    # charts:
    #   longhorn: 1.11.1

Retain the node-selector override file:
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

# Execute the Upgrade

Run the upgrade:
    /opt/genestack/bin/install-longhorn.sh

## Post-Maint

Confirm all Longhorn pods are healthy and scheduled only on labeled nodes:
    kubectl -n longhorn-system get pods -o wide --sort-by=.spec.nodeName

Confirm Longhorn settings survived the hop:
    kubectl -n longhorn-system get settings.longhorn.io system-managed-components-node-selector -o yaml

Confirm all volumes remain healthy:
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

Confirm no failed pre-upgrade checks were recorded:
    kubectl -n longhorn-system get events --sort-by=.lastTimestamp | tail -n 40

## Sources

https://longhorn.io/docs/1.11.1/deploy/upgrade/longhorn-manager/
https://longhorn.io/docs/1.11.1/important-notes/
https://github.com/longhorn/longhorn
