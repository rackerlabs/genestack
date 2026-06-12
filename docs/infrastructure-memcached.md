# Deploy a Memcached

## Deploy the Memcached Cluster

!!! example "Run the memcached deployment Script You can include paramaters to deploy aio or base-monitoring. No paramaters deploys base"

    ``` shell
    /opt/genestack/bin/install.sh --service memcached
    ```

!!! note

    Memcached has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

## Verify readiness with the following command

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```
