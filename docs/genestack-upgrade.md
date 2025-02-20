# Updating the Genestack

Running a genestack upgrade is fairly simple and consists of mainly updating the `git` checkout and then running through the needed `helm` charts to deploy updated applications.

## Change to the genestack directory

``` shell
cd /opt/genestack
```

Fetch the latest checkout from your remote.

``` shell
git fetch origin
git rebase origin/main
```

!!! tip

    You may want to checkout a specific SHA or tag when running a stable environment.

## Update the submodules

``` shell
git pull --recurse-submodules
```

## Updating the genestack applications

An update is generally the same as an install. Many of the Genestack applications are governed by operators which include lifecycle management.

* When needing to run an upgrade for the infrastructure operators, consult the operator documentation to validate the steps required.
* When needing to run an upgrade for the OpenStack components, simply re-run the `helm` charts as documented in the Genestack installation process.

!!! note "Before running upgrades, make sure cached charts are cleaned up"

    ``` shell
    find /etc/genestack/kustomize/ -name charts -type d -exec rm -rf {} \;
    ```

## Kubernetes Upgrade Notes

Over the course of normal operations it's likely that a CRD will change versions, names, or something else. In these cases, should an operator or helm chart not gracefully handle an full upgrade, the `kubectl convert` plugin can be used to make some adjustments where needed.

!!! example "Converting mmontes CRDs to mariadb official ones"

    ``` shell
    kubectl get --namespace openstack crd.namespace -o yaml value > /tmp/value.crd.namespace.yaml
    kubectl convert -f /tmp/value.crd.namespace.yaml --output-version new-namespace/VERSION
    ```

!!! example "Cleaning up nova jobs before upgrading"

    ``` shell
    kubectl --namespace openstack delete jobs $(kubectl --namespace openstack get jobs --no-headers -o custom-columns=":metadata.name" | grep nova)
    ```

## Kubernetes Finalizers

When processing an upgrade there may come a time when a finalizer is stuck, typically something that happens when an operator or an api reference is changed. If this happens one way to resolve the issue is to patch the Finalizers.

!!! warning

    Patching Finalizers could leave orphaned resources. Before patching a finalizer be sure your "ready."

!!! example "Patching Finalizers"

    ``` shell
    kubectl patch $@ --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
    ```
