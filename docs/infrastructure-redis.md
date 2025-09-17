# Deploy Redis Operator, Redis Replication Cluster and Redis Sentinel

## Deploy the Redis operator and replication cluster

Genestack primarily makes use of the popular opensource Redis in-memory database to support various services that utilize [Taskflow](https://wiki.openstack.org/wiki/TaskFlow) and [Jobboard](https://docs.openstack.org/taskflow/latest/user/jobs.html) functionality.
One such service is [Octavia](https://docs.openstack.org/octavia/latest/install/install-amphorav2.html), which uses Redis to track tasks across the Octavia cluster in a HA fashion ensuring that tasks can still be completed in the event of a partial outage of the Octavia system.

In order to take advantage of the Redis system in a HA way we deploy [Redis Replication](https://redis-operator.opstree.dev/docs/getting-started/replication/) and [Redis Sentinel](https://redis-operator.opstree.dev/docs/getting-started/sentinel/) to handle the needs of a clustered, HA Redis deployment. 

!!! tip
    As noted in the [Sentinel](https://redis-operator.opstree.dev/docs/getting-started/sentinel/) Docs we must deploy the Redis Operator and Replication cluster prior to deploying Sentinel. Below are the steps to achieve this.

```
CLUSTER_NAME=`kubectl config view --minify -o jsonpath='{.clusters[0].name}'`
echo $CLUSTER_NAME
```

If `cluster_name` was anything other than `cluster.local` you should pass that as a parameter to the installer

!!! example "Run the redis-operator deployment Script `/opt/genestack/bin/install-redis-operator.sh` You can include cluster_name paramater from the output of $CLUSTER_NAME. If no paramaters are provided, the system will deploy with `cluster.local` as the cluster name."

    ``` shell
    --8<-- "bin/install-redis-operator.sh"
    ```


## Verify Redis Operator and Replication cluster readiness with the following command

``` shell
kubectl --namespace redis-systems get pods -w
```

## Deploy the Redis Sentinel

!!! example "Run the redis-sentinel deployment Script `/opt/genestack/bin/install-redis-sentinel.sh`"

    ``` shell
    --8<-- "bin/install-redis-sentinel.sh"
    ```

## Verify Sentinel readiness with the following command

``` shell
kubectl --namespace redis-systems get pods -w
```
