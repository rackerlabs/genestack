# Deploy the MariaDB Operator and Mariadb Cluster

## Create secret

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic mariadb \
                --type Opaque \
                --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Deploy the mariadb operator

```
cluster_name=`kubectl config view --minify -o jsonpath='{.clusters[0].name}'`
echo $cluster_name
```

If `cluster_name` was anything other than `cluster.local` you should pass that as a parameter to the installer

!!! example "Run the mariadb-operator deployment Script `bin/install-mariadb-operator.sh` You can include cluster_name paramater. No paramaters deploys with `cluster.local` cluster name."

    ``` shell
    --8<-- "bin/install-mariadb-operator.sh"
    ```

!!! info

    The operator may take a minute to get ready, before deploying the Galera cluster, wait until the webhook is online.

``` shell
kubectl --namespace mariadb-system get pods -w
```

## Deploy the MariaDB Cluster

!!! note

    MariaDB has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

=== "Replication _(Recommended)_"

    Replication in MariaDB involves synchronizing data between a primary database and one or more replicas, enabling continuous data availability even in the event of hardware failures or outages. By using MariaDB replication, OpenStack deployments can achieve improved fault tolerance and load balancing, ensuring that critical cloud services remain operational and performant at all times.

    ``` shell
    kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
    ```

=== "AIO"

    In some OpenStack deployments, a single MariaDB server is used to manage the database needs of the cloud environment. While this setup is simpler and easier to manage than clustered solutions, it is typically suited for smaller environments or use cases where high availability and fault tolerance are not critical. A single MariaDB server provides a centralized database service for storing and managing the operational data of OpenStack components, ensuring consistent performance and straightforward management. However, it is important to recognize that this configuration presents a single point of failure, making it less resilient to outages or hardware failures compared to more robust, multi-node setups.

    ``` shell
    kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/aio
    ```

## Verify readiness with the following command

``` shell
kubectl --namespace openstack get mariadbs -w
```
