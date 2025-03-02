---
hide:
  - footer
---

# External Block - Bring Your Own Storage

For some Topo/Ceph/NFS are not great fits, Genestack allows for external block devices to be used in the stand up and operation of Openstack.

## Deploy External CSI driver in Genestack

Follow Documentation on getting a storage class presented to k8s, name it "general" and mark that storage class as default, in this example storage is provided by democratic csi driver over iscsi.

``` shell
(genestack) root@genestack-controller1:# kubectl get sc
NAME                   PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
general (default)      org.democratic-csi.iscsi        Delete          Immediate           true                   3h15m
```

!!! info

    OSD placement is done on nodes with label ‘openstack-control-plane’, a minimum of 3 nodes is required for a healthy Ceph cluster.

Deploy Ceph operator

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-operator/
kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.13.7
```

Deploy Ceph on PVC

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-cluster-external-pvc/
```

Monitor cluster state, once cluster HEALTH_OK proceed to the next step

``` shell
(genestack) root@genestack-controller1:# kubectl --namespace rook-ceph get cephclusters.ceph.rook.io
NAME        DATADIRHOSTPATH   MONCOUNT   AGE    PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          129m   Ready   Cluster created successfully   HEALTH_OK              9a6657cd-f3ab-4d70-b276-a05e2ca03e1b
```

Deploy cephfs filesystem named 'general-multi-attach' for Glance consumption

``` shell
kubectl apply -k /etc/genestack/kustomize/rook-defaults-external-pvc/
```

You should now have two storage class providers configured for Genestack

``` shell
(genestack) root@genestack-controller1:# kubectl get sc -A
NAME                   PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
general (default)      org.democratic-csi.iscsi        Delete          Immediate           true                   3h25m
general-multi-attach   rook-ceph.cephfs.csi.ceph.com   Delete          Immediate           true                   85m
```
