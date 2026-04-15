### Longhorn Maintenance: 1.9.1 to 1.10.2

## Validation

Kubernetes 1.33.4 satisfies the published Longhorn minimum of Kubernetes v1.25+.
Upstream explicitly supports upgrading Longhorn v1.10.1 from v1.9.x. 1.10.2 is the latest stable 1.10.x patch.
This is the highest-risk hop because Longhorn v1.10 removes the longhorn.io/v1beta1 API and the deprecated replica.status.evictionRequested field.
Upstream documents a mandatory CRD stored-version migration and verification step before the 1.10 upgrade, and there is a real 1.33.4 field report showing upgrade failure when v1beta1 remained in CRD stored versions.

## Goal

Upgrade Longhorn from 1.9.1 to 1.10.2 only after confirming CRDs no longer store v1beta1 data.

## Prep

# Deployment Node

Confirm current version and cluster health:
    kubectl version
    kubectl -n longhorn-system get pods -o wide
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

Confirm node-selector settings still restrict Longhorn to storage nodes:
    kubectl get nodes -L longhorn.io/storage-node
    kubectl -n longhorn-system get settings.longhorn.io system-managed-components-node-selector -o yaml

Verify CRD stored versions before the upgrade:
    kubectl get crd -l app.kubernetes.io/name=longhorn -o=jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.storedVersions}{"\n"}{end}'

If every Longhorn CRD already shows only ["v1beta2"], skip the migration section and continue.

## Execute

# Required CRD Migration for the 1.10 Upgrade

Run the upstream migration procedure before the upgrade:
    kubectl patch validatingwebhookconfiguration longhorn-webhook-validator --type=merge -p "$(kubectl get validatingwebhookconfiguration longhorn-webhook-validator -o json | jq '.webhooks[0].rules |= map(if .apiGroups == ["longhorn.io"] and .resources == ["settings"] then .operations |= map(select(. != "UPDATE")) else . end)')"
    migration_time="$(date +%Y-%m-%dT%H:%M:%S)"
    crds=($(kubectl get crd -l app.kubernetes.io/name=longhorn -o json | jq -r '.items[] | select(.status.storedVersions | index("v1beta1")) | .metadata.name'))
    for crd in "${crds[@]}"; do
      echo "Migrating ${crd} ..."
      for name in $(kubectl -n longhorn-system get "$crd" -o jsonpath='{.items[*].metadata.name}'); do
        kubectl patch "${crd}" "${name}" -n longhorn-system --type=merge -p='{"metadata":{"annotations":{"migration-time":"'"${migration_time}"'"}}}'
      done
      kubectl patch crd "${crd}" --subresource=status --type=merge -p '{"status":{"storedVersions":["v1beta2"]}}'
    done

Verify migration success:
    kubectl get crd -l app.kubernetes.io/name=longhorn -o=jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.storedVersions}{"\n"}{end}'

Expected:
    # Every Longhorn CRD shows only ["v1beta2"]

Do not proceed until every Longhorn CRD shows only ["v1beta2"].

# Bump the Chart Version

Edit /etc/genestack/helm-chart-versions.yaml:
    # charts:
    #   longhorn: 1.10.2

Keep the same node-selector override file in /etc/genestack/helm-configs/longhorn/longhorn.yaml:
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

Confirm the pre-upgrade check did not fail:
    kubectl -n longhorn-system get events --sort-by=.lastTimestamp | tail -n 40

Confirm all Longhorn pods are running:
    kubectl -n longhorn-system get pods -o wide --sort-by=.spec.nodeName

Confirm CRDs still show only v1beta2:
    kubectl get crd -l app.kubernetes.io/name=longhorn -o=jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.storedVersions}{"\n"}{end}'

Expected:
    # Every Longhorn CRD shows only ["v1beta2"]

Confirm volumes are healthy:
    kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

## Troubleshooting

# Rollback Signal

If the upgrade fails with an error mentioning status.storedVersions[0]: Invalid value: "v1beta1", stop and roll back. That indicates the CRD migration was incomplete.

Helm rollback pattern:
    helm history longhorn -n longhorn-system
    # helm rollback longhorn <REVISION> -n longhorn-system

## Sources

https://longhorn.io/docs/1.10.1/deploy/upgrade/longhorn-manager/
https://longhorn.io/docs/1.10.0/important-notes/
https://longhorn.io/docs/1.11.1/important-notes/
https://github.com/longhorn/longhorn/issues/11886
