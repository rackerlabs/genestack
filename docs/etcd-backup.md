# Etcd Backup

In order to backup etcd we create a backup CronJob resource. This constitues of 3 things:

1. etcd-backup container image with the etcdctl binary and the python script that uploads
the backup to Ceph S3 endpoint or any S3 compatible endpoint.

2. The CronJob deployment resource. This job will only be done on the box with label set
matching is-etcd-backup-enabled.

3. Secrets required for the backup to function. These include the location of the
S3 endpoint, access keys, and etcd certs to access etcd endpoints.

Label one or more box in the cluster to run the job:

```
kubectl label node etcd01.your.domain.tld is-etcd-backup-node=true
```

Populate the backup secret:

!!! note "Information about the secrets used"

    The infrastructure install creates the backup Secret if it is missing and reuses existing values when rerun.
    However, you still need to add data to the empty keys that are region-specific. `S3_REGION` now defaults to an empty value and should be patched when your S3-compatible endpoint requires a region.

!!! note

    Ensure that the correct ETCD and S3 connection information is patched into the secret
    ```shell
       kubectl -n openstack patch secret etcd-backup-secrets \
       --patch='{"stringData": {"ETCDCTL_CERT":"/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld.pem",
                                "ETCDCTL_KEY":"/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld-key.pem",
                                "ACCESS_KEY": "<ACCESS KEY>", "SECRET_KEY": "<SECRET KEY>",
                                "S3_HOST": "<S3 ENDPOINT>", "S3_REGION": "<S3 REGION>"}}'
    ```

Next, deploy the backup job:

```shell
kubectl apply -k /etc/genestack/kustomize/backups/overlay --namespace openstack
```
