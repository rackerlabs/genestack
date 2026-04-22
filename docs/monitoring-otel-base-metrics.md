# OpenTelemetry Base Metrics Collection - Complete Reference

This document describes the metrics collected by the current OpenTelemetry + Prometheus configuration and where they come from.

---

## Table of Contents

1. [Metrics Collection Architecture](#metrics-collection-architecture)
2. [OTel Collector Metrics](#otel-collector-metrics)
3. [Infrastructure Metrics](#infrastructure-metrics)
4. [Kubernetes Component Metrics](#kubernetes-component-metrics)
5. [Node and System Metrics](#node-and-system-metrics)
6. [Application Metrics](#application-metrics)
7. [Metric Label Reference](#metric-label-reference)
8. [Troubleshooting](#troubleshooting)

---

## Metrics Collection Architecture

### Collection Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           METRICS SOURCES                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐   ┌─────────────────┐   ┌──────────────────────────┐   │
│  │ Applications    │   │ Host Metrics    │   │ Infra Receivers          │   │
│  │ (OTLP)          │   │ (node-level)    │   │ MySQL / PostgreSQL /     │   │
│  │                 │   │                 │   │ RabbitMQ / Memcached     │   │
│  └────────┬────────┘   └────────┬────────┘   └────────────┬─────────────┘   │
│           │                     │                         │                 │
│           │                     ▼                         │                 │
│           │        ┌──────────────────────────┐           │                 │
│           │        │ OTel Collector DaemonSet │           │                 │
│           │        │   (on each node)         │           │                 │
│           │        └──────────┬───────────────┘           │                 │
│           │                   │                           │                 │
│           └───────────────────┼───────────────┬───────────┘                 │
│                               │               │                             │
│                               ▼               ▼                             │
│                  ┌────────────────────────────────────────┐                 │
│                  │ OTel Collector Deployment              │                 │
│                  │ (cluster-wide OTLP + infra scraping)   │                 │
│                  └──────────────────┬─────────────────────┘                 │
│                                     │                                       │
│                                     ▼                                       │
│                  ┌────────────────────────────────────────┐                 │
│                  │ Prometheus Remote Write                │                 │
│                  │   (:9090/api/v1/write)                 │                 │
│                  └────────────────────────────────────────┘                 │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                PROMETHEUS DIRECT SCRAPING (ServiceMonitors)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   ┌──────────┐  ┌──────────────┐  │
│  │ API      │  │ Scheduler│  │ Ctrl Mgr │   │ CoreDNS  │  │ etcd / Proxy │  │
│  │ Server   │  │          │  │          │   │          │  │ / KSM / Node │  │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘   └────┬─────┘  └──────┬───────┘  │
│        │             │             │             │               │          │
│        └─────────────┼─────────────┼─────────────┼───────────────┘          │
│                      │             │             │                          │
│                      ▼             ▼             ▼                          │
│                    ┌──────────────────────────────┐                         │
│                    │   Prometheus Server (scrape) │                         │
│                    └──────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **OTel Collector DaemonSet**: runs on every node and collects node-local host metrics.
2. **OTel Collector Deployment**: receives OTLP metrics and scrapes infrastructure/service metrics.
3. **Prometheus Server**: scrapes Kubernetes components directly via ServiceMonitors.
4. **Remote Write**: OTel collectors push their metrics into Prometheus via remote write.

### Important Design Notes

- `hostmetrics` is **enabled** in the daemon collector and wired into the daemon metrics pipeline.
- `kubeletMetrics` preset is **disabled** in both collectors.
- Prometheus direct kubelet scraping is also **disabled** because `kubelet.enabled: false`.
- `resource_to_telemetry_conversion` is enabled on the Prometheus remote write exporter, so OTel resource attributes become Prometheus labels.
- `target_info` is disabled on the Prometheus remote write exporter.
- The `httpcheck` receiver is configured with targets, but it is **currently commented out of the deployment metrics pipeline**. Its metric families are documented below so the reference stays complete for the configured receiver.
- `libvirt` metrics are collected by a Prometheus receiver scrape in the daemon collector against a node-local `libvirt_exporter` endpoint and then remote-written to Prometheus.

---

## OTel Collector Metrics

These metrics are collected by the OTel collectors and sent to Prometheus via remote write.

### 1. Host Metrics (from hostmetrics receiver)

**Source**: `hostmetrics` receiver on each node  
**Collector**: OTel DaemonSet  
**Collection Interval**: `30s`  
**Labels**: `k8s_node_name`, `host_name`, `service_instance_id` plus converted resource attributes

#### CPU Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_cpu_time_seconds_total` | Counter | CPU time by state | `cpu`, `state` |
| `system_cpu_utilization_ratio` | Gauge | CPU utilization (0-1) | `cpu`, `state` |
| `system_cpu_load_average_1m` | Gauge | 1-minute load average | - |
| `system_cpu_load_average_5m` | Gauge | 5-minute load average | - |
| `system_cpu_load_average_15m` | Gauge | 15-minute load average | - |

#### Memory Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_memory_usage_bytes` | Gauge | Memory usage by state | `state` |
| `system_memory_utilization_ratio` | Gauge | Memory utilization (0-1) | `state` |

#### Disk Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_disk_io_bytes_total` | Counter | Disk I/O bytes | `device`, `direction` |
| `system_disk_operations_total` | Counter | Disk operations count | `device`, `direction` |
| `system_disk_io_time_seconds_total` | Counter | Disk I/O time | `device` |
| `system_disk_weighted_io_time_seconds_total` | Counter | Weighted I/O time | `device` |
| `system_disk_merged_total` | Counter | Merged operations | `device`, `direction` |
| `system_disk_pending_operations` | Gauge | Pending operations | `device` |

#### Filesystem Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_filesystem_usage_bytes` | Gauge | Filesystem usage by state | `device`, `type`, `mode`, `mountpoint`, `state` |
| `system_filesystem_utilization_ratio` | Gauge | Filesystem utilization (0-1) | `device`, `type`, `mode`, `mountpoint` |
| `system_filesystem_inodes_usage` | Gauge | Inode usage by state | `device`, `type`, `mode`, `mountpoint`, `state` |

**Note**: Excludes pseudo-filesystems and mounts such as `/dev/*`, `/proc/*`, `/sys/*`, `/run/*`, `overlay`, `tmpfs`, `cgroup*`, and similar filesystem types.

#### Network Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_network_io_bytes_total` | Counter | Network I/O bytes | `device`, `direction` |
| `system_network_packets_total` | Counter | Network packets | `device`, `direction` |
| `system_network_errors_total` | Counter | Network errors | `device`, `direction` |
| `system_network_dropped_total` | Counter | Dropped packets | `device`, `direction` |
| `system_network_connections` | Gauge | Network connections | `protocol`, `state` |

#### Paging Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `system_paging_usage_bytes` | Gauge | Swap usage | `device`, `state` |
| `system_paging_operations_total` | Counter | Page in/out operations | `type`, `direction` |
| `system_paging_faults_total` | Counter | Page faults | `type` |

#### Not Collected by hostmetrics in This Config

The following hostmetrics scrapers are **not enabled** in the current configuration:

- `process`
- `processes`

That means this config does **not** collect hostmetrics process metrics such as:

- `system_processes_count`
- `system_processes_created_total`

---

### 2. Libvirt Metrics (from libvirt_exporter via Prometheus receiver)

**Source**: Prometheus receiver scrape job `libvirt` against the node-local `libvirt_exporter` endpoint  
**Collector**: OTel DaemonSet  
**Collection Interval**: `30s`  
**Typical Scrape Target**: `localhost:9474/metrics` (or equivalent node-local endpoint)  
**Labels**: `domain`, `host_name`, `instance_name`, `instance_id`, `project_name`, `project_id`, `user_name`, `user_id`, `flavor_name`, `job`, `instance`, plus converted resource attributes

**Important label note**:
- `instance` is the exporter scrape endpoint (for example `localhost:9474`), not the Nova instance UUID.
- For VM identity and OpenStack metadata, use `libvirt_domain_openstack_info` labels such as `instance_name`, `instance_id`, `project_name`, `user_name`, and `flavor_name`.
- For compute host selection, prefer `host_name`.

#### Inventory and Metadata Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domains` | Gauge | Number of libvirt domains visible to the exporter | - |
| `libvirt_domain_timed_out` | Gauge | Whether scraping metrics for a specific domain timed out | `domain` |
| `libvirt_domain_openstack_info` | Gauge | OpenStack / Nova metadata exported as labels | `domain`, `host_name`, `instance_name`, `instance_id`, `project_name`, `project_id`, `user_name`, `user_id`, `flavor_name` |
| `libvirt_domain_info` | Gauge | Static domain metadata such as OS type and architecture exported as labels | `domain`, `os_type`, `os_type_machine`, `os_type_arch` |
| `libvirt_domain_info_state` | Gauge | Domain state code with descriptive state label | `domain`, `state_desc` |

#### Domain Compute and Memory Overview Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_info_cpu_time_seconds_total` | Counter | Total CPU time consumed by the domain | `domain` |
| `libvirt_domain_info_virtual_cpus` | Gauge | Configured virtual CPU count for the domain | `domain` |
| `libvirt_domain_info_maximum_memory_bytes` | Gauge | Maximum configured memory for the domain | `domain` |
| `libvirt_domain_info_memory_usage_bytes` | Gauge | Current memory usage reported for the domain | `domain` |

#### Domain Memory Stats Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_memory_stats_available_bytes` | Gauge | Memory available to the guest | `domain` |
| `libvirt_domain_memory_stats_current_balloon_bytes` | Gauge | Current balloon size | `domain` |
| `libvirt_domain_memory_stats_disk_caches_bytes` | Gauge | Guest memory used for reclaimable disk cache | `domain` |
| `libvirt_domain_memory_stats_hugetlb_pgalloc_total` | Counter | Successful guest hugepage allocations via balloon reporting | `domain` |
| `libvirt_domain_memory_stats_hugetlb_pgfail_total` | Counter | Failed guest hugepage allocations via balloon reporting | `domain` |
| `libvirt_domain_memory_stats_last_update_timestamp_seconds` | Gauge | Timestamp of the last memory stats update | `domain` |
| `libvirt_domain_memory_stats_major_fault_total` | Counter | Major page faults reported for the domain | `domain` |
| `libvirt_domain_memory_stats_maximum_bytes` | Gauge | Maximum guest memory available to the domain | `domain` |
| `libvirt_domain_memory_stats_minor_fault_total` | Counter | Minor page faults reported for the domain | `domain` |
| `libvirt_domain_memory_stats_rss_bytes` | Gauge | Resident set size of the process backing the domain | `domain` |
| `libvirt_domain_memory_stats_swap_in_bytes` | Counter | Bytes swapped into guest memory | `domain` |
| `libvirt_domain_memory_stats_swap_out_bytes` | Counter | Bytes swapped out from guest memory | `domain` |
| `libvirt_domain_memory_stats_unused_bytes` | Gauge | Unused memory inside the guest | `domain` |
| `libvirt_domain_memory_stats_usable_bytes` | Gauge | Usable guest memory, similar to Linux `MemAvailable` | `domain` |
| `libvirt_domain_memory_stats_used_percent` | Gauge | Guest memory utilization percentage | `domain` |

#### Block Device Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_block_stats_info` | Gauge | Block device metadata exported as labels | `domain`, `disk_type`, `driver_cache`, `driver_discard`, `driver_name`, `driver_type`, `serial`, `source_file`, `target_bus`, `target_device` |
| `libvirt_domain_block_stats_capacity_bytes` | Gauge | Logical capacity of the block device backing image | `domain`, `target_device` |
| `libvirt_domain_block_stats_flush_requests_total` | Counter | Flush requests issued to the block device | `domain`, `target_device` |
| `libvirt_domain_block_stats_flush_time_seconds_total` | Counter | Time spent flushing the block device cache | `domain`, `target_device` |
| `libvirt_domain_block_stats_read_bytes_total` | Counter | Bytes read from the block device | `domain`, `target_device` |
| `libvirt_domain_block_stats_read_requests_total` | Counter | Read requests issued to the block device | `domain`, `target_device` |
| `libvirt_domain_block_stats_read_time_seconds_total` | Counter | Time spent in block reads | `domain`, `target_device` |
| `libvirt_domain_block_stats_write_bytes_total` | Counter | Bytes written to the block device | `domain`, `target_device` |
| `libvirt_domain_block_stats_write_requests_total` | Counter | Write requests issued to the block device | `domain`, `target_device` |
| `libvirt_domain_block_stats_write_time_seconds_total` | Counter | Time spent in block writes | `domain`, `target_device` |

#### Network Interface Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_interface_stats_info` | Gauge | Interface metadata exported as labels | `domain`, `interface_type`, `mac_address`, `model_type`, `mtu_size`, `source_bridge`, `target_device` |
| `libvirt_domain_interface_stats_receive_bytes_total` | Counter | Bytes received on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_receive_drops_total` | Counter | Dropped received packets on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_receive_errors_total` | Counter | Receive errors on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_receive_packets_total` | Counter | Packets received on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_transmit_bytes_total` | Counter | Bytes transmitted on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_transmit_drops_total` | Counter | Dropped transmitted packets on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_transmit_errors_total` | Counter | Transmit errors on the guest interface | `domain`, `target_device` |
| `libvirt_domain_interface_stats_transmit_packets_total` | Counter | Packets transmitted on the guest interface | `domain`, `target_device` |

#### Domain Job Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_job_info_data_processed_bytes` | Gauge | Data bytes already processed by the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_data_remaining_bytes` | Gauge | Data bytes remaining for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_data_total_bytes` | Gauge | Total data bytes for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_file_processed_bytes` | Gauge | File bytes already processed by the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_file_remaining_bytes` | Gauge | File bytes remaining for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_file_total_bytes` | Gauge | Total file bytes for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_memory_processed_bytes` | Gauge | Memory bytes already processed by the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_memory_remaining_bytes` | Gauge | Memory bytes remaining for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_memory_total_bytes` | Gauge | Total memory bytes for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_time_elapsed_seconds` | Gauge | Time elapsed for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_time_remaining_seconds` | Gauge | Estimated time remaining for the active domain job | `domain`, `host_name` |
| `libvirt_domain_job_info_type` | Gauge | Domain job type code | `domain`, `host_name` |

**Note**: Domain job metrics are most useful during live migration, block copy, or other active libvirt jobs. It is normal for job-oriented panels to be sparse or empty when no domain jobs are running.

#### vCPU Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `libvirt_domain_vcpu_current` | Gauge | Number of currently online vCPUs for the domain | `domain` |
| `libvirt_domain_vcpu_delay_seconds_total` | Counter | Time a vCPU spent delayed in the run queue | `domain`, `vcpu` |
| `libvirt_domain_vcpu_maximum` | Gauge | Maximum number of vCPUs allowed for the domain | `domain` |
| `libvirt_domain_vcpu_state` | Gauge | Per-vCPU state code | `domain`, `vcpu`, `state_desc` |
| `libvirt_domain_vcpu_time_seconds_total` | Counter | CPU time used by a specific vCPU | `domain`, `vcpu` |
| `libvirt_domain_vcpu_wait_seconds_total` | Counter | Time a specific vCPU spent waiting | `domain`, `vcpu` |

### 3. OTLP Application Metrics

**Source**: Applications sending metrics to OTel collector via OTLP  
**Collector**: OTel Deployment

**Endpoints**:
- gRPC: `:4317`
- HTTP: `:4318`

Applications instrumented with OpenTelemetry SDKs can send custom metrics. These vary by application, but commonly include:

- Request counts
- Request durations
- Error counts/rates
- Business metrics
- Application-specific resource and usage metrics

**Metadata enrichment**:
- Resource attributes are preserved and converted to Prometheus labels by remote write
- Kubernetes metadata is added where available through the `k8sattributes` processor

---

### 4. kubeletstats Metrics (DISABLED)

**Status**: ⚠️ **DISABLED**

The `kubeletMetrics` preset is disabled in both the daemon and deployment collectors, so OTel is **not** collecting `k8s_pod_*` / `k8s_container_*` metrics from the kubeletstats receiver.

---

### 5. HTTP Endpoint Check Metrics

**Source**: `httpcheck` receiver  
**Collector**: OTel Deployment  
**Configured Collection Interval**: `30s`  
**Configured Targets**:
- `https://nova.api.example.com`
- `https://neutron.api.example.com`
- `https://keystone.api.example.com`
- `https://octavia.api.example.com`
- `https://glance.api.example.com`
- `https://heat.api.example.com`
- `https://cinder.api.example.com`
- `https://cloudformation.api.example.com`
- `https://placement.api.example.com`
- `https://barbican.api.example.com`
- `https://magnum.api.example.com`
- `https://masakari.api.example.com`
- `https://novnc.api.example.com/vnc_auto.html`

#### HTTP Check Metric Families

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `httpcheck.status` | Gauge | Result of the HTTP endpoint check, typically success/failure state | `target`, `method`, others |
| `httpcheck.duration` | Gauge | Total check duration | `target`, `method`, others |
| `httpcheck.dns_duration` | Gauge | DNS lookup duration | `target`, `method`, others |
| `httpcheck.connect_duration` | Gauge | TCP connect duration | `target`, `method`, others |
| `httpcheck.tls_duration` | Gauge | TLS handshake duration for HTTPS targets | `target`, `method`, others |
| `httpcheck.first_byte_duration` | Gauge | Time to first byte | `target`, `method`, others |
| `httpcheck.response_duration` | Gauge | Response read duration | `target`, `method`, others |

#### Optional TLS Certificate Metrics

Depending on receiver options, HTTP/TLS checking can also expose certificate-related metrics such as certificate expiry timing. Those are not explicitly enabled in the pasted config, so they should be treated as optional rather than guaranteed.

#### Current Status in This Config

The receiver is configured, but it is currently commented out in the deployment collector metrics pipeline:

```yaml
#              - httpcheck # uncomment to add endpoint checking metrics with above endpoint config...
```

So the receiver and target list are defined, but **its metrics are not currently emitted until it is uncommented in the pipeline**.

---

## Infrastructure Metrics

These metrics are collected by the OTel deployment collector and remote-written to Prometheus.

### 1. MySQL Metrics

**Source**: `mysql` receiver  
**Collector**: OTel Deployment  
**Endpoint**: `mariadb-cluster-internal.openstack.svc.cluster.local:3306`  
**Collection Interval**: `30s`

Enabled metric families:

| Metric Name | Type | Description |
|-------------|------|-------------|
| `mysql.connection.count` | Gauge / Sum | Current and cumulative connection metrics |
| `mysql.connection.errors` | Sum | MySQL connection error counters |
| `mysql.commands` | Sum | Command execution counters by command type |
| `mysql.buffer_pool.usage` | Gauge | InnoDB buffer pool usage |
| `mysql.threads` | Gauge | MySQL thread counts |
| `mysql.locks` | Gauge / Sum | Lock-related MySQL metrics |

**Notes**:
- Exact emitted series depend on the MySQL server status variables available.
- These are OpenTelemetry semantic metric names before export; Prometheus naming may reflect translation by the exporter.

---

### 2. PostgreSQL Metrics

**Source**: `postgresql` receiver  
**Collector**: OTel Deployment  
**Endpoint**: `postgres-cluster.openstack.svc.cluster.local:5432`  
**Collection Interval**: `30s`

Enabled metric families:

| Metric Name | Type | Description |
|-------------|------|-------------|
| `postgresql.backends` | Gauge | PostgreSQL backend connections |
| `postgresql.commits` | Sum | Transaction commits |
| `postgresql.rollbacks` | Sum | Transaction rollbacks |
| `postgresql.db_size` | Gauge | Database size |
| `postgresql.deadlocks` | Sum | Deadlock count |
| `postgresql.blocks_read` | Sum | Blocks read from disk |

**Notes**:
- Exact labels vary by database and server version.
- Only the explicitly enabled PostgreSQL metrics are collected.

---

### 3. RabbitMQ Metrics

**Source**: `rabbitmq` receiver  
**Collector**: OTel Deployment  
**Endpoint**: `http://rabbitmq.openstack.svc.cluster.local:15672`  
**Collection Interval**: `30s`

Enabled metric families:

| Metric Name | Type | Description |
|-------------|------|-------------|
| `rabbitmq.node.disk_free` | Gauge | Free disk space on the node |
| `rabbitmq.node.disk_free_limit` | Gauge | Configured disk free limit |
| `rabbitmq.node.disk_free_alarm` | Gauge | Whether disk free alarm is active |
| `rabbitmq.node.mem_used` | Gauge | Memory used |
| `rabbitmq.node.mem_limit` | Gauge | Memory limit |
| `rabbitmq.node.mem_alarm` | Gauge | Whether memory alarm is active |
| `rabbitmq.node.fd_used` | Gauge | File descriptors used |
| `rabbitmq.node.fd_total` | Gauge | File descriptor limit |
| `rabbitmq.node.sockets_used` | Gauge | Sockets used |
| `rabbitmq.node.sockets_total` | Gauge | Socket limit |
| `rabbitmq.node.proc_used` | Gauge | Erlang processes used |
| `rabbitmq.node.proc_total` | Gauge | Erlang process limit |
| `rabbitmq.node.disk_free_details.rate` | Gauge | Disk free change rate |
| `rabbitmq.node.fd_used_details.rate` | Gauge | File descriptor usage rate |
| `rabbitmq.node.mem_used_details.rate` | Gauge | Memory usage rate |
| `rabbitmq.node.proc_used_details.rate` | Gauge | Process usage rate |
| `rabbitmq.node.sockets_used_details.rate` | Gauge | Socket usage rate |

---

### 4. Memcached Metrics

**Source**: `memcached` receiver  
**Collector**: OTel Deployment  
**Endpoint**: `memcached.openstack.svc.cluster.local:11211`  
**Transport**: `tcp`  
**Collection Interval**: `30s`

Enabled metric families:

| Metric Name | Type | Description |
|-------------|------|-------------|
| `memcached.operation_hit_ratio` | Gauge | Cache hit ratio |
| `memcached.current_items` | Gauge | Current item count |
| `memcached.evictions` | Sum | Eviction count |
| `memcached.bytes` | Gauge | Memory bytes used by memcached |

---

### 5. cert-manager Metrics

**Source**: Prometheus receiver scrape job `cert-manager`  
**Collector**: OTel Deployment  
**Discovery**: Kubernetes pod discovery in namespace `cert-manager`  
**Selection**: Pods annotated with `prometheus.io/scrape: "true"`

This scrape job keeps pods in `cert-manager` where annotation-based scraping is enabled and respects annotated path/port overrides.

Common metric families expected from cert-manager components:

#### Certificate Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `certmanager_certificate_expiration_timestamp_seconds` | Gauge | Certificate expiration time as Unix timestamp | `name`, `namespace`, issuer labels |
| `certmanager_certificate_renewal_timestamp_seconds` | Gauge | Scheduled certificate renewal time | `name`, `namespace`, issuer labels |
| `certmanager_certificate_ready_status` | Gauge | Whether the certificate is ready | `name`, `namespace`, `condition` |

#### Controller / Runtime Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `certmanager_controller_sync_call_count` | Counter | Controller sync call count | `controller` |
| `certmanager_controller_sync_call_duration_seconds` | Histogram | Sync duration | `controller` |
| `certmanager_controller_sync_error_count` | Counter | Sync error count | `controller` |
| `go_*` | Various | Go runtime metrics | Varies |
| `process_*` | Various | Process metrics | Varies |
| `controller_runtime_*` | Various | Controller runtime metrics | Varies |

**Notes**:
- Actual cert-manager metric set depends on which components expose `/metrics`.
- This config discovers pods by annotations rather than fixed ServiceMonitors.

---

### 6. MetalLB Metrics

**Source**: Prometheus receiver scrape job `metallb`  
**Collector**: OTel Deployment  
**Discovery**: Kubernetes pod discovery in namespace `metallb-system`  
**Selection**:
- `app.kubernetes.io/component=controller|speaker`
- container port `7472`

#### Allocator Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_allocator_addresses_in_use_total` | Gauge | IP addresses in use per pool | `pool` |
| `metallb_allocator_addresses_total` | Gauge | Total usable IPs per pool | `pool` |

#### Config / Kubernetes Client Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_k8s_client_updates_total` | Counter | Kubernetes object updates processed | Varies |
| `metallb_k8s_client_update_errors_total` | Counter | Update failures | Varies |
| `metallb_k8s_client_config_loaded_bool` | Gauge | Config loaded successfully at least once | - |
| `metallb_k8s_client_config_stale_bool` | Gauge | Running with stale config | - |

#### BGP Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_bgp_session_up` | Gauge | BGP session state | `peer` |
| `metallb_bgp_updates_total` | Counter | BGP UPDATE messages sent | `peer`, `vrf` |
| `metallb_bgp_announced_prefixes_total` | Gauge | Advertised prefixes | `peer`, `vrf` |

#### FRR-only Metrics (if FRR mode is in use)

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_bgp_opens_sent` | Counter | BGP OPEN messages sent | `peer`, `vrf` |
| `metallb_bgp_opens_received` | Counter | BGP OPEN messages received | `peer`, `vrf` |
| `metallb_bgp_notifications_sent` | Counter | BGP NOTIFICATION messages sent | `peer`, `vrf` |
| `metallb_bgp_updates_total_received` | Counter | BGP UPDATE messages received | `peer`, `vrf` |
| `metallb_bgp_keepalives_sent` | Counter | KEEPALIVE messages sent | `peer`, `vrf` |
| `metallb_bgp_keepalives_received` | Counter | KEEPALIVE messages received | `peer`, `vrf` |
| `metallb_bgp_route_refresh_sent` | Counter | Route refresh messages sent | `peer`, `vrf` |
| `metallb_bgp_total_sent` | Counter | Total BGP messages sent | `peer`, `vrf` |
| `metallb_bgp_total_received` | Counter | Total BGP messages received | `peer`, `vrf` |
| `metallb_bfd_session_up` | Gauge | BFD session state | `peer`, `vrf` |
| `metallb_bfd_control_packet_input` | Counter | Received BFD control packets | `peer`, `vrf` |
| `metallb_bfd_control_packet_output` | Counter | Sent BFD control packets | `peer`, `vrf` |

#### Runtime Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `go_*` | Various | Go runtime metrics | Varies |
| `process_*` | Various | Process metrics | Varies |
| `controller_runtime_*` | Various | Controller-runtime metrics | Varies |

---

### 7. OVN / Kube-OVN Metrics

**Source**: Prometheus receiver scrape jobs:
- `kube-ovn-monitor`
- `kube-ovn-controller`
- `kube-ovn-cni`
- `kube-ovn-pinger`

**Collector**: OTel Deployment  
**Discovery**: Kubernetes endpoints in namespace `kube-system`  
**Selection**:
- service name matches the target service
- endpoint port name `metrics`

This config now explicitly scrapes these Kube-OVN services:

- `kube-ovn-monitor`
- `kube-ovn-controller`
- `kube-ovn-cni`
- `kube-ovn-pinger`

#### 7.1 OVN Monitor Metrics (`kube-ovn-monitor`)

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `kube_ovn_ovn_status` | Gauge | OVN health status: follower/standby=2, leader/active=1, unhealthy=0 | Varies |
| `kube_ovn_failed_req_count` | Gauge | Failed requests to OVN stack | Varies |
| `kube_ovn_log_file_size` | Gauge | OVN log file size | `component` |
| `kube_ovn_db_file_size` | Gauge | OVN database file size | `component` |
| `kube_ovn_chassis_info` | Gauge | Chassis state/metadata | `chassis`, others |
| `kube_ovn_db_status` | Gauge | OVN NB/SB DB health | `db` |
| `kube_ovn_logical_switch_info` | Gauge | Logical switch metadata | `logical_switch` |
| `kube_ovn_logical_switch_external_id` | Gauge | Logical switch external IDs | `logical_switch`, `key`, `value` |
| `kube_ovn_logical_switch_port_binding` | Gauge | Logical switch to port binding | `logical_switch`, `port` |
| `kube_ovn_logical_switch_tunnel_key` | Gauge | Tunnel key for logical switch | `logical_switch` |
| `kube_ovn_logical_switch_ports_num` | Gauge | Number of ports on logical switch | `logical_switch` |
| `kube_ovn_logical_switch_port_info` | Gauge | Logical switch port metadata | `logical_switch`, `port` |
| `kube_ovn_logical_switch_port_tunnel_key` | Gauge | Tunnel key for logical switch port | `logical_switch`, `port` |
| `kube_ovn_cluster_enabled` | Gauge | Whether clustering is enabled | - |
| `kube_ovn_cluster_role` | Gauge | Cluster server role | `role` |
| `kube_ovn_cluster_status` | Gauge | Cluster server status | `status` |
| `kube_ovn_cluster_term` | Gauge | Current raft term | - |
| `kube_ovn_cluster_leader_self` | Gauge | Whether this server is leader | - |
| `kube_ovn_cluster_vote_self` | Gauge | Whether this server voted for itself | - |
| `kube_ovn_cluster_election_timer` | Gauge | Election timer value | - |
| `kube_ovn_cluster_log_not_committed` | Gauge | Log entries not committed | - |
| `kube_ovn_cluster_log_not_applied` | Gauge | Log entries not applied | - |
| `kube_ovn_cluster_log_index_start` | Gauge | Log start index | - |
| `kube_ovn_cluster_log_index_next` | Gauge | Next log index | - |
| `kube_ovn_cluster_inbound_connections_total` | Gauge | Inbound connections | - |
| `kube_ovn_cluster_outbound_connections_total` | Gauge | Outbound connections | - |
| `kube_ovn_cluster_inbound_connections_error_total` | Gauge | Failed inbound connections | - |
| `kube_ovn_cluster_outbound_connections_error_total` | Gauge | Failed outbound connections | - |

#### 7.2 OVS Monitor Metrics (`kube-ovn-monitor`)

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `ovs_status` | Gauge | OVS health state | - |
| `ovs_info` | Gauge | OVS metadata | Varies |
| `failed_req_count` | Gauge | Failed requests to OVS stack | - |
| `log_file_size` | Gauge | OVS log file size | `component` |
| `db_file_size` | Gauge | OVS database file size | `component` |
| `datapath` | Gauge | Datapath marker | `datapath` |
| `dp_total` | Gauge | Total datapaths | - |
| `dp_if` | Gauge | Datapath interface marker | `datapath`, `interface` |
| `dp_if_total` | Gauge | Interfaces per datapath | `datapath` |
| `dp_flows_total` | Gauge | Flow count | `datapath` |
| `dp_flows_lookup_hit` | Gauge | Flow lookup hits | `datapath` |
| `dp_flows_lookup_missed` | Gauge | Flow lookup misses | `datapath` |
| `dp_flows_lookup_lost` | Gauge | Lost packets | `datapath` |
| `dp_masks_hit` | Gauge | Mask visits | `datapath` |
| `dp_masks_total` | Gauge | Mask count | `datapath` |
| `dp_masks_hit_ratio` | Gauge | Average mask visits per packet | `datapath` |
| `interface` | Gauge | Interface marker | `interface` |
| `interface_admin_state` | Gauge | Interface admin state | `interface` |
| `interface_link_state` | Gauge | Interface link state | `interface` |
| `interface_mac_in_use` | Gauge | MAC in use | `interface`, `mac` |
| `interface_mtu` | Gauge | Interface MTU | `interface` |
| `interface_of_port` | Gauge | OpenFlow port ID | `interface` |
| `interface_if_index` | Gauge | Interface index | `interface` |
| `interface_tx_packets` | Gauge | TX packets | `interface` |
| `interface_tx_bytes` | Gauge | TX bytes | `interface` |
| `interface_tx_error` | Gauge | TX error count | `interface` |
| `interface_rx_packets` | Gauge | RX packets | `interface` |
| `interface_rx_bytes` | Gauge | RX bytes | `interface` |
| `interface_rx_errors` | Gauge | RX errors | `interface` |
| `interface_rx_dropped` | Gauge | RX drops | `interface` |
| `interface_rx_frame_err` | Gauge | RX frame errors | `interface` |
| `interface_rx_over_err` | Gauge | RX overrun errors | `interface` |
| `interface_tx_dropped` | Gauge | TX drops | `interface` |
| `interface_tx_errors` | Gauge | TX errors | `interface` |
| `interface_collisions` | Gauge | Interface collisions | `interface` |

#### 7.3 kube-ovn-controller Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `rest_client_request_latency_seconds` | Histogram | Request latency in seconds | `verb`, `url` |
| `rest_client_requests_total` | Counter | Number of HTTP requests | `code`, `method`, `host` |
| `lists_total` | Counter | Total number of API lists done by reflectors | `name` |
| `list_duration_seconds` | Summary | Duration of reflector list calls | `name` |
| `items_per_list` | Summary | Number of items returned per list call | `name` |
| `watches_total` | Counter | Total number of API watches done by reflectors | `name` |
| `short_watches_total` | Counter | Total number of short API watches done by reflectors | `name` |
| `watch_duration_seconds` | Summary | Duration of reflector watch calls | `name` |
| `items_per_watch` | Summary | Number of items returned per watch call | `name` |
| `last_resource_version` | Gauge | Last resource version seen by reflectors | `name` |
| `ovs_client_request_latency_milliseconds` | Histogram | Latency histogram for OVS requests | `method` |
| `subnet_available_ip_count` | Gauge | Available IP count in subnet | `subnet` |
| `subnet_used_ip_count` | Gauge | Used IP count in subnet | `subnet` |

#### 7.4 kube-ovn-cni Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `cni_op_latency_seconds` | Histogram | CNI operation latency | `operation` |
| `cni_wait_address_seconds_total` | Counter | Time waiting for controller to assign an address | `operation` |
| `cni_wait_connectivity_seconds_total` | Counter | Time waiting for address readiness in overlay network | `operation` |
| `cni_wait_route_seconds_total` | Counter | Time waiting for routed annotation to be added to pod | `operation` |
| `rest_client_request_latency_seconds` | Histogram | Request latency in seconds | `verb`, `url` |

#### 7.5 kube-ovn-pinger Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `pinger_ovs_up` | Gauge | Whether OVS on the node is up | `node` |
| `pinger_ovs_down` | Gauge | Whether OVS on the node is down | `node` |
| `pinger_ovn_controller_up` | Gauge | Whether `ovn_controller` on the node is up | `node` |
| `pinger_ovn_controller_down` | Gauge | Whether `ovn_controller` on the node is down | `node` |
| `pinger_inconsistent_port_binding` | Gauge | Number of mismatched port bindings between OVS and OVN-SB | `node` |
| `pinger_apiserver_healthy` | Gauge | Whether API server requests are healthy on this node | `node` |
| `pinger_apiserver_unhealthy` | Gauge | Whether API server requests are unhealthy on this node | `node` |
| `pinger_apiserver_latency_ms` | Histogram | API server request latency from this node | `node` |
| `pinger_internal_dns_healthy` | Gauge | Whether internal DNS requests are healthy on this node | `node` |
| `pinger_internal_dns_unhealthy` | Gauge | Whether internal DNS requests are unhealthy on this node | `node` |
| `pinger_internal_dns_latency_ms` | Histogram | Internal DNS request latency from this node | `node` |
| `pinger_external_dns_health` | Gauge | Whether external DNS requests are healthy on this node | `node` |
| `pinger_external_dns_unhealthy` | Gauge | Whether external DNS requests are unhealthy on this node | `node` |
| `pinger_external_dns_latency_ms` | Histogram | External DNS request latency from this node | `node` |
| `pinger_pod_ping_latency_ms` | Histogram | Pod-to-pod ping latency | `src`, `dst`, others |
| `pinger_pod_ping_lost_total` | Gauge | Lost packet count for pod-to-pod ping | `src`, `dst` |
| `pinger_pod_ping_count_total` | Gauge | Total packet count for pod-to-pod ping | `src`, `dst` |
| `pinger_node_ping_latency_ms` | Histogram | Pod-to-node ping latency | `src`, `dst`, others |
| `pinger_node_ping_lost_total` | Gauge | Lost packet count for pod-to-node ping | `src`, `dst` |
| `pinger_node_ping_count_total` | Gauge | Total packet count for pod-to-node ping | `src`, `dst` |
| `pinger_external_ping_latency_ms` | Histogram | Pod-to-external-address ping latency | `target`, others |
| `pinger_external_lost_total` | Gauge | Lost packet count for external ping | `target` |

---

## Kubernetes Component Metrics

These metrics are scraped **directly by Prometheus** via ServiceMonitors, not by OTel.

### 1. API Server Metrics

**Source**: `kube-apiserver`  
**Status**: ✅ enabled  
**Endpoint**: `https://kubernetes.default.svc:443/metrics`

Common metrics:
- `apiserver_request_total`
- `apiserver_request_duration_seconds`
- `apiserver_request_sli_duration_seconds`
- `apiserver_current_inflight_requests`
- `apiserver_longrunning_requests`
- `apiserver_response_sizes`
- `apiserver_storage_objects`
- `apiserver_audit_event_total`
- `etcd_request_duration_seconds`
- `etcd_db_total_size_in_bytes`

**Note**: Some `apiserver_request_duration_seconds_bucket` buckets are intentionally dropped by metric relabeling.

---

### 2. Scheduler Metrics

**Source**: `kube-scheduler`  
**Status**: ✅ enabled  
**Endpoint**: `https://:10259/metrics`

Common metrics:
- `scheduler_queue_incoming_pods_total`
- `scheduler_scheduling_attempt_duration_seconds`
- `scheduler_e2e_scheduling_duration_seconds`
- `scheduler_pod_scheduling_attempts`
- `scheduler_pending_pods`
- `scheduler_framework_extension_point_duration_seconds`
- `scheduler_schedule_attempts_total`
- `scheduler_preemption_attempts_total`

---

### 3. Controller Manager Metrics

**Source**: `kube-controller-manager`  
**Status**: ✅ enabled  
**Endpoint**: `https://:10257/metrics`

Common metrics:
- `workqueue_adds_total`
- `workqueue_depth`
- `workqueue_queue_duration_seconds`
- `workqueue_work_duration_seconds`
- `workqueue_retries_total`

---

### 4. CoreDNS Metrics

**Source**: `coredns`  
**Status**: ✅ enabled  
**Endpoint**: `http://:9153/metrics`

Common metrics:
- `coredns_dns_request_duration_seconds`
- `coredns_dns_requests_total`
- `coredns_dns_responses_total`
- `coredns_forward_requests_total`
- `coredns_cache_hits_total`
- `coredns_cache_misses_total`

---

### 5. etcd Metrics

**Source**: `etcd`  
**Status**: ✅ enabled  
**Endpoint**: `http://:2381/metrics`

Common metrics:
- `etcd_server_proposals_committed_total`
- `etcd_server_proposals_applied_total`
- `etcd_server_proposals_pending`
- `etcd_server_proposals_failed_total`
- `etcd_disk_wal_fsync_duration_seconds`
- `etcd_disk_backend_commit_duration_seconds`
- `etcd_network_peer_round_trip_time_seconds`
- `etcd_mvcc_db_total_size_in_bytes`

---

### 6. Kube Proxy Metrics

**Source**: `kube-proxy`  
**Status**: ✅ enabled  
**Endpoint**: `http://:10249/metrics`

Common metrics:
- `kubeproxy_sync_proxy_rules_duration_seconds`
- `kubeproxy_network_programming_duration_seconds`
- `rest_client_requests_total`
- `rest_client_request_duration_seconds`

---

### 7. Kubelet Metrics

**Source**: `kubelet`  
**Status**: ❌ disabled

Although a `kubelet:` block exists with ServiceMonitor options, the current config sets:

```yaml
kubelet:
  enabled: false
```

So Prometheus is **not currently scraping kubelet** and is **not collecting**:

- kubelet `/metrics`
- kubelet `/metrics/cadvisor`

That means `container_*` cAdvisor metrics are **not currently part of this base config** unless enabled elsewhere.

---

## Node and System Metrics

### 1. Node Exporter Metrics

**Source**: `node-exporter` DaemonSet  
**Status**: ✅ enabled  
**Endpoint**: `http://:9100/metrics`

#### CPU Metrics
- `node_cpu_seconds_total`
- `node_load1`, `node_load5`, `node_load15`
- `node_procs_running`
- `node_procs_blocked`

#### Memory Metrics
- `node_memory_MemTotal_bytes`
- `node_memory_MemFree_bytes`
- `node_memory_MemAvailable_bytes`
- `node_memory_Buffers_bytes`
- `node_memory_Cached_bytes`
- `node_memory_SwapTotal_bytes`
- `node_memory_SwapFree_bytes`

#### Disk Metrics
- `node_disk_io_time_seconds_total`
- `node_disk_read_bytes_total`
- `node_disk_written_bytes_total`
- `node_disk_reads_completed_total`
- `node_disk_writes_completed_total`

#### Filesystem Metrics
- `node_filesystem_size_bytes`
- `node_filesystem_free_bytes`
- `node_filesystem_avail_bytes`
- `node_filesystem_files`
- `node_filesystem_files_free`

#### Network Metrics
- `node_network_receive_bytes_total`
- `node_network_transmit_bytes_total`
- `node_network_receive_packets_total`
- `node_network_transmit_packets_total`
- `node_network_receive_errs_total`
- `node_network_transmit_errs_total`
- `node_network_receive_drop_total`
- `node_network_transmit_drop_total`

#### System Metrics
- `node_time_seconds`
- `node_boot_time_seconds`
- `node_context_switches_total`
- `node_forks_total`
- `node_intr_total`

**Notes**:
- Node exporter excludes many pseudo-filesystems and ephemeral mount paths.
- Textfile collector is enabled at `/var/lib/node_exporter/textfile_collector`.

---

### 2. Kube State Metrics

**Source**: `kube-state-metrics` Deployment  
**Status**: ✅ enabled  
**Endpoint**: `http://:8080/metrics`

#### Pod Metrics
- `kube_pod_info`
- `kube_pod_status_phase`
- `kube_pod_status_ready`
- `kube_pod_container_status_ready`
- `kube_pod_container_status_restarts_total`
- `kube_pod_labels`
- `kube_pod_owner`

#### Deployment Metrics
- `kube_deployment_status_replicas`
- `kube_deployment_status_replicas_available`
- `kube_deployment_status_replicas_unavailable`
- `kube_deployment_spec_replicas`
- `kube_deployment_metadata_generation`

#### Node Metrics
- `kube_node_info`
- `kube_node_status_condition`
- `kube_node_status_allocatable`
- `kube_node_status_capacity`
- `kube_node_spec_unschedulable`

#### StatefulSet Metrics
- `kube_statefulset_status_replicas`
- `kube_statefulset_status_replicas_ready`
- `kube_statefulset_replicas`

#### DaemonSet Metrics
- `kube_daemonset_status_number_ready`
- `kube_daemonset_status_desired_number_scheduled`
- `kube_daemonset_status_number_available`

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

If OpenStack services are instrumented to send OTLP metrics, they are accepted by the deployment collector and forwarded to Prometheus.

These may include:
- API request counts
- API request durations
- Error counters
- Business metrics
- Internal worker / queue metrics
- Custom service metrics

### OpenStack Platform Service Metrics (via Specialized Receivers)

In addition to OTLP application metrics, this config also collects infrastructure/service metrics from core platform backends:

- MariaDB / MySQL
- PostgreSQL
- RabbitMQ
- Memcached

### OpenStack Endpoint Availability Metrics (via HTTP Check Receiver)

The config also defines synthetic HTTP endpoint checks for major OpenStack APIs. Even though the receiver is currently commented out of the active pipeline, the configured targets and expected metric families are part of the documented telemetry design.

---

## Metric Label Reference

### Common Labels Added by OTel Collectors

| Label | Source | Description |
|-------|--------|-------------|
| `k8s_node_name` | resource attribute conversion | Kubernetes node name |
| `host_name` | attributes / resource conversion | Host name, set from node name in daemon collector |
| `service_instance_id` | attributes / resource conversion | Node name used as service instance ID |
| `k8s_namespace_name` | k8sattributes | Kubernetes namespace |
| `k8s_pod_name` | k8sattributes | Pod name |
| `k8s_pod_uid` | k8sattributes | Pod UID |
| `k8s_deployment_name` | k8sattributes | Deployment name |
| `k8s_statefulset_name` | k8sattributes | StatefulSet name |
| `k8s_daemonset_name` | k8sattributes | DaemonSet name |
| `k8s_job_name` | k8sattributes | Job name |
| `k8s_cronjob_name` | k8sattributes | CronJob name |
| `k8s_container_name` | k8sattributes | Container name |
| `app` | pod label extraction | `app` pod label |
| `app_kubernetes_io_name` | pod label extraction | `app.kubernetes.io/name` |
| `app_kubernetes_io_component` | pod label extraction | `app.kubernetes.io/component` |
| `app_kubernetes_io_instance` | pod label extraction | `app.kubernetes.io/instance` |
| `app_kubernetes_io_version` | pod label extraction | `app.kubernetes.io/version` |
| `deployment_environment` | attributes processor | Fixed value: `genestack` |
| `k8s_cluster_name` | attributes processor | Fixed cluster name |

### Additional Labels Common on Infrastructure Metrics

| Label | Source | Description |
|-------|--------|-------------|
| `component` | relabeling / scraped metrics | Component name such as `controller`, `speaker`, `webhook` |
| `namespace` | Prometheus SD / relabeling | Kubernetes namespace of target |
| `pod` | Prometheus SD / relabeling | Pod name of target |
| `service` | Prometheus SD / relabeling | Service name |
| `peer` | MetalLB metrics | BGP/BFD peer |
| `pool` | MetalLB metrics | Address pool |
| `vrf` | MetalLB metrics | VRF |
| `controller` | cert-manager metrics | cert-manager controller name |
| `subnet` | Kube-OVN metrics | Subnet identifier |
| `logical_switch` | Kube-OVN metrics | OVN logical switch |
| `interface` | Kube-OVN / OVS metrics | Interface label |
| `db` | Kube-OVN metrics | DB name/type |
| `node` | Kube-OVN / Prometheus | Node associated with metric |
| `target` | HTTP check receiver | Endpoint being checked |
| `method` | HTTP check receiver | HTTP method used for the check |
| `domain` | libvirt exporter | Libvirt domain identifier, often OpenStack `instance-...` |
| `instance_name` | `libvirt_domain_openstack_info` | OpenStack / Nova server name |
| `instance_id` | `libvirt_domain_openstack_info` | OpenStack / Nova server UUID |
| `project_name` | `libvirt_domain_openstack_info` | OpenStack project / tenant identifier or name |
| `project_id` | `libvirt_domain_openstack_info` | OpenStack project UUID |
| `user_name` | `libvirt_domain_openstack_info` | OpenStack user name |
| `user_id` | `libvirt_domain_openstack_info` | OpenStack user identifier |
| `flavor_name` | `libvirt_domain_openstack_info` | OpenStack flavor associated with the domain |
| `state_desc` | libvirt exporter | Human-readable libvirt state label for a domain or vCPU |
| `target_device` | libvirt exporter | Guest block device or interface device name |
| `vcpu` | libvirt exporter | Virtual CPU index within a domain |

### Labels from Prometheus ServiceMonitors

| Label | Description |
|-------|-------------|
| `instance` | Scrape target address |
| `job` | Job name |
| `endpoint` | Endpoint name |
| `service` | Service name |
| `namespace` | Namespace |
| `pod` | Pod name, when available |
| `node` | Node name, when added by relabeling |

**Libvirt-specific note**: for the libvirt scrape job, `instance` is typically the exporter endpoint (for example `localhost:9474`) and should not be treated as the VM UUID. For dashboard filtering and joins, prefer `host_name` for compute selection and `instance_name` / `instance_id` from `libvirt_domain_openstack_info` for VM identity.

---

## Troubleshooting

### Metrics Not Appearing

1. **Check if OTel collectors are running**:
```bash
kubectl get pods -n monitoring | grep opentelemetry
```

2. **Check collector logs**:
```bash
kubectl logs -n monitoring daemonset/opentelemetry-kube-stack-daemon-collector -c otc-container
kubectl logs -n monitoring deployment/opentelemetry-kube-stack-deployment-collector -c otc-container
```

3. **Verify remote write pipeline is healthy**:
```bash
kubectl logs -n monitoring deployment/opentelemetry-kube-stack-deployment-collector -c otc-container | grep -i prometheusremotewrite
```

---

### Missing Host Metrics

1. Verify the daemon collector is running on each node.
2. Confirm the `hostmetrics` receiver is active in the daemon collector metrics pipeline.
3. Check for permissions or host mount issues if hostmetrics suddenly drops out.

---

### Missing Libvirt Metrics

1. Verify the libvirt exporter is running with the libvirt workload on each compute node.
2. Confirm the daemon collector has an active Prometheus scrape job for `libvirt`.
3. Verify the exporter endpoint is reachable from the collector pod, for example `curl http://localhost:9474/metrics` or the configured node-local address.
4. If the exporter is running as a sidecar, confirm the libvirt socket path is correct inside the container.
5. Check collector logs for Prometheus scrape failures:
```bash
kubectl logs -n monitoring daemonset/opentelemetry-kube-stack-daemon-collector -c otc-container | grep -i libvirt
```
6. Check exporter logs for libvirt connection failures or missing socket errors.

---

### Missing MySQL / PostgreSQL / RabbitMQ / Memcached Metrics

1. Confirm the deployment collector is running.
2. Verify credentials secrets exist:
   - `mariadb-monitoring`
   - `postgres.postgres-cluster.credentials.postgresql.acid.zalan.do`
   - `rabbitmq-monitoring-user`
3. Confirm the services are reachable from the deployment collector pod.
4. Check receiver-specific errors in collector logs:
```bash
kubectl logs -n monitoring deployment/opentelemetry-kube-stack-deployment-collector -c otc-container | grep -E "mysql|postgresql|rabbitmq|memcached"
```

---

### Missing cert-manager Metrics

1. Verify pods exist in namespace `cert-manager`.
2. Confirm relevant pods expose Prometheus metrics.
3. Confirm pods are annotated with `prometheus.io/scrape: "true"` where required.
4. Check deployment collector logs for `prometheus/infra` scrape errors.

---

### Missing MetalLB Metrics

1. Verify pods exist in namespace `metallb-system`.
2. Confirm controller/speaker pods expose metrics on port `7472`.
3. Confirm pod label `app.kubernetes.io/component` is set to `controller` or `speaker`.
4. Check deployment collector logs for MetalLB scrape failures.

---

### Missing Kube-OVN Metrics

1. Verify these services exist in `kube-system`:
   - `kube-ovn-monitor`
   - `kube-ovn-controller`
   - `kube-ovn-cni`
   - `kube-ovn-pinger`
2. Confirm each target exposes an endpoint port named `metrics`.
3. Verify the services have backing endpoints.
4. Check deployment collector logs for scrape failures:
```bash
kubectl logs -n monitoring deployment/opentelemetry-kube-stack-deployment-collector -c otc-container | grep -E "kube-ovn-monitor|kube-ovn-controller|kube-ovn-cni|kube-ovn-pinger"
```

---

### Missing HTTP Check Metrics

1. Confirm the `httpcheck` receiver is uncommented in the deployment metrics pipeline.
2. Verify DNS and TLS connectivity from the deployment collector pod.
3. Check logs for `httpcheck` receiver activity.

---

### Missing Kubelet / cAdvisor Metrics

This is expected in the current base config because:

- `kubelet.enabled: false`
- `kubeletMetrics` preset is disabled

If you want `container_*` and kubelet metrics, you must explicitly enable kubelet scraping.

---

### High Cardinality Issues

If Prometheus is struggling with too many series:

1. Drop unnecessary labels at scrape time or via relabeling.
2. Reduce collection intervals where acceptable (`30s` → `60s`).
3. Use recording rules to pre-aggregate noisy metrics.
4. Be cautious with:
   - per-peer MetalLB metrics
   - per-interface OVS metrics
   - per-target pinger metrics
   - per-target HTTP check metrics
   - high-label OTLP application metrics
   - libvirt per-domain / per-interface / per-block-device / per-vCPU metrics
   - kube-state-metrics object labels

---

### Duplicate Metrics

Some overlap is expected:

- `system_*` from OTel `hostmetrics`
- `node_*` from `node-exporter`

This is normal. They provide different views of node health.

In the current base config, **container_* metrics are not duplicated**, because kubelet/cAdvisor scraping is disabled.

---

## Summary

Base configuration collects metrics from:

1. **OTel Collectors (Remote Write to Prometheus)**:
   - Host metrics via `hostmetrics`
   - Libvirt hypervisor and per-domain metrics via OTel Prometheus receiver scraping `libvirt_exporter`
   - Application OTLP metrics
   - MySQL metrics via OTel receiver
   - PostgreSQL metrics via OTel receiver
   - RabbitMQ metrics via OTel receiver
   - Memcached metrics via OTel receiver
   - `cert-manager` metrics via OTel Prometheus receiver
   - `MetalLB` metrics via OTel Prometheus receiver
   - `kube-ovn-monitor` metrics via OTel Prometheus receiver
   - `kube-ovn-controller` metrics via OTel Prometheus receiver
   - `kube-ovn-cni` metrics via OTel Prometheus receiver
   - `kube-ovn-pinger` metrics via OTel Prometheus receiver
   - HTTP check targets and metric families are configured/documented, but the receiver is not currently enabled in the active metrics pipeline
   - kubeletstats receiver remains disabled

2. **Prometheus Direct Scraping**:
   - Kubernetes API server
   - Scheduler
   - Controller manager
   - CoreDNS
   - etcd
   - kube-proxy
   - node-exporter
   - kube-state-metrics

3. **Not Currently Collected in This Base Config**:
   - kubelet metrics
   - cAdvisor `container_*` metrics
   - hostmetrics process-related scrapers (process, processes) are not enabled
   - active HTTP check metric emission until the receiver is uncommented in the pipeline

## Key Metric Sources by Prefix

| Metric Prefix | Source | Collection Method | What It Measures |
|--------------|--------|-------------------|------------------|
| `system_*` | hostmetrics receiver | OTel DaemonSet → Remote Write | Node-level system metrics |
| `libvirt_*` | `libvirt_exporter` | OTel DaemonSet Prometheus scrape → Remote Write | Hypervisor, VM, OpenStack metadata, disk, interface, job, and vCPU metrics |
| `httpcheck.*` | HTTP check receiver | OTel Deployment → Remote Write when enabled | Endpoint availability and latency checks |
| `mysql.*` | MySQL receiver | OTel Deployment → Remote Write | MariaDB/MySQL server health and usage |
| `postgresql.*` | PostgreSQL receiver | OTel Deployment → Remote Write | PostgreSQL usage and transaction metrics |
| `rabbitmq.*` | RabbitMQ receiver | OTel Deployment → Remote Write | RabbitMQ node resource and alarm metrics |
| `memcached.*` | Memcached receiver | OTel Deployment → Remote Write | Cache utilization and eviction metrics |
| `certmanager_*` | cert-manager pods | OTel Deployment → Remote Write | Certificate lifecycle and controller metrics |
| `metallb_*` | MetalLB controller/speaker | OTel Deployment → Remote Write | Address pools, config health, BGP/BFD state |
| `kube_ovn_*`, `ovs_*` | Kube-OVN services | OTel Deployment → Remote Write | OVN/OVS health and topology metrics |
| `pinger_*` | kube-ovn-pinger | OTel Deployment → Remote Write | Network and control-plane reachability checks |
| `node_*` | node-exporter | Prometheus scraping | Detailed node metrics |
| `kube_*` | kube-state-metrics | Prometheus scraping | Kubernetes object state and metadata |
| `apiserver_*`, `scheduler_*`, `workqueue_*`, `coredns_*`, `etcd_*`, `kubeproxy_*` | K8s components | Prometheus scraping | Control plane and cluster service health |

All collected metrics are stored in Prometheus and can be queried from Grafana.
