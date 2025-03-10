# Background

By default, _Genestack_ creates a pod that runs _OVN_ snapshots daily in the `kube-system` namespace where you find other centralized _OVN_ things. These get stored on a persistent storage volume associated with the `ovndb-backup` _PersistentVolumeClaim_. Snapshots older than 30 days get deleted.

You should primarily follow the [Kube-OVN documentation on backup and recovery](https://kubeovn.github.io/docs/stable/en/ops/recover-db/) and consider the information here supplementary.

## Backup

A default _Genestack_ installation creates a _k8s_ _CronJob_ in the `kube-system` namespace along side the other central OVN components that will store snapshots of the OVN NB and SB in the _PersistentVolume_ for the _PersistentVolumeClaim_ named `ovndb-backup`. Storing these on the persistent volume like this matches the conventions for _MariaDB_ in _Genestack_.

## Restoration and recovery

You may wish to implement shipping these off of the cluster to a permanent location, as you might have cluster problems that could interfere with your ability to get these off of the _PersistentVolume_ when you need these backups.

### Recovering when a majority of OVN DB nodes work fine

If you have a majority of _k8s_ nodes running `ovn-central` working fine, you can just follow the directions in the _Kube-OVN_ documentation for kicking a node out. Things mostly work normally when you have a majority because OVSDB HA uses a raft algorithm which only requires a majority of the nodes for full functionality, so you don't have to do anything too strange or extreme to recover. You essentially kick the bad node out and let it recover.

### Recovering from a majority of OVN DB node failures or a total cluster failure

**You probably shouldn't use this section if you don't have a majority OVN DB node failure. Just kick out the minority of bad nodes as indicated above instead**. Use this section to recover from a failure of the **majority** of nodes.

As a first step, you will need to get database files to run the recovery. You can try to use files on your nodes as described below, or use one of the backup snapshots.

#### Trying to use _OVN_ DB files in `/etc/origin/ovn` on the _k8s_ nodes

You can use the information in this section to try to get the files to use for your recovery from your running _k8s_ nodes.

The _Kube-OVN_ shows trying to use _OVN_ DB files from `/etc/origin/ovn` on the _k8s_ nodes. You can try this, or skip this section and use a backup snapshot as shown below if you have one. However, you can probably try to use the files on the nodes as described here first, and then switch to the latest snapshot backup from the `CronJob` later if trying to use the files on the _k8s_ nodes doesn't seem to work, since restoring from the snapshot backup fully rebuilds the database.

The directions in the _Kube-OVN_ documentation use `docker run` to get a working `ovsdb-tool` to try to work with the OVN DB files on the nodes, but _k8s_ installations mostly use `CRI-O`, `containerd`, or other container runtimes, so you probably can't pull the image and run it with `docker` as shown. I will cover this and some alternatives below.

##### Finding the first node

The _Kube-OVN_ documentation directs you to pick the node running the `ovn-central` pod associated with the first IP of the `NODE_IPS` environment variable. You should find the `NODE_IPS` environment variable defined on an `ovn-central` pod or the `ovn-central` _Deployment_. Assuming you can run the `kubectl` commands, the following example gets the node IPs off of one of the the deployment:

``` shell
kubectl get deployment -n kube-system ovn-central  -o yaml | grep -A1 'name: NODE_IPS'

        - name: NODE_IPS
          value: 10.130.140.246,10.130.140.250,10.130.140.252
```

Then find the _k8s_ node with the first IP. You can see your _k8s_ nodes and their IPs with the command `kubectl get node -o wide`:

``` shell
kubectl get node -o wide | grep 10.130.140.246

k8s-controller01   Ready      control-plane   3d17h   v1.28.6   10.130.140.246   <none>        Ubuntu 22.04.3 LTS   6.5.0-17-generic    containerd://1.7.11
root@k8s-controller01:~#
```

##### Trying to create a pod for `ovsdb-tool`

As an alternative to `docker run` since your _k8s_ cluster probably doesn't use _Docker_ itself, you can **possibly** try to create a pod instead of running a container directly, but you should **try it before scaling your _OVN_ replicas down to 0**, as not having `ovn-central` available should interfere with pod creation. The broken `ovn-central` might still prevent _k8s_ from creating the pod even if you haven't scaled your replicas down, however.

**Read below the pod manifest for edits you may need to make**

``` yaml
apiVersion: v1
kind: Pod
metadata:
  name: ovn-central-kubectl
  namespace: kube-system
spec:
  serviceAccount: "ovn"
  serviceAccountName: "ovn"
  nodeName: <full name first _k8s_ node from NODE_IPS>
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: "Exists"
    effect: "NoSchedule"
  volumes:
  - name: host-config-ovn
    hostPath:
      path: /etc/origin/ovn
      type: ""
  - name: backup
    persistentVolumeClaim:
      claimName: ovndb-backup
  containers:
  - name: ovn-central-kubectl
    command:
      - "/usr/bin/sleep"
    args:
      - "infinity"
    image: docker.io/kubeovn/kube-ovn:v1.12.30
    volumeMounts:
    - mountPath: /etc/ovn
      name: host-config-ovn
    - mountPath: /backup
      name: backup
```

You also have to make sure to get the pod on the _k8s_ node with the first IP of `NODE_IPS` from your `ovn-central` installation, as the _Kube-OVN_ documentation indicates, so see the section on "finding the first node" above to fill in `<full name first _k8s_ node from NODE_IPS>` in the example pod manifest above.

You can save this to a YAML file, and `kubectl apply -f <file>`.

You may need to delete the `backup` stuff under `.spec.volumes` and `.spec.containers[].volumeMounts` if you don't have that volume (although a default _Genestack_ installation does the scheduled snapshots there) or trying to use it causes problems, but if it works, you can possibly `kubectl cp` a previous backup off it to restore.

Additionally, you may need to delete the tolerations in the manifest if you untainted your controllers.

To reiterate, if you reached this step, this pod creation may not work because of your `ovn-central` problems, but a default `Genestack` can't `docker run` the container directly as shown in the `Kube-OVN` documentation because it probably uses _containerd_ instead of _Docker_. I tried creating a pod like this with `ovn-central` scaled to 0 pods, and the pod stays in `ContainerCreating` status.

If creating this pod worked, **scale your replicas to 0**, use `ovsdb-tool` to make the files you will use for restore (both north and south DB), then jump to _Full Recovery_ as described below here and in the _Kube-OVN_ documentation.

##### `ovsdb-tool` from your Linux distribution's packaging system

As an alternative to the `docker run`, which may not work on your cluster, and the pod creation, which may not work because of your broken OVN, if you still want to try to use the OVN DB files on your _k8s_ nodes instead of going to one of your snapshot backups, you can try to install your distribution's package with the `ovsdb-tool`, `openvswitch-common` on Ubuntu, although you risk (and will probably have) a slight version mismatch with the OVS version within your normal `ovn-central` pods. OVSDB has a stable format and this likely will not cause any problems, although you should probably restore a previously saved snapshot in preference to using an `ovsdb-tool` with a slightly mismatched version, but you may consider using the mismatch version if you don't have other options.

##### Conclusion of using the OVN DB files on your _k8s_ nodes

The entire section on using the OVN DB files from your nodes just gives you an alternative way to a planned snapshot backup to try to get something to restore the database from. From here forward, the directions converge with full recovery as described below and in the full _Kube-OVN_ documentation.

#### Full recovery

You start here when you have north database and south database files you want to use to run your recovery, whether you retrieved it from one of your _k8s_ nodes as described above, or got it from one of your snapshots. Technically, the south database should get rebuilt with only the north database, but if you have the two that go together, you can save the time it would take for a full rebuild by also restoring the south DB. It also avoids relying on the ability to rebuild the south DB in case something goes wrong.

If you just have your _PersistentVolume_ with the snapshots, you can try to create a pod as shown in the example manifest above with the _PersistentVolume_ mounted and `kubectl cp` the files off.

However you got the files, full recovery from here forward works exactly as described in the _Kube-OVN_ documentation, which at a high level, starts with you scaling your replicas down to 0.
