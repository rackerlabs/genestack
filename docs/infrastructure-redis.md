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

Redis metrics are collected by the **native OpenTelemetry redis receiver**, not by a
redis_exporter sidecar. The receiver issues the Redis `INFO` command against each
discovered pod and converts the response into `redis.*` metrics, which the collector's
`prometheusremotewrite` exporter writes into Prometheus as `redis_*` series.

This keeps Redis consistent with the other infrastructure services in Genestack
(memcached, MariaDB, RabbitMQ), where collection is defined entirely in the
OpenTelemetry collector configuration rather than in per-service exporters.

### How collection is wired

Everything lives in
`base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-overrides.yaml`:

| Component | Purpose |
|---|---|
| `receiver_creator/redis` | Discovers the `redis-replication-<n>` pods and scrapes `INFO` on port `6379`. |
| `receiver_creator/redis_sentinel` | Discovers the `redis-sentinel-sentinel-<n>` pods and scrapes the Sentinel `INFO` on port `26379`. |
| `tcpcheck` | Connects to each Redis and Sentinel member to provide the up/down signal, replacing the exporter's `redis_up` gauge. |
| `transform/redis_labels` | Projects pod metadata onto the datapoints as the `namespace`, `pod`, `redis_server` and `redis_component` labels. |
| `transform/redis_tcpcheck_labels` | Derives the same `namespace` / `pod` / `redis_component` labels for the `tcpcheck` series. |

Both receivers are discovered through the `k8s_observer` extension, which is scoped to
the `openstack` and `redis-systems` namespaces.

!!! note

    The discovery rules match on **pod** endpoints (`type == "pod"`) and append the
    Redis port explicitly, rather than matching on a container port. This is
    deliberate: the redis-operator only declares a `containerPort` on the Redis
    container when `hostPort` is set, which Genestack does not configure, so there are
    no `type == "port"` endpoints for `6379`/`26379` to match against. A rule written
    against `port` silently discovers nothing.

    If you rename the Redis custom resources or change the replica count, update the
    `name matches` expressions in the two `receiver_creator` blocks and the `tcpcheck`
    target list to match your environment. You can confirm the pod and
    headless-service names with:

    ``` shell
    kubectl --namespace redis-systems get pods,svc
    ```

### Verifying collection

After the collector rolls out, confirm the receivers are producing data:

``` shell
# the collector logs the receivers it started for each discovered endpoint
kubectl --namespace monitoring logs -l app.kubernetes.io/name=opentelemetry-kube-stack-deployment-collector \
  | grep -Ei 'redis|tcpcheck'
```

Then confirm the series landed in Prometheus, for example by querying
`redis_uptime_seconds_total`, `redis_sentinel_masters` and `tcpcheck_status_ratio`.

### Dashboards

Genestack ships two Grafana dashboards, both written against the OpenTelemetry metric
names:

- `etc/grafana-dashboards/redis_metrics.json` — **Redis Overview** (replication cluster health).
- `etc/grafana-dashboards/redis_sentinel_metrics.json` — **Redis Sentinel** (Sentinel health).

Import them using the standard [Grafana dashboard import](monitoring-grafana.md) workflow.

### Metric name changes

If you have existing alerts or dashboards written against redis_exporter metric names,
note that the OpenTelemetry receiver uses the OpenTelemetry semantic names, which the
remote-write exporter normalizes differently:

| redis_exporter | OpenTelemetry redis receiver |
|---|---|
| `redis_up` | `tcpcheck_status_ratio` (from the `tcpcheck` receiver) |
| `redis_connected_clients` | `redis_clients_connected` |
| `redis_connected_slaves` | `redis_slaves_connected` |
| `redis_uptime_in_seconds` | `redis_uptime_seconds_total` |
| `redis_evicted_keys_total` | `redis_keys_evicted_total` |
| `redis_memory_max_bytes` | `redis_maxmemory_bytes` |
| `redis_instance_info{role="master"}` | `redis_role{role="primary"}` |
| `redis_memory_used_bytes` | `redis_memory_used_bytes` (unchanged) |
| `redis_db_keys` | `redis_db_keys` (unchanged) |
| `redis_commands_processed_total` | `redis_commands_processed_total` (unchanged) |
| `redis_keyspace_hits_total` / `redis_keyspace_misses_total` | unchanged |
| `redis_sentinel_masters` | `redis_sentinel_masters` (unchanged) |

### Sentinel coverage limitation

The OpenTelemetry redis receiver only parses the Sentinel `INFO` output. It does **not**
issue the `SENTINEL masters` command, so the following per-master series that
redis_exporter provides have **no receiver equivalent**:

- `redis_sentinel_master_status`
- `redis_sentinel_master_ok_sentinels`
- `redis_sentinel_master_ok_slaves`
- `redis_sentinel_master_slaves`
- `redis_sentinel_known_sentinels`

In their place the Sentinel dashboard reports the Sentinel-level health signals the
receiver does provide: masters monitored, TILT state and TILT event rate, and the
script queue depth.

If you specifically need the per-master quorum and failover detail, you can enable the
redis_exporter sidecar alongside the OpenTelemetry receiver by creating
`/etc/genestack/helm-configs/redis-sentinel/redis-exporter-overrides.yaml`:

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

Then re-run the installer:

``` shell
/opt/genestack/bin/install-redis-sentinel.sh
```
