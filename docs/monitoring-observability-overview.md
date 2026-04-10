# Monitoring And Observability Stack Overview

Complete overview of the monitoring and observability stack for Rackspace Genestack, providing telemetry collection, storage, visualization, and alerting across the entire infrastructure.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Technology Stack](#technology-stack)
3. [Data Flow](#data-flow)
4. [Components](#components)
5. [What Gets Monitored](#what-gets-monitored)
6. [Access Points](#access-points)
7. [Key Features](#key-features)

---

## Architecture Overview

The observability stack is deployed in the `monitoring` namespace and provides comprehensive telemetry collection for:
- **Kubernetes cluster** (nodes, pods, containers, resources)
- **OpenStack services** (Nova, Neutron, Keystone, etc.)
- **Infrastructure services** (MySQL, PostgreSQL, RabbitMQ, Memcached)
- **Application traces** and **distributed tracing**

### High-Level Architecture

```
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
│                            │  • Explore      │                             │
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
| **OpenTelemetry** | Telemetry collection & processing | OTel Collector Contrib | Stateless |
| **Prometheus** | Metrics storage & querying | Prometheus 2.x | Local TSDB (15d retention) |
| **Loki** | Log aggregation & querying | Grafana Loki 2.x | S3/Filesystem |
| **Tempo** | Distributed tracing | Grafana Tempo 2.x | S3/Filesystem |
| **Grafana** | Visualization & dashboards | Grafana 10.x | MariaDB |
| **Alertmanager** | Alert routing & notification | Prometheus Alertmanager | Stateless |

### Supporting Components

| Component | Purpose | Details |
|-----------|---------|---------|
| **kube-state-metrics** | Kubernetes cluster state metrics | Exports cluster-level metrics (deployments, pods, nodes) |
| **node-exporter** | Node-level system metrics | CPU, memory, disk, network per node |
| **MariaDB** | Grafana persistent storage | Stores dashboards, users, datasources |
| **ServiceMonitors** | Prometheus target discovery | Auto-discovers scrape targets via CRDs |

---

## Data Flow

### Metrics Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Metrics Collection                              │
└──────────────────────────────────────────────────────────────────────────┘

Sources                   Collectors              Storage         Visualization
────────                  ──────────              ───────         ─────────────

Kubernetes Pods  ─────┐
                      │
OpenStack Services ───┤
                      ├──► OTel Daemon     ────┐
Host Metrics  ────────┤    (DaemonSet)         │
                      │                        │
K8s Events  ──────────┘                        ├──► Prometheus ──► Grafana
                                               │    (TSDB)         (Dashboards)
MySQL  ───────────┐                            │                   (Alerts)
                  │                            │
PostgreSQL  ──────┤                            │
                  ├──► OTel Deployment  ───────┘
RabbitMQ  ────────┤    (Single Pod)
                  │
Memcached  ───────┘

                                               
ServiceMonitors  ─────► Prometheus  ────────────► Grafana
(kube-state-metrics,    (Direct Scrape)           (Dashboards)
 node-exporter)
```

### Logs Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            Logs Collection                               │
└──────────────────────────────────────────────────────────────────────────┘

Log Sources              Collectors           Processing         Storage
───────────              ──────────           ──────────         ───────

/var/log/pods/  ──────┐
 (K8s containers)     │
                      ├──► OTel Daemon  ──► Processors  ──► Loki  ──► Grafana
/var/log/pods/  ──────┤    (filelog)         • Parse           (Storage)   (Explore)
 (OpenStack svcs)     │                      • Enrich          (Index)     (Search)
                      │                      • Label
K8s Events  ──────────┘                      • Filter

                      Parse:                 Query:
                      • CRI format           • LogQL
                      • Multiline            • Label filters
                      • Timestamps           • Regex search
                      • Severity             • Aggregation
```

### Traces Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Traces Collection                              │
└──────────────────────────────────────────────────────────────────────────┘

Application Code         Collectors            Storage          Visualization
────────────────         ──────────            ───────          ─────────────

Python Apps  ────┐
 (OpenTelemetry) │
                 ├──► OTel Daemon  ──► Tempo  ──► Grafana
Java Apps  ──────┤    (OTLP gRPC)      (S3)       (Trace View)
 (Jaeger SDK)    │                                (Service Graph)
                 │
Go Apps  ────────┘
 (Zipkin)

                 Protocols:              Query:
                 • OTLP (gRPC/HTTP)      • TraceQL
                 • Jaeger                • Trace ID
                 • Zipkin                • Service
                                         • Duration
```

---

## Components

### OpenTelemetry Collectors

**Purpose**: Universal telemetry collection, processing, and export

#### Daemon Collector (DaemonSet)
- **Deployment**: One pod per Kubernetes node
- **Collects**:
  - OTLP metrics and traces from applications
  - Jaeger and Zipkin traces (legacy protocols)
  - Container logs via filelog (`/var/log/pods`)
  - Host metrics (CPU, memory, disk, network)
  - Kubernetes events via k8sobjects
- **Processes**:
  - Kubernetes attributes enrichment (pod, namespace, labels)
  - Resource attribute manipulation
  - Batching and memory limiting
- **Exports**:
  - Metrics → Prometheus (remote write)
  - Logs → Loki (OTLP/HTTP)
  - Traces → Tempo (OTLP/gRPC)

#### Deployment Collector (Single Pod)
- **Deployment**: One pod on control plane
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

---

### Prometheus

**Purpose**: Time-series metrics storage and querying

**Deployment**:
- StatefulSet with persistent storage (15 days retention)
- Alertmanager for alert routing

**Collects Metrics From**:
- OpenTelemetry collectors (remote write)
- kube-state-metrics (Kubernetes cluster state)
- node-exporter (node system metrics)
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

---

### Loki

**Purpose**: Log aggregation and querying system (like Prometheus but for logs)

**Deployment**:
- Distributed architecture:
  - **Write**: Ingests logs from OTel
  - **Read**: Serves log queries
  - **Backend**: Long-term storage

**Data Model**:
- Logs stored with labels (not indexed content)
- Query language: LogQL (similar to PromQL)
- Cost-effective: Only indexes labels, not log content

**Storage**:
- Short-term: Local filesystem
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

---

### Tempo

**Purpose**: Distributed tracing backend

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
- Automatic trace to logs correlation

**Use Cases**:
- Debug slow API requests
- Find bottlenecks in microservices
- Trace request flow across services
- Identify error propagation

---

### Grafana

**Purpose**: Visualization and dashboarding platform

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

**Pre-configured Dashboards**:
- Kubernetes cluster monitoring
- Node resource usage
- OpenStack service health
- Database performance
- RabbitMQ queue monitoring

---

### Alertmanager

**Purpose**: Alert routing and notification management

**Deployment**:
- StatefulSet for HA (high availability)
- Receives alerts from Prometheus

**Features**:
- **Grouping**: Combine similar alerts
- **Inhibition**: Suppress dependent alerts
- **Silencing**: Temporarily mute alerts
- **Routing**: Send to different channels (Slack, PagerDuty, email)

**Alert Flow**:
```
Prometheus Rules  ──► Alertmanager  ──► Notification Channels
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
| **Nova** | API requests, VM operations | nova-api, nova-compute logs | VM creation traces |
| **Neutron** | Network operations, ports | neutron-server logs | Network provisioning |
| **Keystone** | Auth requests, token operations | keystone logs | Auth flow traces |
| **Cinder** | Volume operations | cinder-api logs | Volume attach traces |
| **Glance** | Image operations | glance-api logs | Image upload traces |
`All openstack services get logged the above is just an example`


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

```
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

### Prometheus UI

```
URL: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

Access via kubectl port-forward:
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090
```

**Use Cases**:
- Query metrics with PromQL
- View active alerts
- Check target health
- Debug scraping issues

### Alertmanager UI

```
URL: http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093

Access via kubectl port-forward:
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
- 📊 **Metrics**: Numerical time-series data (what's happening)
- 📝 **Logs**: Event records (what happened)
- 🔍 **Traces**: Request flows (how it happened)

**Correlation**:
- Jump from metric spike → related logs → trace details
- Unified view across all telemetry types

### 2. Kubernetes-Native

- **Service Discovery**: Automatic target discovery via ServiceMonitors
- **Metadata Enrichment**: Automatic pod/namespace/label tagging
- **Resource Awareness**: Monitors K8s resources (CPU, memory, limits)
- **CRD-Based**: Uses Kubernetes Custom Resources for configuration

### 3. OpenStack Aware

- **Service Logs**: Parses OpenStack log formats
- **API Monitoring**: Tracks OpenStack API health
- **Request Tracing**: Traces requests across OpenStack services
- **Infrastructure Metrics**: Monitors databases and message queues

### 4. High Cardinality Support

- **Prometheus**: Handles millions of time series
- **Loki**: Efficient label-based log storage
- **Tempo**: Cost-effective trace storage at scale

### 5. Alerting and Notification

- **PrometheusRules**: Define alerts in YAML
- **Alertmanager**: Route alerts to multiple channels
- **Grafana Alerts**: Visual alert builder
- **Alert Hierarchy**: Parent/child relationships and inhibition

### 6. Multi-Tenant Ready

- **Namespace Isolation**: Clear separation of concerns
- **RBAC Integration**: Kubernetes RBAC for access control
- **Datasource Permissions**: Grafana team-based access

### 7. Long-Term Storage

- **Prometheus**: 15 days in-cluster, can extend with Thanos
- **Loki**: S3 backend for long-term log retention
- **Tempo**: S3 backend for trace history

### 8. Cost-Effective

- **Loki**: Only indexes labels (not log content) → lower storage costs
- **Tempo**: Compressed trace storage in object storage
- **Prometheus**: Efficient TSDB for time-series data

---

## Summary

### What This Stack Provides

✅ **Complete Observability**: Metrics, logs, and traces in one unified stack  
✅ **Kubernetes-Native**: Built for cloud-native environments  
✅ **OpenStack-Aware**: Tailored for OpenStack deployments  
✅ **Scalable**: Handles large-scale infrastructure  
✅ **Cost-Effective**: Efficient storage and indexing  
✅ **Open Source**: No vendor lock-in, community-driven  

### Key Benefits

- **Faster Debugging**: Correlated telemetry (metrics → logs → traces)
- **Proactive Monitoring**: Alerts before users notice issues
- **Performance Optimization**: Identify bottlenecks and optimize
- **Compliance**: Audit trails and long-term retention
- **Team Collaboration**: Shared dashboards and knowledge

### Technology Choices

| Technology | Why Chosen |
|------------|-----------|
| **OpenTelemetry** | Industry standard, vendor-neutral, future-proof |
| **Prometheus** | De facto standard for metrics in Kubernetes |
| **Loki** | Cost-effective logs, integrates with Prometheus/Grafana |
| **Tempo** | Scalable tracing, S3-based storage |
| **Grafana** | Best-in-class visualization, multi-datasource support |

---

## Additional Resources

### Documentation

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)
- [Grafana Documentation](https://grafana.com/docs/grafana/)

### Community

- [CNCF Observability Landscape](https://landscape.cncf.io/card-mode?category=observability-and-analysis)
- [Genestack Project](https://github.com/rackerlabs/genestack)

---
