---
hide:
  - footer
---

# Cephadm/ceph-ansible/Rook (Ceph) - External

We can use an external ceph cluster and present it via rook-ceph to your cluster.

## Prepare pools on external cluster

``` shell
ceph osd pool create general 32
ceph osd pool create general-multi-attach-data 32
ceph osd pool create general-multi-attach-metadata 32
rbd pool init general
ceph fs new general-multi-attach general-multi-attach-metadata general-multi-attach-data
```

!!! info

    You must have a MDS service running, in this example I am tagging my 3 ceph nodes with MDS labels and creating a MDS service for the general-multi-attach Cephfs Pool

``` shell
ceph orch host label add genestack-ceph1 mds
ceph orch host label add genestack-ceph2 mds
ceph orch host label add genestack-ceph3 mds
ceph orch apply mds myfs label:mds
```

!!! note

    From your ceph deploymenty node, We will now download create-external-cluster-resources.py and create exports to run on your controller node. Using cephadm in this example:

``` shell
./cephadm shell
yum install wget -y ; wget https://raw.githubusercontent.com/rook/rook/release-1.16/deploy/examples/create-external-cluster-resources.py
python3 create-external-cluster-resources.py --rbd-data-pool-name general --cephfs-filesystem-name general-multi-attach --namespace rook-ceph-external --format bash
```

!!! example "Example create-external-cluster-resources.py output"

    The script generates a lot of output, you will need to capture all of the exports. These exports will be used in the next command.  Copy these exports to your genestack deployment node.

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

Run the following commands to import the cluster after pasting in exports from external cluster

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-operator/
/opt/genestack/scripts/import-external-cluster.sh
helm repo add rook-release https://charts.rook.io/release
kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.13.7
wget https://raw.githubusercontent.com/rook/rook/refs/tags/v1.16.5/deploy/charts/rook-ceph-cluster/values-external.yaml -O /etc/genestack/helm-configs/rook-values-external.yaml
helm install --create-namespace --namespace rook-ceph-external rook-ceph-cluster --set operatorNamespace=rook-ceph rook-release/rook-ceph-cluster -f /etc/genestack/helm-configs/rook-values-external.yaml
kubectl patch storageclass general -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Monitor progress

``` shell
kubectl --namespace rook-ceph-external get cephcluster -w
```

## Validate the Connection

When the monitor shows the message "Cluster connected successfully" the cluster is connected and ready for use.

``` shell
NAME                 DATADIRHOSTPATH   MONCOUNT   AGE     PHASE       MESSAGE                          HEALTH      EXTERNAL   FSID
rook-ceph-external   /var/lib/rook     3          3m24s   Connected   Cluster connected successfully   HEALTH_OK   true       d45869e0-ccdf-11ee-8177-1d25f5ec2433
```
