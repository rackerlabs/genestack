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

!!! example "Run the redis-replication deployment Script `/opt/genestack/bin/install-redis-replication.sh`."

    ``` shell
    --8<-- "bin/install-redis-replication.sh"
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

## Monitoring Redis and Redis Sentinel

Genestack ships two Grafana dashboards for Redis:

- `etc/grafana-dashboards/redis_metrics.json` — **Redis Overview** (replication cluster health).
- `etc/grafana-dashboards/redis_sentinel_metrics.json` — **Redis Sentinel** (Sentinel and failover health).

The dashboards read the `redis_*` and `redis_sentinel_*` metrics from the redis_exporter,
which is **disabled by default** in the base overrides. To enable it, create user
override files under `/etc/genestack/helm-configs/` for each service:

=== "Enable redis-replication exporter"

    Create `/etc/genestack/helm-configs/redis-replication/redis-exporter-overrides.yaml`:

    ``` yaml
    redisExporter:
      enabled: true
      image: quay.io/opstree/redis-exporter
      tag: "v1.44.0"

    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s
      namespace: monitoring
    ```

=== "Enable redis-sentinel exporter"

    Create `/etc/genestack/helm-configs/redis-sentinel/redis-exporter-overrides.yaml`:

    ``` yaml
    redisExporter:
      enabled: true
      image: quay.io/opstree/redis-exporter
      tag: "v1.44.0"

    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s
      namespace: monitoring
    ```

Then re-run the install scripts to apply the overrides:

``` shell
/opt/genestack/bin/install-redis-replication.sh
/opt/genestack/bin/install-redis-sentinel.sh
```

!!! note

    Until the exporter and ServiceMonitor are enabled, the Redis dashboards will
    show "No Data".

Import the dashboards using the standard [Grafana dashboard import](monitoring-grafana.md) workflow.
