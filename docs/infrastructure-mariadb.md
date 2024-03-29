# Deploy the MariaDB Operator and a Galera Cluster

## Create secret

``` shell
# MariaDB
kubectl --namespace openstack \
        create secret generic mariadb \
        --type Opaque \
        --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"

# MaxScale
kubectl --namespace openstack \
        create secret generic maxscale \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

## Deploy the mariadb operator

``` shell
cluster_name=`kubectl config view --minify -o jsonpath='{.clusters[0].name}'`
sed -i -e "s/cluster\.local/$cluster_name/" /opt/genestack/kustomize/mariadb-operator/kustomization.yaml

test -n "$cluster_name" && kubectl kustomize --enable-helm /opt/genestack/kustomize/mariadb-operator | \
  kubectl --namespace mariadb-system apply --server-side --force-conflicts -f -
```

!!! info

    The operator may take a minute to get ready, before deploying the Galera cluster, wait until the webhook is online.

``` shell
kubectl --namespace mariadb-system get pods -w
```

## Deploy the MariaDB Cluster

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
