# Monitoring And Observability Stack Overview

Complete overview of the monitoring and observability stack for Rackspace Genestack, providing telemetry collection, storage, visualization, and alerting across the entire infrastructure.

---

## Table of Contents

1. [Component Guide Map](#component-guide-map)
2. [Architecture Overview](#architecture-overview)
3. [Technology Stack](#technology-stack)
4. [Data Flow](#data-flow)
5. [Components](#components)
6. [What Gets Monitored](#what-gets-monitored)
7. [Access Points](#access-points)
8. [Key Features](#key-features)
9. [Collected Metrics]
10. [Summary](#summary)(monitoring-otel-base-metrics.md)

---

## Component Guide Map

Genestack keeps monitoring configuration in service-specific directories so the Helm values and Kustomize overlays follow the same pattern as the rest of the platform:

- `/opt/genestack/base-helm-configs/<service>/`
- `/etc/genestack/helm-configs/<service>/`
- `/etc/genestack/kustomize/<service>/overlay/`

The documentation still groups the stack conceptually so you can navigate it as one monitoring system:

- [Getting Started](monitoring-getting-started.md) for install order and day-one validation
- [Prometheus](monitoring-prometheus.md) for metrics storage and alerting
- [Loki](monitoring-loki.md) for logs
- [Tempo](monitoring-tempo.md) for traces
- [Grafana](monitoring-grafana.md) for dashboards and datasources
- [OpenTelemetry](monitoring-opentelemetry.md) for collectors and infrastructure telemetry receivers
- [OpenStack Exporter](openstack-exporter.md) for OpenStack API availability probes
- [Pushgateway](prometheus-pushgateway.md) for short-lived job metrics
- [OpenTelemetry Metrics Reference](monitoring-otel-base-metrics.md)

---

## Architecture Overview

The observability stack is deployed in the `monitoring` namespace and provides comprehensive telemetry collection for:

- **Kubernetes cluster** (nodes, pods, containers, resources)
- **OpenStack services** (Nova, Neutron, Keystone, Cinder, Glance, and related APIs)
- **OpenStack compute domains** via libvirt exporter metrics enriched with Nova/OpenStack metadata
- **Infrastructure services** (MySQL, PostgreSQL, RabbitMQ, Memcached)
- **Application traces** and **distributed tracing**

### High-Level Architecture

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                          Monitoring Namespace                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                    OpenTelemetry Collectors                        │    │
│  │                                                                    │    │
│  │  ┌───────────────────┐              ┌──────────────────────┐       │    │
│  │  │ Daemon Collectors │              │ Deployment Collector │       │    │
│  │  │  (DaemonSet)      │              │    (Deployment)      │       │    │
│  │  │                   │              │                      │       │    │
│  │  │ • Metrics (OTLP)  │              │ • MySQL Metrics      │       │    │
│  │  │ • Traces (OTLP)   │              │ • PostgreSQL Metrics │       │    │
│  │  │ • Logs (filelog)  │              │ • RabbitMQ Metrics   │       │    │
│  │  │ • Host Metrics    │              │ • Memcached Metrics  │       │    │
│  │  │ • K8s Events      │              │ • HTTP Checks        │       │    │
│  │  │ • Libvirt Exporter│              │                      │       │    │
│  │  └─────────┬─────────┘              └──────────┬───────────┘       │    │
│  └────────────┼───────────────────────────────────┼───────────────────┘    │
│               │                                   │                        │
│               ├──────────────┬────────────────────┼──────────┐             │
│               │              │                    │          │             │
│               ▼              ▼                    ▼          ▼             │
│      ┌────────────┐  ┌────────────┐     ┌────────────┐  ┌──────────┐       │
│      │ Prometheus │  │    Loki    │     │   Tempo    │  │AlertMgr  │       │
│      │            │  │            │     │            │  │          │       │
│      │ • Metrics  │  │ • Logs     │     │ • Traces   │  │• Alerts  │       │
│      │ • Alerts   │  │ • Search   │     │ • Storage  │  │• Routes  │       │
│      │ • Rules    │  │ • Storage  │     │            │  │          │       │
│      └─────┬──────┘  └─────┬──────┘     └─────┬──────┘  └────┬─────┘       │
│            │               │                  │              │             │
│            └───────────────┴──────────────────┴──────────────┘             │
│                                     │                                      │
│                                     ▼                                      │
│                            ┌─────────────────┐                             │
│                            │    Grafana      │                             │
│                            │                 │                             │
│                            │ • Dashboards    │                             │
│                            │ • Visualization │                             │
│                            │ • Explore       │                             │
│                            │                 │                             │
│                            └─────────────────┘                             │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

### Core Components

| Component | Purpose | Technology | Storage |
|-----------|---------|------------|---------|
| **OpenTelemetry** | Telemetry collection and processing | OTel Collector Contrib | Stateless |
| **Prometheus** | Metrics storage and querying | Prometheus 2.x | Local TSDB (15d retention) |
| **Loki** | Log aggregation and querying | Grafana Loki 2.x | S3/Filesystem |
| **Tempo** | Distributed tracing | Grafana Tempo 2.x | S3/Filesystem |
| **Grafana** | Visualization and dashboards | Grafana 10.x | MariaDB |
| **Alertmanager** | Alert routing and notification | Prometheus Alertmanager | Stateless |

### Supporting Components

| Component | Purpose | Details |
|-----------|---------|---------|
| **kube-state-metrics** | Kubernetes cluster state metrics | Exports cluster-level metrics (deployments, pods, nodes) |
| **node-exporter** | Node-level system metrics | CPU, memory, disk, network per node |
| **libvirt exporter** | Nova compute domain metrics | Exports VM state, CPU, memory, block, interface, vCPU, and job metrics with OpenStack metadata |
| **MariaDB** | Grafana persistent storage | Stores dashboards, users, datasources |
| **ServiceMonitors** | Prometheus target discovery | Auto-discovers scrape targets via CRDs |

---

## Data Flow

### Metrics Flow

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                          Metrics Collection                              │
└──────────────────────────────────────────────────────────────────────────┘

Sources                     Collectors                Storage   Visualization
────────                    ──────────                ───────   ─────────────
Kubernetes Pods ─────┐
OpenStack Services ──┤
Host Metrics ────────┤                         ┌──► Prometheus ──► Grafana
K8s Events ──────────┤                         │    (TSDB)         (Dashboards)
Libvirt Exporter ────┘ ───────► OTel Daemon ───┤
                                 (DaemonSet)   │
                                               └──► Alerting / Rules

MySQL ───────────────┐
PostgreSQL ──────────┤
RabbitMQ ────────────┤ ───────► OTel Deployment ───────► Prometheus ──► Grafana
Memcached ───────────┘           (Single Pod)             (TSDB)

ServiceMonitors ────────────────────────────────────────► Prometheus ──► Grafana
(kube-state-metrics, node-exporter, other direct scrapes)
```

### Logs Flow

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                           Logs Collection                                │
└──────────────────────────────────────────────────────────────────────────┘

Log Sources                 Collectors         Processing        Storage
───────────                 ──────────         ──────────        ───────
/var/log/pods/ ──────┐
(K8s containers)     │
                     ├──► OTel Daemon ──► Processors ──► Loki ──► Grafana
/var/log/pods/ ──────┤    (filelog)         • Parse       (Store) (Explore)
(OpenStack svcs)     │                      • Enrich              (Search)
                     │                      • Label
K8s Events ──────────┘                      • Filter
```

### Traces Flow

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                          Traces Collection                               │
└──────────────────────────────────────────────────────────────────────────┘

Application Code         Collectors            Storage          Visualization
────────────────         ──────────            ───────          ─────────────
Python Apps  ────┐
(OpenTelemetry)  │
                 ├──► OTel Daemon  ──► Tempo  ──► Grafana
Java Apps ───────┤    (OTLP gRPC)      (S3)       (Trace View)
(Jaeger SDK)     │                                (Service Graph)
                 │
Go Apps ─────────┘
(Zipkin)
```

---

## Components

### OpenTelemetry Collectors

**Purpose**: Universal telemetry collection, processing, and export.

#### Daemon Collector (DaemonSet)

- **Deployment**: One pod per Kubernetes node
- **Collects**:
  - OTLP metrics and traces from applications
  - Jaeger and Zipkin traces (legacy protocols)
  - Container logs via filelog (`/var/log/pods`)
  - Host metrics (CPU, memory, disk, network)
  - Kubernetes events via k8sobjects
  - Libvirt exporter metrics from compute nodes, including:
    - domain inventory and timeout status: `libvirt_domains`, `libvirt_domain_timed_out`
    - domain metadata and state: `libvirt_domain_openstack_info`, `libvirt_domain_info`, `libvirt_domain_info_state`
    - CPU and vCPU metrics: `libvirt_domain_info_cpu_time_seconds_total`, `libvirt_domain_vcpu_*`
    - memory metrics: `libvirt_domain_memory_stats_*`
    - block metrics: `libvirt_domain_block_stats_*`
    - interface metrics: `libvirt_domain_interface_stats_*`
    - migration and job progress metrics: `libvirt_domain_job_info_*`
- **Processes**:
  - Kubernetes attributes enrichment (pod, namespace, labels)
  - Resource attribute manipulation
  - Batching and memory limiting
- **Exports**:
  - Metrics → Prometheus (remote write)
  - Logs → Loki (OTLP/HTTP)
  - Traces → Tempo (OTLP/gRPC)

#### Deployment Collector (Single Pod)

- **Deployment**: One pod on the control plane
- **Collects**:
  - MySQL metrics (connections, queries, locks, buffer pool)
  - PostgreSQL metrics (backends, transactions, deadlocks, size)
  - RabbitMQ metrics (messages, queues, consumers, node health)
  - Memcached metrics (hit ratio, evictions, memory)
  - HTTP endpoint checks (OpenStack API health)
- **Exports**:
  - Metrics → Prometheus (remote write)

**Key Features**:

- Vendor-agnostic telemetry format (OTLP)
- Built-in processors for data manipulation
- Multiple protocol support (OTLP, Jaeger, Zipkin)
- Automatic Kubernetes metadata enrichment
- Compute-local libvirt scraping from the daemon collector, which keeps VM metrics aligned with the node that runs the guest

### Prometheus

**Purpose**: Time-series metrics storage and querying.

**Deployment**:

- StatefulSet with persistent storage (15 days retention)
- Alertmanager for alert routing

**Collects Metrics From**:

- OpenTelemetry collectors (remote write)
- kube-state-metrics (Kubernetes cluster state)
- node-exporter (node system metrics)
- libvirt exporter metrics relayed through OpenTelemetry
- ServiceMonitors (auto-discovered targets)

**Data Model**:

- Time-series: `metric_name{label="value"} value timestamp`
- Query language: PromQL
- Storage: Local TSDB (optimized for time-series data)

**Retention**:

- Default: 15 days
- Configurable via `retention.time` and `retention.size`

**Key Features**:

- Powerful query language (PromQL)
- Multi-dimensional data model
- Built-in alerting rules
- Service discovery and scraping
- High performance for time-series queries

### Loki

**Purpose**: Log aggregation and querying system (like Prometheus but for logs).

**Deployment**:

- Distributed architecture:
  - **Write**: Ingests logs from OTel
  - **Read**: Serves log queries
  - **Backend**: Long-term storage

**Data Model**:

- Logs stored with labels (not indexed content)
- Query language: LogQL (similar to PromQL)
- Cost-effective: only indexes labels, not log content

**Storage**:

- Short-term: local filesystem
- Long-term: S3-compatible object storage

**Key Features**:

- Label-based indexing (efficient storage)
- LogQL for querying (grep-like but better)
- Integrates with Grafana (Explore interface)
- Multi-tenancy support
- Automatic log parsing and labeling

**Query Examples**:

```logql
# All logs from OpenStack namespace
{namespace="openstack"}

# Errors from Nova service
{namespace="openstack", service_name="nova"} |= "ERROR"

# Rate of errors per minute
rate({namespace="openstack"} |= "ERROR" [5m])
```

### Tempo

**Purpose**: Distributed tracing backend.

**Deployment**:

- Scalable architecture (ingester, querier, compactor)
- S3-compatible storage for traces

**Data Model**:

- Traces composed of spans
- Each span has:
  - Trace ID (unique per request)
  - Span ID (unique per operation)
  - Parent span ID (for hierarchy)
  - Timestamps, tags, logs

**Key Features**:

- Cost-effective trace storage
- TraceQL for querying traces
- Integrates with Grafana and Loki
- Automatic trace-to-logs correlation

**Use Cases**:

- Debug slow API requests
- Find bottlenecks in microservices
- Trace request flow across services
- Identify error propagation

### Grafana

**Purpose**: Visualization and dashboarding platform.

**Deployment**:

- Deployment with MariaDB backend
- Persistent storage for dashboards and configuration

**Datasources**:

- **Prometheus**: Metrics and alerting
- **Loki**: Log searching and exploration
- **Tempo**: Distributed tracing

**Features**:

- **Dashboards**: Pre-built and custom visualizations
- **Explore**: Ad-hoc querying interface
- **Alerting**: Visual alert rule builder
- **Correlation**: Jump from metrics → logs → traces

**Pre-configured Dashboard Themes**:

- Kubernetes cluster monitoring
- Node resource usage
- OpenStack service health
- Nova/libvirt compute domain health and capacity
- Database performance
- RabbitMQ queue monitoring

### Alertmanager

**Purpose**: Alert routing and notification management.

**Deployment**:

- StatefulSet for HA (high availability)
- Receives alerts from Prometheus

**Features**:

- **Grouping**: Combine similar alerts
- **Inhibition**: Suppress dependent alerts
- **Silencing**: Temporarily mute alerts
- **Routing**: Send to different channels (Slack, PagerDuty, email)

**Alert Flow**:

```text
Prometheus Rules ──► Alertmanager ──► Notification Channels
 (PromQL)              (Routing)          • Slack
                                           • PagerDuty
                                           • Email
                                           • Webhooks
```

---

## What Gets Monitored

### Kubernetes Infrastructure

| Component | Metrics | Logs | Traces |
|-----------|---------|------|--------|
| **Nodes** | CPU, memory, disk, network | System logs | N/A |
| **Pods** | Resource usage, restarts, status | Container stdout/stderr | App traces |
| **Containers** | CPU, memory, I/O | Application logs | App traces |
| **Services** | Request rate, latency, errors | Service logs | Service traces |
| **Cluster State** | Deployments, StatefulSets, DaemonSets | K8s events | N/A |

### OpenStack Services

| Service | Metrics | Logs | Examples |
|---------|---------|------|----------|
| **Nova API** | API requests, scheduler activity, VM operations | nova-api, nova-scheduler logs | VM creation traces |
| **Nova / Libvirt Compute** | Domain count, state, CPU, memory, vCPU, disk I/O, network I/O, migration/job progress | nova-compute, libvirtd logs | VM lifecycle and compute-node troubleshooting |
| **Neutron** | Network operations, ports | neutron-server logs | Network provisioning |
| **Keystone** | Auth requests, token operations | keystone logs | Auth flow traces |
| **Cinder** | Volume operations | cinder-api logs | Volume attach traces |
| **Glance** | Image operations | glance-api logs | Image upload traces |

_All OpenStack services are logged; the above is representative, not exhaustive._

### OpenStack Compute / Libvirt Metric Families

The libvirt exporter provides detailed domain metrics that are best understood as Nova compute visibility rather than generic host metrics.

| Family | Examples | Typical Use |
|--------|----------|-------------|
| **Domain inventory and metadata** | `libvirt_domains`, `libvirt_domain_timed_out`, `libvirt_domain_openstack_info`, `libvirt_domain_info`, `libvirt_domain_info_state` | Count VMs, track state, map domains to instance name, flavor, project, and compute host |
| **CPU and vCPU** | `libvirt_domain_info_cpu_time_seconds_total`, `libvirt_domain_info_virtual_cpus`, `libvirt_domain_vcpu_current`, `libvirt_domain_vcpu_time_seconds_total`, `libvirt_domain_vcpu_wait_seconds_total`, `libvirt_domain_vcpu_delay_seconds_total`, `libvirt_domain_vcpu_state` | VM CPU usage, vCPU wait/delay analysis, scheduling pressure |
| **Memory** | `libvirt_domain_info_memory_usage_bytes`, `libvirt_domain_info_maximum_memory_bytes`, `libvirt_domain_memory_stats_*` | Guest memory usage, RSS, ballooning, faults, swap, usable/unused memory |
| **Block I/O** | `libvirt_domain_block_stats_*`, `libvirt_domain_block_stats_info` | Disk throughput, IOPS, read/write latency, flush latency, capacity |
| **Interface I/O** | `libvirt_domain_interface_stats_*`, `libvirt_domain_interface_stats_info` | Guest network throughput, packet rates, drops, errors |
| **Migration and job metrics** | `libvirt_domain_job_info_*` | Migration progress, elapsed time, remaining time, bytes processed |

### Libvirt Metadata and Labeling Notes

Use metadata from `libvirt_domain_openstack_info` for VM identity and OpenStack context:

- `instance_name`: friendly VM name
- `instance_id`: UUID for the Nova server
- `project_name` and `project_id`: tenant/project context
- `flavor_name`: Nova flavor context
- `host_name`: compute host

Be careful with the scrape label `instance`: in daemon-local libvirt scraping it may only identify the exporter endpoint, such as `localhost:9474`, rather than the Nova server identity.

### Infrastructure Services

| Service | Metrics Collected | Key Metrics |
|---------|-------------------|-------------|
| **MySQL/MariaDB** | 25+ metrics | Connections, queries, locks, buffer pool |
| **PostgreSQL** | 30+ metrics | Backends, commits, deadlocks, cache hits |
| **RabbitMQ** | 20+ metrics | Messages, queues, consumers, memory |
| **Memcached** | 15+ metrics | Hit ratio, evictions, memory usage |

### Application Instrumentation

Applications can send telemetry using:

- **OpenTelemetry SDKs** (Python, Java, Go, Node.js)
- **Jaeger client libraries** (legacy)
- **Zipkin libraries** (legacy)

Send to: `opentelemetry-kube-stack-daemon-collector:4317` (OTLP gRPC)

---

## Access Points

### Grafana UI

```text
URL: http://grafana.monitoring.svc.cluster.local
     or https://grafana.your-domain.com (if Ingress configured)

Default Credentials:
  Username: admin
  Password: (from secret: grafana-admin-password)
```

**Access via kubectl port-forward**:

```bash
kubectl -n monitoring port-forward svc/grafana 3000:80
# Open: http://localhost:3000
```

**Use Cases**:

- View infrastructure dashboards
- Explore Nova/libvirt compute dashboards
- Correlate metrics with logs and traces

### Prometheus UI

```text
URL: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
```

**Access via kubectl port-forward**:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090
```

**Use Cases**:

- Query metrics with PromQL
- View active alerts
- Check target health
- Debug scraping issues
- Validate libvirt exporter series and label joins

### Alertmanager UI

```text
URL: http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093
```

**Access via kubectl port-forward**:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
# Open: http://localhost:9093
```

**Use Cases**:

- View active alerts
- Silence alerts
- Check alert routing

---

## Key Features

### 1. Unified Observability

**Three Pillars in One Stack**:

- **Metrics**: numerical time-series data (what is happening)
- **Logs**: event records (what happened)
- **Traces**: request flows (how it happened)

**Correlation**:

- Jump from metric spike → related logs → trace details
- Unified view across all telemetry types
- Follow Nova API activity into compute-node domain metrics and compute logs

### 2. Kubernetes-Native

- **Service Discovery**: automatic target discovery via ServiceMonitors
- **Metadata Enrichment**: automatic pod/namespace/label tagging
- **Resource Awareness**: monitors Kubernetes resources (CPU, memory, limits)
- **CRD-Based**: uses Kubernetes custom resources for configuration

### 3. OpenStack Aware

- **Service Logs**: parses OpenStack log formats
- **API Monitoring**: tracks OpenStack API health
- **Request Tracing**: traces requests across OpenStack services
- **Compute Metrics**: monitors libvirt/Nova domains with OpenStack metadata for instance, project, flavor, and compute host
- **Infrastructure Metrics**: monitors databases and message queues

### 4. High Cardinality Support

- **Prometheus**: handles millions of time series
- **Loki**: efficient label-based log storage
- **Tempo**: cost-effective trace storage at scale

### 5. Alerting and Notification

- **PrometheusRules**: define alerts in YAML
- **Alertmanager**: route alerts to multiple channels
- **Grafana Alerts**: visual alert builder
- **Alert Hierarchy**: parent/child relationships and inhibition

### 6. Multi-Tenant Ready

- **Namespace Isolation**: clear separation of concerns
- **RBAC Integration**: Kubernetes RBAC for access control
- **Datasource Permissions**: Grafana team-based access
- **Tenant Context**: OpenStack labels such as project, user, and flavor make per-tenant views possible without changing the scrape path

### 7. Long-Term Storage

- **Prometheus**: 15 days in-cluster, can extend with Thanos
- **Loki**: S3 backend for long-term log retention
- **Tempo**: S3 backend for trace history

### 8. Cost-Effective

- **Loki**: only indexes labels (not log content), lowering storage costs
- **Tempo**: compressed trace storage in object storage
- **Prometheus**: efficient TSDB for time-series data
- **OpenTelemetry**: centralizes metric forwarding

---

## Summary

### What This Stack Provides

- ✅ Complete observability: metrics, logs, and traces in one unified stack
- ✅ Kubernetes-native: built for cloud-native environments
- ✅ OpenStack-aware: tailored for OpenStack deployments
- ✅ Compute-aware: includes libvirt/Nova domain metrics with OpenStack metadata
- ✅ Scalable: handles large-scale infrastructure
- ✅ Cost-effective: efficient storage and indexing
- ✅ Open source: no vendor lock-in, community-driven

### Key Benefits

- **Faster Debugging**: correlated telemetry (metrics → logs → traces)
- **Proactive Monitoring**: alerts before users notice issues
- **Performance Optimization**: identify bottlenecks and optimize
- **Compute Visibility**: inspect per-VM CPU, memory, network, disk, and migration progress from the same monitoring stack
- **Compliance**: audit trails and long-term retention
- **Team Collaboration**: shared dashboards and knowledge
