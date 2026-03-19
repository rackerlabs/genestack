# OpenTelemetry Base Metrics Collection - Complete Reference

This document describes all metrics collected by your OpenTelemetry configuration and where they come from.

---

## Table of Contents

1. [Metrics Collection Architecture](#metrics-collection-architecture)
2. [OTel Collector Metrics](#otel-collector-metrics)
3. [Kubernetes Component Metrics](#kubernetes-component-metrics)
4. [Node and System Metrics](#node-and-system-metrics)
5. [Application Metrics](#application-metrics)
6. [Metric Label Reference](#metric-label-reference)
7. [Troubleshooting](#troubleshooting)

---

## Metrics Collection Architecture

### Collection Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      METRICS SOURCES                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐                         ┌─────────────────┐    │
│  │ Applications    │                         │ Host Metrics    │    │
│  │ (OTLP)          │                         │ (node-level)    │    │
│  └────────┬────────┘                         └────────┬────────┘    │
│           │                                           │             │
│           └──────────────────┬────────────────────────┘             │
│                              │                                      │
│                              ▼                                      │
│               ┌──────────────────────────┐                          │
│               │ OTel Collector DaemonSet │                          │
│               │  (on each node)          │                          │
│               └──────────┬───────────────┘                          │
│                          │                                          │
│                          ▼                                          │
│               ┌──────────────────────────┐                          │
│               │ Prometheus Remote Write  │                          │
│               │ (:9090/api/v1/write)     │                          │
│               └──────────────────────────┘                          │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│              PROMETHEUS DIRECT SCRAPING (ServiceMonitors)           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ API      │  │ Scheduler│  │ Ctrl Mgr │  │ Kubelet  │             │
│  │ Server   │  │          │  │          │  │ cAdvisor │ ...         │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘             │
│        │             │             │             │                  │
│        └─────────────┼─────────────┼─────────────┘                  │
│                      │             │                                │
│                      ▼             ▼                                │
│           ┌──────────────────────────────┐                          │
│           │ Prometheus Server (scrape)   │                          │
│           └──────────────────────────────┘                          │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **OTel Collector DaemonSet**: Runs on every node, collects node-local metrics
2. **Prometheus Server**: Scrapes Kubernetes components directly via ServiceMonitors
3. **Remote Write**: OTel collectors push metrics to Prometheus

---

## OTel Collector Metrics

These metrics are collected by the OTel collector and sent to Prometheus via remote write.

### 1. Host Metrics (from hostmetrics receiver)

**Source**: hostmetrics receiver on each node  
**Collection Interval**: 30s  
**Labels**: `k8s_node_name`, `host_name`, `service_instance_id`

#### CPU Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_cpu_time_seconds_total` | Counter | CPU time by state | `cpu`, `state` (user, system, idle, iowait, irq, softirq, steal, nice) |
| `system_cpu_utilization_ratio` | Gauge | CPU utilization (0-1) | `cpu`, `state` |
| `system_cpu_load_average_1m` | Gauge | 1-minute load average | - |
| `system_cpu_load_average_5m` | Gauge | 5-minute load average | - |
| `system_cpu_load_average_15m` | Gauge | 15-minute load average | - |

#### Memory Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_memory_usage_bytes` | Gauge | Memory usage | `state` (used, free, buffered, cached, slab_reclaimable, slab_unreclaimable) |
| `system_memory_utilization_ratio` | Gauge | Memory utilization (0-1) | `state` |

#### Disk Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_disk_io_bytes_total` | Counter | Disk I/O bytes | `device`, `direction` (read, write) |
| `system_disk_operations_total` | Counter | Disk operations count | `device`, `direction` |
| `system_disk_io_time_seconds_total` | Counter | Disk I/O time | `device` |
| `system_disk_weighted_io_time_seconds_total` | Counter | Weighted I/O time | `device` |
| `system_disk_merged_total` | Counter | Merged operations | `device`, `direction` |
| `system_disk_pending_operations` | Gauge | Pending operations | `device` |

#### Filesystem Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_filesystem_usage_bytes` | Gauge | Filesystem usage | `device`, `type`, `mode`, `mountpoint`, `state` (used, free, reserved) |
| `system_filesystem_utilization_ratio` | Gauge | Filesystem utilization (0-1) | `device`, `type`, `mode`, `mountpoint` |
| `system_filesystem_inodes_usage` | Gauge | Inode usage | `device`, `type`, `mode`, `mountpoint`, `state` |

**Note**: Excludes pseudo-filesystems: `/dev/*`, `/proc/*`, `/sys/*`, `/run/*`, overlay, tmpfs, etc.

#### Network Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_network_io_bytes_total` | Counter | Network I/O bytes | `device`, `direction` (transmit, receive) |
| `system_network_packets_total` | Counter | Network packets | `device`, `direction` |
| `system_network_errors_total` | Counter | Network errors | `device`, `direction` |
| `system_network_dropped_total` | Counter | Dropped packets | `device`, `direction` |
| `system_network_connections` | Gauge | Network connections | `protocol`, `state` |

#### Paging Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_paging_usage_bytes` | Gauge | Swap usage | `device`, `state` (used, free) |
| `system_paging_operations_total` | Counter | Page in/out operations | `type` (major, minor), `direction` |
| `system_paging_faults_total` | Counter | Page faults | `type` |

#### Process Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_processes_count` | Gauge | Process count | `status` (running, blocked, etc.) |
| `system_processes_created_total` | Counter | Processes created | - |

---

### 2. Pod and Container Metrics (from Prometheus cAdvisor scraping)

**Source**: Prometheus scraping kubelet's cAdvisor endpoint `https://<node-ip>:10250/metrics/cadvisor`  
**Scrape Interval**: 30s (default)  
**Labels**: Includes pod, container, namespace, node, image labels

**Note**: In your configuration, kubeletstats receiver is **disabled** to avoid duplicate sample errors. Instead, pod and container metrics come from Prometheus directly scraping kubelet/cAdvisor via ServiceMonitor. These metrics use the `container_*` prefix instead of `k8s_pod_*` or `k8s_container_*`.

#### Container CPU Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_cpu_usage_seconds_total` | Counter | Total CPU time used | `container`, `pod`, `namespace`, `node` | `k8s_container_cpu_time_seconds_total` |
| `container_cpu_cfs_periods_total` | Counter | CFS scheduler periods | `container`, `pod`, `namespace` | - |
| `container_cpu_cfs_throttled_periods_total` | Counter | Throttled periods | `container`, `pod`, `namespace` | - |
| `container_cpu_cfs_throttled_seconds_total` | Counter | Time throttled | `container`, `pod`, `namespace` | - |

**Query Examples**:
```promql
# CPU usage rate (cores)
rate(container_cpu_usage_seconds_total{container!=""}[5m])

# Per-pod CPU usage
sum by (pod, namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))

# CPU throttling percentage
rate(container_cpu_cfs_throttled_seconds_total[5m]) 
  / 
rate(container_cpu_cfs_periods_total[5m]) * 100
```

#### Container Memory Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_memory_usage_bytes` | Gauge | Current memory usage | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_usage_bytes` |
| `container_memory_working_set_bytes` | Gauge | Working set size (used for OOM) | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_working_set_bytes` |
| `container_memory_rss` | Gauge | Resident set size | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_rss_bytes` |
| `container_memory_cache` | Gauge | Page cache | `container`, `pod`, `namespace` | - |
| `container_memory_swap` | Gauge | Swap usage | `container`, `pod`, `namespace` | - |
| `container_memory_failcnt` | Counter | Memory allocation failures | `container`, `pod`, `namespace` | - |
| `container_memory_failures_total` | Counter | Memory limit hit count | `container`, `pod`, `namespace`, `failure_type`, `scope` | - |

**Query Examples**:
```promql
# Current memory usage
container_memory_working_set_bytes{container!=""}

# Per-pod memory usage
sum by (pod, namespace) (container_memory_working_set_bytes{container!=""})

# Memory usage as % of limit
container_memory_working_set_bytes{container!=""}
  /
container_spec_memory_limit_bytes{container!=""} * 100
```

#### Container Network Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_network_receive_bytes_total` | Counter | Network RX bytes | `pod`, `namespace`, `interface` | `k8s_pod_network_io_bytes_total{direction="receive"}` |
| `container_network_transmit_bytes_total` | Counter | Network TX bytes | `pod`, `namespace`, `interface` | `k8s_pod_network_io_bytes_total{direction="transmit"}` |
| `container_network_receive_packets_total` | Counter | Network RX packets | `pod`, `namespace`, `interface` | - |
| `container_network_transmit_packets_total` | Counter | Network TX packets | `pod`, `namespace`, `interface` | - |
| `container_network_receive_packets_dropped_total` | Counter | RX packets dropped | `pod`, `namespace`, `interface` | - |
| `container_network_transmit_packets_dropped_total` | Counter | TX packets dropped | `pod`, `namespace`, `interface` | - |
| `container_network_receive_errors_total` | Counter | RX errors | `pod`, `namespace`, `interface` | `k8s_pod_network_errors_total{direction="receive"}` |
| `container_network_transmit_errors_total` | Counter | TX errors | `pod`, `namespace`, `interface` | `k8s_pod_network_errors_total{direction="transmit"}` |

**Query Examples**:
```promql
# Network receive rate (bytes/sec)
rate(container_network_receive_bytes_total[5m])

# Per-pod network bandwidth
sum by (pod, namespace) (
  rate(container_network_receive_bytes_total[5m]) +
  rate(container_network_transmit_bytes_total[5m])
)
```

#### Container Filesystem Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_fs_usage_bytes` | Gauge | Filesystem usage | `container`, `pod`, `namespace`, `device` | `k8s_container_filesystem_usage_bytes` |
| `container_fs_limit_bytes` | Gauge | Filesystem limit | `container`, `pod`, `namespace`, `device` | `k8s_container_filesystem_capacity_bytes` |
| `container_fs_reads_total` | Counter | Filesystem reads | `container`, `pod`, `namespace`, `device` | - |
| `container_fs_writes_total` | Counter | Filesystem writes | `container`, `pod`, `namespace`, `device` | - |
| `container_fs_reads_bytes_total` | Counter | Bytes read | `container`, `pod`, `namespace`, `device` | - |
| `container_fs_writes_bytes_total` | Counter | Bytes written | `container`, `pod`, `namespace`, `device` | - |
| `container_fs_inodes_total` | Gauge | Total inodes | `container`, `pod`, `namespace`, `device` | - |
| `container_fs_inodes_free` | Gauge | Free inodes | `container`, `pod`, `namespace`, `device` | - |

**Query Examples**:
```promql
# Filesystem usage
container_fs_usage_bytes{container!=""}

# Filesystem usage %
container_fs_usage_bytes{container!=""}
  /
container_fs_limit_bytes{container!=""} * 100

# I/O rate
rate(container_fs_reads_bytes_total[5m]) + 
rate(container_fs_writes_bytes_total[5m])
```

#### Container Limits and Requests

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `container_spec_cpu_quota` | Gauge | CPU quota (microseconds per period) | `container`, `pod`, `namespace` |
| `container_spec_cpu_period` | Gauge | CPU period (microseconds) | `container`, `pod`, `namespace` |
| `container_spec_cpu_shares` | Gauge | CPU shares | `container`, `pod`, `namespace` |
| `container_spec_memory_limit_bytes` | Gauge | Memory limit | `container`, `pod`, `namespace` |
| `container_spec_memory_reservation_limit_bytes` | Gauge | Memory soft limit | `container`, `pod`, `namespace` |
| `container_spec_memory_swap_limit_bytes` | Gauge | Memory + swap limit | `container`, `pod`, `namespace` |

**Query Examples**:
```promql
# CPU limit in cores
container_spec_cpu_quota / container_spec_cpu_period

# Memory limit
container_spec_memory_limit_bytes{container!=""}
```

#### Pod-Level Aggregations

Since cAdvisor reports per-container metrics, aggregate to pod level:

```promql
# Pod CPU usage (sum of all containers in pod)
sum by (pod, namespace, node) (
  rate(container_cpu_usage_seconds_total{container!=""}[5m])
)

# Pod memory usage (sum of all containers in pod)
sum by (pod, namespace, node) (
  container_memory_working_set_bytes{container!=""}
)

# Pod network I/O (already at pod level, not container level)
rate(container_network_receive_bytes_total[5m]) +
rate(container_network_transmit_bytes_total[5m])
```

#### Special Labels

**Important label filters**:
- `container!=""` - Excludes pod-level aggregates (use for per-container metrics)
- `container=""` - Shows only pod-level aggregates
- `container!="POD"` - Excludes pause containers in older K8s versions
- `image!=""` - Excludes special system containers

**Label mappings from cAdvisor**:
- `pod` → Kubernetes pod name (cAdvisor)
- `k8s_pod_name` → Kubernetes pod name (kubeletstats)
- `namespace` → Kubernetes namespace (cAdvisor)
- `k8s_namespace_name` → Kubernetes namespace (kubeletstats)
- `container` → Container name (cAdvisor)
- `k8s_container_name` → Container name (kubeletstats)

---

### 3. kubeletstats Metrics (DISABLED in Current Config)

**Status**: ⚠️ **DISABLED** - kubeletstats receiver is disabled to prevent duplicate sample errors.

The kubeletstats receiver would provide `k8s_pod_*` and `k8s_container_*` metrics, but these overlap significantly with the `container_*` metrics from cAdvisor (above). 

**Why disabled**: Multiple OTel collectors were sending identical metrics with identical timestamps to Prometheus, causing "duplicate sample" and "out of order sample" errors. The issue persisted even with proper node-level filtering.

**Alternative**: Use the `container_*` metrics from Prometheus/cAdvisor instead (see section above for equivalent queries).

**If you need kubeletstats metrics**: They can be re-enabled via the `kubeletMetrics` preset, but you may experience duplicate sample warnings in Prometheus logs. Most metrics will still work despite the warnings.

---

### 3. Application Metrics (via OTLP)

**Source**: Applications sending metrics to OTel collector via OTLP  
**Endpoints**: 
- gRPC: `:4317`
- HTTP: `:4318`

Applications instrumented with OpenTelemetry SDKs can send custom metrics. These vary by application but commonly include:

- Request counts, durations, error rates
- Business metrics (transactions, users, etc.)
- Resource usage from application perspective
- Custom application-specific metrics

**Labels**: Enriched with Kubernetes metadata via `k8sattributes` processor:
- `k8s_namespace_name`
- `k8s_pod_name`
- `k8s_node_name`
- `k8s_deployment_name`, `k8s_statefulset_name`, etc.
- Pod labels: `app`, `app_kubernetes_io_name`, `app_kubernetes_io_component`, etc.

---

## Kubernetes Component Metrics

These metrics are scraped **directly by Prometheus** via ServiceMonitors (NOT via OTel collectors).

### 1. API Server Metrics

**Source**: `kube-apiserver` (scraped by Prometheus)  
**Endpoint**: `https://kubernetes.default.svc:443/metrics`  
**Labels**: `instance`, `job`, `endpoint`, `service`, `namespace`

Common metrics:
- `apiserver_request_total` - API request count
- `apiserver_request_duration_seconds` - Request latency (histogram)
- `apiserver_request_sli_duration_seconds` - SLI latency
- `apiserver_current_inflight_requests` - In-flight requests
- `apiserver_longrunning_requests` - Long-running requests
- `apiserver_response_sizes` - Response sizes
- `apiserver_storage_objects` - Object counts in etcd
- `apiserver_audit_event_total` - Audit events
- `etcd_request_duration_seconds` - etcd request latency
- `etcd_db_total_size_in_bytes` - etcd database size

**Note**: Some histogram buckets are dropped via `metricRelabelings` to reduce cardinality.

### 2. Scheduler Metrics

**Source**: `kube-scheduler` (scraped by Prometheus)  
**Endpoint**: `https://<scheduler-pod-ip>:10259/metrics`  
**Labels**: `instance`, `job`, `endpoint`, `service`, `namespace`, `pod`

Common metrics:
- `scheduler_queue_incoming_pods_total` - Incoming pods by event/queue
- `scheduler_scheduling_attempt_duration_seconds` - Scheduling duration
- `scheduler_e2e_scheduling_duration_seconds` - End-to-end scheduling time
- `scheduler_pod_scheduling_attempts` - Pod scheduling attempts
- `scheduler_pending_pods` - Pending pods count
- `scheduler_framework_extension_point_duration_seconds` - Plugin execution time
- `scheduler_schedule_attempts_total` - Schedule attempts
- `scheduler_preemption_attempts_total` - Preemption attempts

### 3. Controller Manager Metrics

**Source**: `kube-controller-manager` (scraped by Prometheus)  
**Endpoint**: `https://<controller-pod-ip>:10257/metrics`  
**Labels**: `instance`, `job`, `endpoint`, `service`, `namespace`, `pod`

Common metrics:
- `workqueue_adds_total` - Work queue additions
- `workqueue_depth` - Work queue depth
- `workqueue_queue_duration_seconds` - Time in queue
- `workqueue_work_duration_seconds` - Work duration
- `workqueue_retries_total` - Retries count
- Controller-specific metrics for each controller (deployment, replicaset, etc.)

### 4. Kubelet Metrics (cAdvisor)

**Source**: `kubelet` cAdvisor endpoint (scraped by Prometheus)  
**Endpoint**: `https://<node-ip>:10250/metrics/cadvisor`  
**Labels**: `instance`, `job`, `node`, `container`, `pod`, `namespace`, `image`

**Important**: These are **different** from kubeletstats metrics. cAdvisor provides more detailed container metrics.

Common metrics:
- `container_cpu_usage_seconds_total` - Container CPU usage
- `container_memory_usage_bytes` - Container memory usage
- `container_memory_working_set_bytes` - Container working set
- `container_network_receive_bytes_total` - Network RX bytes
- `container_network_transmit_bytes_total` - Network TX bytes
- `container_fs_usage_bytes` - Filesystem usage
- `container_fs_reads_total` - Filesystem reads
- `container_fs_writes_total` - Filesystem writes
- `container_start_time_seconds` - Container start time
- `container_last_seen` - Last seen timestamp

### 5. Kubelet Metrics (kubelet /metrics)

**Source**: `kubelet` endpoint (scraped by Prometheus)  
**Endpoint**: `https://<node-ip>:10250/metrics`  
**Labels**: `instance`, `job`, `node`

Common metrics:
- `kubelet_running_pods` - Running pods count
- `kubelet_running_containers` - Running containers count
- `kubelet_volume_stats_*` - Volume statistics
- `kubelet_pod_start_duration_seconds` - Pod start duration
- `kubelet_pod_worker_duration_seconds` - Pod worker duration
- `kubelet_runtime_operations_*` - Container runtime operations
- `kubelet_pleg_*` - Pod lifecycle event generator metrics

### 6. CoreDNS Metrics

**Source**: `coredns` (scraped by Prometheus)  
**Endpoint**: `http://<coredns-pod-ip>:9153/metrics`  
**Labels**: `instance`, `job`, `pod`, `namespace`

Common metrics:
- `coredns_dns_request_duration_seconds` - DNS request duration
- `coredns_dns_requests_total` - DNS requests count
- `coredns_dns_responses_total` - DNS responses count
- `coredns_forward_requests_total` - Forwarded requests
- `coredns_cache_hits_total` - Cache hits
- `coredns_cache_misses_total` - Cache misses

### 7. etcd Metrics

**Source**: `etcd` (scraped by Prometheus if configured)  
**Endpoint**: `http://<etcd-ip>:2381/metrics`  
**Labels**: `instance`, `job`

Common metrics:
- `etcd_server_proposals_committed_total` - Committed proposals
- `etcd_server_proposals_applied_total` - Applied proposals
- `etcd_server_proposals_pending` - Pending proposals
- `etcd_server_proposals_failed_total` - Failed proposals
- `etcd_disk_wal_fsync_duration_seconds` - WAL fsync duration
- `etcd_disk_backend_commit_duration_seconds` - Backend commit duration
- `etcd_network_peer_round_trip_time_seconds` - Peer RTT
- `etcd_mvcc_db_total_size_in_bytes` - Database size

### 8. Kube Proxy Metrics

**Source**: `kube-proxy` (scraped by Prometheus)  
**Endpoint**: `http://<proxy-pod-ip>:10249/metrics`  
**Labels**: `instance`, `job`, `node`

Common metrics:
- `kubeproxy_sync_proxy_rules_duration_seconds` - Sync duration
- `kubeproxy_network_programming_duration_seconds` - Network programming duration
- `rest_client_requests_total` - REST client requests
- `rest_client_request_duration_seconds` - REST client latency

---

## Node and System Metrics

### 1. Node Exporter Metrics

**Source**: `node-exporter` DaemonSet (scraped by Prometheus)  
**Endpoint**: `http://<node-exporter-pod-ip>:9100/metrics`  
**Labels**: `instance`, `job`, `node` (added via relabeling)

**Important**: These provide MORE detailed node metrics than hostmetrics receiver.

#### CPU Metrics
- `node_cpu_seconds_total` - CPU time by mode
- `node_load1`, `node_load5`, `node_load15` - Load averages
- `node_procs_running` - Running processes
- `node_procs_blocked` - Blocked processes

#### Memory Metrics
- `node_memory_MemTotal_bytes` - Total memory
- `node_memory_MemFree_bytes` - Free memory
- `node_memory_MemAvailable_bytes` - Available memory
- `node_memory_Buffers_bytes` - Buffers
- `node_memory_Cached_bytes` - Cached
- `node_memory_SwapTotal_bytes` - Swap total
- `node_memory_SwapFree_bytes` - Swap free

#### Disk Metrics
- `node_disk_io_time_seconds_total` - Disk I/O time
- `node_disk_read_bytes_total` - Bytes read
- `node_disk_written_bytes_total` - Bytes written
- `node_disk_reads_completed_total` - Read operations
- `node_disk_writes_completed_total` - Write operations

#### Filesystem Metrics
- `node_filesystem_size_bytes` - Filesystem size
- `node_filesystem_free_bytes` - Filesystem free
- `node_filesystem_avail_bytes` - Filesystem available
- `node_filesystem_files` - Total inodes
- `node_filesystem_files_free` - Free inodes

#### Network Metrics
- `node_network_receive_bytes_total` - Network RX bytes
- `node_network_transmit_bytes_total` - Network TX bytes
- `node_network_receive_packets_total` - Network RX packets
- `node_network_transmit_packets_total` - Network TX packets
- `node_network_receive_errs_total` - Network RX errors
- `node_network_transmit_errs_total` - Network TX errors
- `node_network_receive_drop_total` - Network RX drops
- `node_network_transmit_drop_total` - Network TX drops

#### System Metrics
- `node_time_seconds` - System time
- `node_boot_time_seconds` - Boot time
- `node_context_switches_total` - Context switches
- `node_forks_total` - Forks
- `node_intr_total` - Interrupts

### 2. Kube State Metrics

**Source**: `kube-state-metrics` Deployment (scraped by Prometheus)  
**Endpoint**: `http://<ksm-pod-ip>:8080/metrics`  
**Labels**: Varies by resource type

**Important**: Provides Kubernetes object state metrics (NOT performance metrics).

#### Pod Metrics
- `kube_pod_info` - Pod information
- `kube_pod_status_phase` - Pod phase (Running, Pending, etc.)
- `kube_pod_status_ready` - Pod ready status
- `kube_pod_container_status_ready` - Container ready status
- `kube_pod_container_status_restarts_total` - Container restarts
- `kube_pod_labels` - Pod labels
- `kube_pod_owner` - Pod owner

#### Deployment Metrics
- `kube_deployment_status_replicas` - Deployment replicas
- `kube_deployment_status_replicas_available` - Available replicas
- `kube_deployment_status_replicas_unavailable` - Unavailable replicas
- `kube_deployment_spec_replicas` - Desired replicas
- `kube_deployment_metadata_generation` - Generation

#### Node Metrics
- `kube_node_info` - Node information
- `kube_node_status_condition` - Node conditions (Ready, MemoryPressure, etc.)
- `kube_node_status_allocatable` - Allocatable resources
- `kube_node_status_capacity` - Node capacity
- `kube_node_spec_unschedulable` - Unschedulable status

#### StatefulSet Metrics
- `kube_statefulset_status_replicas` - StatefulSet replicas
- `kube_statefulset_status_replicas_ready` - Ready replicas
- `kube_statefulset_replicas` - Desired replicas

#### DaemonSet Metrics
- `kube_daemonset_status_number_ready` - Ready pods
- `kube_daemonset_status_desired_number_scheduled` - Desired pods
- `kube_daemonset_status_number_available` - Available pods

#### Other Resource Metrics
- Services: `kube_service_*`
- ConfigMaps: `kube_configmap_*`
- Secrets: `kube_secret_*`
- PersistentVolumes: `kube_persistentvolume_*`
- PersistentVolumeClaims: `kube_persistentvolumeclaim_*`
- Ingress: `kube_ingress_*`
- Jobs: `kube_job_*`
- CronJobs: `kube_cronjob_*`

---

## Application Metrics

### OpenStack Service Metrics (via OTLP)

If OpenStack services are instrumented to send OTLP metrics, they will include:
- Custom application metrics
- Auto-instrumented framework metrics (HTTP requests, DB queries, etc.)
- Resource usage from application perspective

**Labels**: Enriched with:
- `service_name` (nova, neutron, cinder, etc.)
- Kubernetes labels from `k8sattributes` processor
- Custom application labels

---

## Metric Label Reference

### Common Labels Added by OTel Collectors

All metrics from OTel collectors are enriched with these labels (where applicable):

| Label | Source | Description |
|-------|--------|-------------|
| `k8s_node_name` | k8sattributes + attributes processor | Kubernetes node name |
| `host_name` | attributes processor | Same as k8s_node_name |
| `service_instance_id` | attributes processor | Node name (for uniqueness) |
| `k8s_namespace_name` | k8sattributes | Kubernetes namespace |
| `k8s_pod_name` | k8sattributes | Pod name |
| `k8s_pod_uid` | k8sattributes | Pod UID |
| `k8s_deployment_name` | k8sattributes | Deployment name |
| `k8s_statefulset_name` | k8sattributes | StatefulSet name |
| `k8s_daemonset_name` | k8sattributes | DaemonSet name |
| `k8s_job_name` | k8sattributes | Job name |
| `k8s_cronjob_name` | k8sattributes | CronJob name |
| `k8s_container_name` | k8sattributes | Container name |
| `app` | k8sattributes (from pod label) | App label |
| `app_kubernetes_io_name` | k8sattributes | Standard app name |
| `app_kubernetes_io_component` | k8sattributes | App component |
| `app_kubernetes_io_instance` | k8sattributes | App instance |
| `app_kubernetes_io_version` | k8sattributes | App version |
| `deployment_environment` | attributes processor | Fixed: "genestack" |
| `k8s_cluster_name` | attributes processor | Fixed: "openstack-genestack-k8s-cluster" |

### Labels from Prometheus ServiceMonitors

Metrics scraped directly by Prometheus include:

| Label | Description |
|-------|-------------|
| `instance` | Scrape target address (IP:port) |
| `job` | ServiceMonitor job name (e.g., "kube-scheduler") |
| `endpoint` | Endpoint name |
| `service` | Service name |
| `namespace` | Namespace |
| `pod` | Pod name (if available) |
| `node` | Node name (if added via relabeling) |

**Note**: To add `node` labels to ServiceMonitor metrics, add relabeling rules (see section above).

---

## Estimated Metric Cardinality

Based on your configuration:

### From OTel Collectors
- **hostmetrics**: ~200-300 unique series per node × N nodes
- **kubeletstats**: ⚠️ **DISABLED** (would be ~50-100 series per pod × P pods if enabled)
- **OTLP applications**: Varies widely (1000s to 100,000s depending on instrumentation)

### From Prometheus ServiceMonitors
- **API Server**: ~5,000 series
- **Scheduler**: ~500 series per scheduler
- **Controller Manager**: ~1,000 series per controller
- **Kubelet (cAdvisor)**: ~100-200 series per pod × P pods (**primary source for container metrics**)
- **Kubelet (kubelet)**: ~100 series per node × N nodes
- **CoreDNS**: ~50 series per CoreDNS pod
- **etcd**: ~500 series per etcd member
- **Kube Proxy**: ~100 series per node × N nodes
- **Node Exporter**: ~800-1000 series per node × N nodes
- **Kube State Metrics**: ~5-10 series per Kubernetes object

### Total Estimate
For a typical cluster with:
- 5 nodes
- 100 pods
- Standard Kubernetes components

**Total: ~50,000-100,000 unique time series**

For larger clusters, this can grow to 500,000+ series.

**Note**: With kubeletstats disabled, you're primarily using Prometheus-scraped `container_*` metrics for pod/container monitoring, which reduces the risk of duplicate metrics while still providing comprehensive coverage.

---

## Troubleshooting

### Metrics Not Appearing

1. **Check if OTel collector is running**:
   ```bash
   kubectl get pods -n opentelemetry
   ```

2. **Check collector logs for errors**:
   ```bash
   kubectl logs -n opentelemetry daemonset/opentelemetry-kube-stack-daemon-collector -c otc-container
   ```

3. **Verify metrics are being collected** (debug exporter):
   ```bash
   kubectl logs -n opentelemetry daemonset/opentelemetry-kube-stack-daemon-collector \
     -c otc-container | grep "k8s_pod_cpu"
   ```

4. **Check Prometheus targets**:
   - Go to Prometheus UI → Status → Targets
   - Verify all ServiceMonitors are discovered and UP

### Missing Labels

1. **For OTel-collected metrics**: Check that `k8sattributes` and `attributes/add-node-labels` processors are in the pipeline

2. **For Prometheus-scraped metrics**: Add relabeling rules to ServiceMonitors

3. **Verify labels in Prometheus**:
   ```promql
   # Check a metric and see all its labels
   system_cpu_time_seconds_total{k8s_node_name!=""}
   ```

### High Cardinality Issues

If Prometheus is struggling with too many metrics:

1. **Drop unnecessary metrics** via `metricRelabelings` in ServiceMonitors
2. **Reduce collection intervals** (30s → 60s)
3. **Limit metric groups** in kubeletstats receiver
4. **Use recording rules** to aggregate high-cardinality metrics

### Duplicate Metrics

If you see the same metric with different prefixes:
- `system_*` from hostmetrics (OTel)
- `node_*` from node-exporter (Prometheus)
- `container_*` from both kubeletstats and cAdvisor

This is normal - they provide different levels of detail. Choose which source you prefer and drop duplicates if needed.

---

## Summary

Your configuration collects metrics from:

1. **OTel Collectors (Remote Write to Prometheus)**:
   - Host metrics (CPU, memory, disk, network, filesystem, paging, processes) via `hostmetrics` receiver
   - Application OTLP metrics (traces and metrics from instrumented applications)
   - **Note**: kubeletstats receiver is disabled to avoid duplicate sample errors

2. **Prometheus Direct Scraping**:
   - Kubernetes components (API server, scheduler, controller manager, etc.)
   - **Kubelet/cAdvisor** (pod and container metrics - `container_*` prefix)
   - Node exporter (detailed node metrics - `node_*` prefix)
   - Kube-state-metrics (Kubernetes object state - `kube_*` prefix)

## Key Metric Sources by Prefix

| Metric Prefix | Source | Collection Method | What It Measures |
|--------------|--------|-------------------|------------------|
| `system_*` | hostmetrics receiver | OTel DaemonSet → Remote Write | Node-level system metrics (CPU, memory, disk, network) |
| `container_*` | kubelet/cAdvisor | Prometheus scraping | Pod and container resource usage |
| `node_*` | node-exporter | Prometheus scraping | Detailed node metrics (more comprehensive than system_*) |
| `kube_*` | kube-state-metrics | Prometheus scraping | Kubernetes object state and metadata |
| `apiserver_*`, `scheduler_*`, etc. | K8s components | Prometheus scraping | Control plane component metrics |
| Custom app metrics | OTLP instrumented apps | OTel DaemonSet → Remote Write | Application-specific metrics |

## Common Query Patterns

### Pod CPU Usage
```promql
# Using cAdvisor metrics (container_*)
sum by (pod, namespace) (
  rate(container_cpu_usage_seconds_total{container!=""}[5m])
)
```

### Pod Memory Usage
```promql
# Using cAdvisor metrics (container_*)
sum by (pod, namespace) (
  container_memory_working_set_bytes{container!=""}
)
```

### Node CPU Usage
```promql
# Using hostmetrics (system_*)
sum by (k8s_node_name) (
  rate(system_cpu_time_seconds_total{state!="idle"}[5m])
)

# Or using node-exporter (node_*)
1 - avg by (instance) (
  rate(node_cpu_seconds_total{mode="idle"}[5m])
)
```

### Node Memory Usage
```promql
# Using hostmetrics (system_*)
sum by (k8s_node_name) (
  system_memory_usage_bytes{state="used"}
)

# Or using node-exporter (node_*)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
```

All metrics are enriched with Kubernetes metadata and stored in Prometheus for querying in Grafana.
