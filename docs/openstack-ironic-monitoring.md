# OpenStack Ironic Monitoring

Genestack deploys `ironic-prometheus-exporter` alongside the OpenStack Ironic
conductors. The exporter converts Ironic hardware sensor data into Prometheus
metrics and exposes them on HTTP port `9608`. The OpenTelemetry deployment
collector discovers every ready exporter endpoint and forwards the collected
metrics to the monitoring backend.

This guide describes how Ironic monitoring is configured, enabled, and
validated in Genestack. For Ironic deployment and bare metal provisioning, see
[Deploy Ironic](openstack-ironic.md) and the
[OpenStack Ironic Operational Guide](openstack-ironic-operational-guide.md).

## Architecture

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                         Bare Metal Infrastructure                          │
│                                                                            │
│     ┌────────────────┐   ┌────────────────┐       ┌────────────────┐       │
│     │ Server BMC 1   │   │ Server BMC 2   │  ...  │ Server BMC N   │       │
│     │ IPMI / Redfish │   │ IPMI / Redfish │       │ IPMI / Redfish │       │
│     └────────┬───────┘   └────────┬───────┘       └────────┬───────┘       │
└──────────────┼────────────────────┼────────────────────────┼───────────────┘
               └────────────────────┼────────────────────────┘
                                    │ Sensor collection every 120 seconds
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         OpenStack Namespace                                │
│                                                                            │
│  ┌──────────────────────────────┐    ┌──────────────────────────────┐      │
│  │ Ironic Conductor Pod 1       │    │ Ironic Conductor Pod N       │      │
│  │                              │    │                              │      │
│  │  ironic-conductor            │    │  ironic-conductor            │      │
│  │         │                    │    │         │                    │      │
│  │         ▼                    │    │         ▼                    │      │
│  │  /var/lib/ironic/metrics     │    │  /var/lib/ironic/metrics     │      │
│  │         │                    │    │         │                    │      │
│  │         ▼                    │    │         ▼                    │      │
│  │  exporter sidecar :9608      │    │  exporter sidecar :9608      │      │
│  └──────────────┬───────────────┘    └──────────────┬───────────────┘      │
│                 │                                   │                      │
│                 └─────────────────┬─────────────────┘                      │
│                                   ▼                                        │
│                 ironic-prometheus-exporter Service                         │
│                 Publishes ready endpoints on named port metrics            │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │ Kubernetes API discovery: role endpoints
                                    │ Direct HTTP GET to every endpoint IP:9608
                                    │ every 30 seconds (does not use ClusterIP)
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         Monitoring Namespace                               │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ OpenTelemetry Deployment Collector                                   │  │
│  │                                                                      │  │
│  │ prometheus/ironic receiver ──► processors ──► prometheusremotewrite  │  │
│  └───────────────────────────────────┬──────────────────────────────────┘  │
│                                      │                                     │
│                                      ▼                                     │
│                              ┌──────────────┐                              │
│                              │ Prometheus   │                              │
│                              │ Metrics/Rules│                              │
│                              └──────┬───────┘                              │
│                                     │                                      │
│                          ┌──────────┴──────────┐                           │
│                          ▼                     ▼                           │
│                    ┌───────────┐        ┌──────────────┐                   │
│                    │ Grafana   │        │ Alertmanager │                   │
│                    │ Dashboards│        │ Notifications│                   │
│                    └───────────┘        └──────────────┘                   │
└────────────────────────────────────────────────────────────────────────────┘
```

Each conductor Pod has its own exporter sidecar. The
`ironic-prometheus-exporter` Service selects all Ironic conductor Pods, and the
OpenTelemetry receiver uses Kubernetes service discovery to turn every ready
Service endpoint into a separate scrape target. It then connects directly to
each endpoint IP on port `9608`; scrape traffic does not pass through the
Service ClusterIP. This ensures that metrics produced by each conductor are
collected.

!!! note

    The Prometheus scrape interval and the Ironic sensor collection interval
    control different operations. The OpenTelemetry deployment collector
    scrapes the exporter every 30 seconds, but Ironic refreshes the underlying
    hardware sensor data every 120 seconds by default.

## Prerequisites

Before enabling collection, ensure that:

- Ironic is deployed and its conductors are healthy.
- The OpenTelemetry monitoring stack is installed.
- The target BMCs are reachable from the Ironic conductors.
- The nodes use a hardware type that can provide supported sensor data.
- The OpenTelemetry collector can list Kubernetes Services, Endpoints, and
  Pods in the `openstack` namespace.

See [Monitoring Getting Started](monitoring-getting-started.md) for the base
monitoring stack installation.

## Ironic Sensor Configuration

The base Ironic Helm overrides enable sensor collection and configure the
Prometheus exporter notification driver:

```yaml
conf:
  ironic:
    sensor_data:
      send_sensor_data: true
      interval: 120
      workers: 4
      data_types: ALL
      enable_for_conductor: true
      enable_for_nodes: true
      enable_for_undeployed_nodes: true
    metrics:
      backend: collector
    oslo_messaging_notifications:
      driver: prometheus_exporter
      transport_url: fake://
      location: /var/lib/ironic/metrics
```

The settings have the following purposes:

| Setting | Purpose |
| --- | --- |
| `send_sensor_data` | Enables periodic collection of hardware sensor data. |
| `interval` | Sets the sensor refresh interval in seconds. |
| `workers` | Sets the number of workers used for sensor collection. |
| `data_types` | Selects which available sensor data types are collected. |
| `enable_for_conductor` | Includes conductor metrics in the collected data. |
| `enable_for_nodes` | Includes managed bare metal node metrics. |
| `enable_for_undeployed_nodes` | Collects sensor data from undeployed nodes. |
| `backend` | Stores collected Ironic metrics for notification delivery. |
| `driver` | Writes notifications in the format consumed by the exporter. |
| `location` | Specifies the metrics directory read by the exporter. |

Environment-specific changes should be placed in an override under
`/etc/genestack/helm-configs/ironic/`. After changing the sensor configuration,
apply it by upgrading the Ironic deployment:

```shell
/opt/genestack/bin/install-ironic.sh
```

## Exporter Deployment

The Genestack Ironic Helm values add an `ironic-prometheus-exporter` sidecar to
each conductor Pod. Each sidecar:

- Reads `/etc/ironic/ironic.conf`.
- Listens on the Pod IP at port `9608`.
- Exposes metrics at `/metrics`.
- Uses HTTP readiness and liveness probes against `/metrics`.

The Ironic post-renderer also creates this Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ironic-prometheus-exporter
spec:
  selector:
    application: ironic
    component: conductor
  ports:
    - name: metrics
      port: 9608
      targetPort: metrics
      protocol: TCP
```

The port name must remain `metrics` because the OpenTelemetry relabel rules use
that name to select the correct endpoint port.

## Enable OpenTelemetry Collection

Ironic collection is supplied as an optional OpenTelemetry values example. Copy
it into the service override directory before installing or upgrading the
OpenTelemetry stack:

```shell

cp \
  /opt/genestack/base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-ironic-overrides.yaml.example \
  /etc/genestack/helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-ironic-overrides.yaml

/opt/genestack/bin/install-opentelemetry-kube-stack.sh
```

The override adds the `prometheus/ironic` receiver to the deployment
collector's metrics pipeline. Its scrape configuration is:

```yaml
--8<-- "base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-ironic-overrides.yaml.example"
```

### Why Endpoint Discovery Is Used

The `endpoints` role discovers the actual Pod IP and named port registered
behind the `ironic-prometheus-exporter` Service. The relabel rules then:

1. retain only the `ironic-prometheus-exporter` Service
2. retain only the named `metrics` port
3. retain only ready endpoints
4. add namespace, Service, Pod, and node labels
5. set the Prometheus job to `ironic-prometheus-exporter`

Using endpoint discovery is preferable to discovering all Pods because it
follows the Service selector and excludes endpoints that are not ready.

!!! warning

    Every OpenTelemetry deployment collector replica running this receiver can
    discover and scrape every exporter endpoint. If the deployment collector is
    scaled beyond one replica without target allocation or sharding, verify that
    the monitoring backend is not receiving duplicate samples.

## Validate Collection

### Check Ironic Conductors And Exporter Sidecars

List the conductor Pods and confirm that each Pod includes the exporter
container:

```shell
kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor

kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

Check the exporter logs in one conductor Pod:

```shell
CONDUCTOR_POD=$(kubectl --namespace openstack get pods \
  -l application=ironic,component=conductor \
  -o jsonpath='{.items[0].metadata.name}')

kubectl --namespace openstack logs "${CONDUCTOR_POD}" \
  --container ironic-prometheus-exporter
```

Check The Service And Endpoints

```shell
kubectl --namespace openstack get service ironic-prometheus-exporter
kubectl --namespace openstack get endpoints ironic-prometheus-exporter
```

The Endpoints object should contain one ready address for each healthy
conductor Pod and port `9608` named `metrics`.

To inspect whether Ironic is creating metrics files inside a conductor Pod:

```shell
kubectl --namespace openstack exec "${CONDUCTOR_POD}" \
  --container ironic-conductor -- \
  find /var/lib/ironic/metrics -maxdepth 1 -type f -ls
```

### Query The Exporter Directly

The Ironic conductor uses the host network, and the exporter listens on the Pod
IP, which is the Kubernetes node IP in this configuration. Test the ClusterIP
Service from a Pod inside the cluster:

```shell
kubectl --namespace openstack exec openstack-admin-client -- \
  curl --fail --silent --show-error \
  http://ironic-prometheus-exporter.openstack.svc.cluster.local:9608/metrics \
  | head
```

An HTTP success response confirms that the Service can reach an exporter.
Confirm that the response contains Ironic metrics and not only an empty
response.

!!! note

    The manual ClusterIP request above selects one backend Pod and therefore
    proves only that at least one exporter is reachable. OpenTelemetry does not
    use that load-balanced path: `role: endpoints` creates one scrape target
    for every ready endpoint published by the Service.

To validate the same paths used by OpenTelemetry, query every endpoint IP from
inside the cluster:

```shell
for ENDPOINT_IP in $(kubectl --namespace openstack get endpoints \
  ironic-prometheus-exporter \
  -o jsonpath='{.subsets[*].addresses[*].ip}'); do
  echo "Checking ${ENDPOINT_IP}:9608"
  kubectl --namespace openstack exec openstack-admin-client -- \
    curl --fail --silent --show-error \
    "http://${ENDPOINT_IP}:9608/metrics" >/dev/null
done
```

Each endpoint should return successfully. If one fails, inspect the exporter
sidecar and network path on that conductor's node.

### Query Prometheus

In Prometheus or Grafana Explore, start with:

```promql
up{job="ironic-prometheus-exporter"}
```

Each ready exporter endpoint should report a value of `1`. To inspect all
metric families received for the job, use:

```promql
{job="ironic-prometheus-exporter"}
```

## Limitations

- The available sensor metrics depend on the server hardware, BMC, and Ironic
  hardware type.
- Upstream exporter sensor parsing supports IPMI and Redfish data.
- The exporter exposes Gauge metrics.
- A successful exporter scrape does not prove that every BMC sensor collection
  succeeded; conductor logs and metric freshness must also be monitored.

## References

For upstream details, see the
- [Ironic Prometheus Exporter documentation](https://docs.openstack.org/ironic-prometheus-exporter/latest/)
- [configuration reference](https://docs.openstack.org/ironic-prometheus-exporter/latest/configuration.html)
- [limitations](https://docs.openstack.org/ironic-prometheus-exporter/latest/limitations.html)
