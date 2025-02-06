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

Create the secret:

``` shell
kubectl --namespace openstack \
        create secret generic etcd-backup-secrets \
        --type Opaque \
        --from-literal=ACCESS_KEY="sadbq4bcva2392dasflkdsp" \
        --from-literal=SECRET_KEY="aldskflkjpoq32ibdsfko23bnalkfdao2" \
        --from-literal=S3_HOST="127.0.0.1" \
        --from-literal=S3_REGION="SJC3" \
        --from-literal=ETCDCTL_API="3" \
        --from-literal=ETCDCTL_ENDPOINTS="https://127.0.0.1:2379" \
        --from-literal=ETCDCTL_CACERT="/etc/ssl/etcd/ssl/ca.pem" \
        --from-literal=ETCDCTL_CERT="/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld.pem" \
        --from-literal=ETCDCTL_KEY="/etc/ssl/etcd/ssl/member-etcd01.your.domain.tld-key.pem"
```

!!! note

    Make sure to use the correct values for your region.

Next, Deploy the backup job:

```
kubectl apply -k /etc/genestack/kustomize/backups/etcd/etcd-backup.yaml --namespace openstack
```
