---
hide:
  - footer
---

# NFS - External

While NFS in K8S works great, it's not suitable for use in all situations.

!!! warning

    NFS is officially not supported by MariaDB and will fail to initialize the database backend when running on NFS.

In Genestack, the `general` storage class is used by default for systems like RabbitMQ and MariaDB. If you intend to use NFS, you will need to ensure your use cases match the workloads and may need to make some changes within the manifests.

## Install Base Packages

NFS requires utilities to be installed on the host. Before you create workloads that require NFS make sure you have `nfs-common` installed on your target storage hosts (e.g. the controllers).

### Add the NFS Provisioner Helm repo

``` shell
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
```

## Install External NFS Provisioner

This command will connect to the external storage provider and generate a storage class that services the `general` storage class.

``` shell
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace nfs-provisioner \
    --create-namespace \
    --set nfs.server=172.16.27.67 \
    --set nfs.path=/mnt/storage/k8s \
    --set nfs.mountOptions={"nolock"} \
    --set storageClass.defaultClass=true \
    --set replicaCount=1 \
    --set storageClass.name=general \
    --set storageClass.provisionerName=nfs-provisioner-01
```

This command will connect to the external storage provider and generate a storage class that services the `general-multi-attach` storage class.

``` shell
helm install nfs-subdir-external-provisioner-multi nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace nfs-provisioner \
    --create-namespace \
    --set nfs.server=172.16.27.67 \
    --set nfs.path=/mnt/storage/k8s \
    --set nfs.mountOptions={"nolock"} \
    --set replicaCount=1 \
    --set storageClass.name=general-multi-attach \
    --set storageClass.provisionerName=nfs-provisioner-02 \
    --set storageClass.accessModes=ReadWriteMany
```
