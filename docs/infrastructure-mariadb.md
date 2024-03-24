# Deploy the MariaDB Operator and a Galera Cluster

## Deploy the mariadb operator

If you've changed your k8s cluster name from the default cluster.local, edit `clusterName` in `/opt/genestack/kustomize/mariadb-operator/kustomization.yaml` prior to deploying the mariadb operator.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/mariadb-operator | \
  kubectl --namespace mariadb-system apply --server-side --force-conflicts -f -
```

!!! info

    The operator may take a minute to get ready, before deploying the Galera cluster, wait until the webhook is online.

``` shell
kubectl --namespace mariadb-system get pods -w
```

## Deploy the MariaDB Cluster

## Pre-requsites:

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/mariadb/` path in the Vault

## Create secrets in the vault:

### Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=mariadb
```

### List the existing secrets from `osh/mariadb/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/mariadb
```

### Create the secrets:

- Mariadb root-password:
``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/mariadb mariadb-root-password root-password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- MaxScale password:
``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/mariadb maxscale password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/mariadb
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/mariadb mariadb-root-password
```

## Install mariadb cluster:

- Ensure that the `vault-ca-secret` Kubernetes Secret exists in the OpenStack namespace containing the Vault CA certificate:
```shell
kubectl get secret vault-ca-secret -o yaml -n openstack
```

- If it is absent, create one using the following command:
```shell
kubectl create secret generic vault-ca-secret \
    --from-literal=ca.crt="$(kubectl get secret vault-tls-secret \
    -o jsonpath='{.data.ca\.crt}' -n vault | base64 -d -)" -n openstack
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the mariadb installation:
``` shell
kubectl apply -k /opt/genestack/kustomize/mariadb-cluster/base/vault
```

- Validate whether the required Kubernetes secrets from Vault are populated:
``` shell
kubectl get secrets -n openstack
```

### Deploy mariadb-cluster

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/mariadb-cluster/base
```

!!! note

    MariaDB has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

## Verify readiness with the following command

``` shell
kubectl --namespace openstack get mariadbs -w
```

## MaxScale

Within the deployment the OpenStack services use MaxScale for loadlancing and greater reliability. While the MaxScale ecosystem is a good one, there are some limitations that you should be aware of. It is recommended that you review the [MaxScale reference documentation](https://mariadb.com/kb/en/mariadb-maxscale-2302-limitations-and-known-issues-within-mariadb-maxscale) for more about all of the known limitations and potential workarounds available.

``` mermaid
flowchart TD
    A[Connection] ---B{MaxScale}
    B ---|ro| C[ES-0]
    B ---|rw| D[ES-1] ---|sync| E & C
    B ---|ro| E[ES-2]
```

### MaxScale GUI

The MaxScale deployment has access to a built in GUI that can be exposed for further debuging and visibility into the performance of the MariDB backend. For more information on accessing the GUI please refer to the MaxScale documentation that can be found [here](https://mariadb.com/resources/blog/getting-started-with-the-mariadb-maxscale-gui).
