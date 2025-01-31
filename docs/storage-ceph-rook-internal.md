---
hide:
  - footer
---

# Rook (Ceph) - In Cluster

## Deploy the Rook operator

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-operator/
```

!!! tip "Manually specifying the rook-operator image"

    Under certain circumstances it may be required to do this, below is an
    example of how one can pin the operator version if so desired.

    ``` shell
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.13.7
    ```

## Deploy the Rook cluster

!!! note

    Rook will deploy against nodes labeled `role=storage-node`. Make sure to have a look at the `/etc/genestack/kustomize/rook-cluster/rook-cluster.yaml` file to ensure it's setup to your liking, pay special attention to your `deviceFilter` settings, especially if different devices have different device layouts.

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-cluster/
```

## Validate the cluster is operational

``` shell
kubectl --namespace rook-ceph get cephclusters.ceph.rook.io
```

!!! note

    You can track the deployment with the following command `kubectl --namespace rook-ceph get pods -w`.

## Create Storage Classes

Once the rook cluster is online with a HEALTH status of `HEALTH_OK`, deploy the filesystem, storage-class, and pool defaults.

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-defaults
```

!!! note

    If installing prometheus after rook-ceph is installed, you may patch a running rook-ceph cluster with the following command.

``` shell
kubectl -n rook-ceph patch CephCluster rook-ceph  --type=merge -p "{\"spec\": {\"monitoring\": {\"enabled\": true}}}"
```

Ensure you have 'servicemonitors' defined in the rook-ceph namespace.
