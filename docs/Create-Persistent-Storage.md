# Persistent Storage Demo

[![asciicast](https://asciinema.org/a/629785.svg)](https://asciinema.org/a/629785)

# Deploying Your Persistent Storage

For the basic needs of our Kubernetes environment, we need some basic persistent storage. Storage, like anything good in life,
is a choose your own adventure ecosystem, so feel free to ignore this section if you have something else that satisfies the need.

The basis needs of Genestack are the following storage classes

* general - a general storage cluster which is set as the deault.
* general-multi-attach - a multi-read/write storage backend

These `StorageClass` types are needed by various systems; however, how you get to these storage classes is totally up to you.
The following sections provide a means to manage storage and provide our needed `StorageClass` types.

> The following sections are not all needed; they're just references.

## Rook (Ceph) - In Cluster

### Deploy the Rook operator

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-operator/
```

### Deploy the Rook cluster

> [!IMPORTANT]
> Rook will deploy against nodes labeled `role=storage-node`. Make sure to have a look at the `/opt/genestack/kustomize/rook-cluster/rook-cluster.yaml` file to ensure it's setup to your liking, pay special attention to your `deviceFilter`
settings, especially if different devices have different device layouts.

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-cluster/
```

### Validate the cluster is operational

``` shell
kubectl --namespace rook-ceph get cephclusters.ceph.rook.io
```

> You can track the deployment with the following command `kubectl --namespace rook-ceph get pods -w`.

### Create Storage Classes

Once the rook cluster is online with a HEALTH status of `HEALTH_OK`, deploy the filesystem, storage-class, and pool defaults.

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-defaults
```
> [!IMPORTANT]
> If installing prometheus after rook-ceph is installed, you may patch a running rook-ceph cluster with the following command:
``` shell
kubectl -n rook-ceph patch CephCluster rook-ceph  --type=merge -p "{\"spec\": {\"monitoring\": {\"enabled\": true}}}"
```
Ensure you have 'servicemonitors' defined in the rook-ceph namespace.


## Cephadm/ceph-ansible/Rook (Ceph) - External

We can use an external ceph cluster and present it via rook-ceph to your cluster.

### Prepare pools on external cluster

``` shell
ceph osd pool create general 32
ceph osd pool create general-multi-attach-data 32
ceph osd pool create general-multi-attach-metadata 32
rbd pool init general
ceph fs new general-multi-attach general-multi-attach-metadata general-multi-attach-data
```

### You must have a MDS service running, in this example I am tagging my 3 ceph nodes with MDS labels and creating a MDS service for the general-multi-attach Cephfs Pool

``` shell
ceph orch host label add genestack-ceph1 mds
ceph orch host label add genestack-ceph2 mds
ceph orch host label add genestack-ceph3 mds
ceph orch apply mds myfs label:mds
```

### We will now download create-external-cluster-resources.py and create exports to run on your controller node. Using cephadm in this example:

``` shell
./cephadm shell
yum install wget -y ; wget https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/create-external-cluster-resources.py
python3 create-external-cluster-resources.py --rbd-data-pool-name general --cephfs-filesystem-name general-multi-attach --namespace rook-ceph-external --format bash
```
### Copy and paste the output, here is an example:
``` shell
root@genestack-ceph1:/# python3 create-external-cluster-resources.py --rbd-data-pool-name general --cephfs-filesystem-name general-multi-attach --namespace rook-ceph-external --format bash
export NAMESPACE=rook-ceph-external
export ROOK_EXTERNAL_FSID=d45869e0-ccdf-11ee-8177-1d25f5ec2433
export ROOK_EXTERNAL_USERNAME=client.healthchecker
export ROOK_EXTERNAL_CEPH_MON_DATA=genestack-ceph1=10.1.1.209:6789
export ROOK_EXTERNAL_USER_SECRET=AQATh89lf5KiBBAATgaOGAMELzPOIpiCg6ANfA==
export ROOK_EXTERNAL_DASHBOARD_LINK=https://10.1.1.209:8443/
export CSI_RBD_NODE_SECRET=AQATh89l3AJjBRAAYD+/cuf3XPdMBmdmz4iWIA==
export CSI_RBD_NODE_SECRET_NAME=csi-rbd-node
export CSI_RBD_PROVISIONER_SECRET=AQATh89l9dH4BRAApBKzqwtaUqw9bNcBI/iGGw==
export CSI_RBD_PROVISIONER_SECRET_NAME=csi-rbd-provisioner
export CEPHFS_POOL_NAME=general-multi-attach-data
export CEPHFS_METADATA_POOL_NAME=general-multi-attach-metadata
export CEPHFS_FS_NAME=general-multi-attach
export CSI_CEPHFS_NODE_SECRET=AQATh89lFeqMBhAAJpHAE5vtukXYuRj2+WTh2g==
export CSI_CEPHFS_PROVISIONER_SECRET=AQATh89lHB0dBxAA7CHM/9rTSs79SLJSKVBYeg==
export CSI_CEPHFS_NODE_SECRET_NAME=csi-cephfs-node
export CSI_CEPHFS_PROVISIONER_SECRET_NAME=csi-cephfs-provisioner
export MONITORING_ENDPOINT=10.1.1.209
export MONITORING_ENDPOINT_PORT=9283
export RBD_POOL_NAME=general
export RGW_POOL_PREFIX=default
```

### Run the following commands to import the cluster after pasting in exports from external cluster
``` shell
kubectl apply -k /opt/genestack/kustomize/rook-operator/
/opt/genestack/scripts/import-external-cluster.sh
helm repo add rook-release https://charts.rook.io/release
helm install --create-namespace --namespace rook-ceph-external rook-ceph-cluster     --set operatorNamespace=rook-ceph rook-release/rook-ceph-cluster -f /opt/genestack/submodules/rook/deploy/charts/rook-ceph-cluster/values-external.yaml
kubectl patch storageclass general -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Monitor progress:
``` shell
kubectl --namespace rook-ceph-external get cephcluster -w
```

### Should return when finished:
``` shell
NAME                 DATADIRHOSTPATH   MONCOUNT   AGE     PHASE       MESSAGE                          HEALTH      EXTERNAL   FSID
rook-ceph-external   /var/lib/rook     3          3m24s   Connected   Cluster connected successfully   HEALTH_OK   true       d45869e0-ccdf-11ee-8177-1d25f5ec2433
```



## NFS - External

While NFS in K8S works great, it's not suitable for use in all situations.

> Example: NFS is officially not supported by MariaDB and will fail to initialize the database backend when running on NFS.

In Genestack, the `general` storage class is used by default for systems like RabbitMQ and MariaDB. If you intend to use NFS, you will need to ensure your use cases match the workloads and may need to make some changes within the manifests.

### Install Base Packages

NFS requires utilities to be installed on the host. Before you create workloads that require NFS make sure you have `nfs-common` installed on your target storage hosts (e.g. the controllers).

### Add the NFS Provisioner Helm repo

``` shell
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
```

### Install External NFS Provisioner

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

## TopoLVM - In Cluster

[TopoLVM](https://github.com/topolvm/topolvm) is a capacity aware storage provisioner which can make use of physical volumes.\
The following steps are one way to set it up, however, consult the [documentation](https://github.com/topolvm/topolvm/blob/main/docs/getting-started.md) for a full breakdown of everything possible with TopoLVM.

### Create the target volume group on your hosts

TopoLVM requires access to a volume group on the physical host to work, which means we need to set up a volume group on our hosts. By default, TopoLVM will use the controllers as storage hosts. The genestack Kustomize solution sets the general storage volume group to `vg-general`. This value can be changed within Kustomize found at `kustomize/topolvm/general/kustomization.yaml`.

> Simple example showing how to create the needed volume group.

``` shell
# NOTE sdX is a placeholder for a physical drive or partition.
pvcreate /dev/sdX
vgcreate vg-general /dev/sdX
```

Once the volume group is on your storage nodes, the node is ready for use.

### Deploy the TopoLVM Provisioner

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/topolvm/general | kubectl apply -f -
```
