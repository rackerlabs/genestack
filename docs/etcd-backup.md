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

Create the `etcd-backup-secrets` secret with cluster-specific values:

```bash
kubectl --namespace openstack create secret generic etcd-backup-secrets \
    --type Opaque \
    --from-literal=ACCESS_KEY="<YOUR_ACCESS_KEY_ID>" \
    --from-literal=SECRET_KEY="<YOUR_SECRET_ACCESS_KEY>" \
    --from-literal=S3_HOST="<S3_ENDPOINT_HOST>" \
    --from-literal=S3_REGION="<S3_REGION>" \
    --from-literal=ETCDCTL_API="3" \
    --from-literal=ETCDCTL_ENDPOINTS="https://127.0.0.1:2379" \
    --from-literal=ETCDCTL_CACERT="/etc/ssl/etcd/ssl/ca.pem" \
    --from-literal=ETCDCTL_CERT="/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld.pem" \
    --from-literal=ETCDCTL_KEY="/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld-key.pem"
```

If the ETCD or S3 values change (e.g., different node names, region, CA cert path), apply the diff:

```bash
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
