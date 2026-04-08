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

```text
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
│               │   (on each node)         │                          │
│               └──────────┬───────────────┘                          │
│                          │                                          │
│                          ▼                                          │
│               ┌──────────────────────────┐                          │
│               │ OTel Collector Deployment│                          │
│               │ (cluster-wide scraping)  │                          │
│               └──────────┬───────────────┘                          │
│                          │                                          │
│                          ▼                                          │
│               ┌──────────────────────────┐                          │
│               │ Prometheus Remote Write  │                          │
│               │   (:9090/api/v1/write)   │                          │
│               └──────────────────────────┘                          │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│              PROMETHEUS DIRECT SCRAPING (ServiceMonitors)           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ API      │  │ Scheduler│  │ Ctrl Mgr │  │ Kubelet  │             │
│  │ Server   │  │          │  │          │  │ cAdvisor │             │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘             │
│        │             │             │             │                  │
│        └─────────────┼─────────────┼─────────────┘                  │
│                      │             │                                │
│                      ▼             ▼                                │
│               ┌──────────────────────────────┐                      │
│               │   Prometheus Server (scrape) │                      │
│               └──────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **OTel Collector DaemonSet**: Runs on every node, collects node-local metrics
2. **OTel Collector Deployment**: Runs as a single cluster-wide scraper for shared infrastructure targets
3. **Prometheus Server**: Scrapes Kubernetes components directly via ServiceMonitors
4. **Remote Write**: OTel collectors push metrics to Prometheus

---

## OTel Collector Metrics

These metrics are collected by the OTel collector and sent to Prometheus via remote write.

### 1. Host Metrics (from hostmetrics receiver)

**Source**: `hostmetrics` receiver on each node  
**Collection Interval**: `30s`  
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

**Source**: Prometheus scraping kubelet's cAdvisor endpoint `https://:10250/metrics/cadvisor`  
**Scrape Interval**: `30s` (default)  
**Labels**: Includes pod, container, namespace, node, image labels

**Note**: In your configuration, kubeletstats receiver is **disabled** to avoid duplicate sample errors. Instead, pod and container metrics come from Prometheus directly scraping kubelet/cAdvisor via ServiceMonitor.

These metrics use the `container_*` prefix instead of `k8s_pod_*` or `k8s_container_*`.

#### Container CPU Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_cpu_usage_seconds_total` | Counter | Total CPU time used | `container`, `pod`, `namespace`, `node` | `k8s_container_cpu_time_seconds_total` |
| `container_cpu_cfs_periods_total` | Counter | CFS scheduler periods | `container`, `pod`, `namespace` | - |
| `container_cpu_cfs_throttled_periods_total` | Counter | Throttled periods | `container`, `pod`, `namespace` | - |
| `container_cpu_cfs_throttled_seconds_total` | Counter | Time throttled | `container`, `pod`, `namespace` | - |

#### Container Memory Metrics

| Metric Name | Type | Description | Labels | kubeletstats Equivalent |
|-------------|------|-------------|--------|-------------------------|
| `container_memory_usage_bytes` | Gauge | Current memory usage | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_usage_bytes` |
| `container_memory_working_set_bytes` | Gauge | Working set size | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_working_set_bytes` |
| `container_memory_rss` | Gauge | Resident set size | `container`, `pod`, `namespace`, `node` | `k8s_container_memory_rss_bytes` |
| `container_memory_cache` | Gauge | Page cache | `container`, `pod`, `namespace` | - |
| `container_memory_swap` | Gauge | Swap usage | `container`, `pod`, `namespace` | - |
| `container_memory_failcnt` | Counter | Memory allocation failures | `container`, `pod`, `namespace` | - |
| `container_memory_failures_total` | Counter | Memory limit hit count | `container`, `pod`, `namespace`, `failure_type`, `scope` | - |

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

#### Container Limits and Requests

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `container_spec_cpu_quota` | Gauge | CPU quota (microseconds per period) | `container`, `pod`, `namespace` |
| `container_spec_cpu_period` | Gauge | CPU period (microseconds) | `container`, `pod`, `namespace` |
| `container_spec_cpu_shares` | Gauge | CPU shares | `container`, `pod`, `namespace` |
| `container_spec_memory_limit_bytes` | Gauge | Memory limit | `container`, `pod`, `namespace` |
| `container_spec_memory_reservation_limit_bytes` | Gauge | Memory soft limit | `container`, `pod`, `namespace` |
| `container_spec_memory_swap_limit_bytes` | Gauge | Memory + swap limit | `container`, `pod`, `namespace` |

---

### 3. kubeletstats Metrics (DISABLED in Current Config)

**Status**: ⚠️ **DISABLED** - kubeletstats receiver is disabled to prevent duplicate sample errors.

The kubeletstats receiver would provide `k8s_pod_*` and `k8s_container_*` metrics, but these overlap significantly with the `container_*` metrics from cAdvisor.

---

### 4. Application Metrics (via OTLP)

**Source**: Applications sending metrics to OTel collector via OTLP

**Endpoints**:
- gRPC: `:4317`
- HTTP: `:4318`

Applications instrumented with OpenTelemetry SDKs can send custom metrics.

These vary by application but commonly include:
- Request counts, durations, error rates
- Business metrics
- Resource usage from application perspective
- Custom application-specific metrics

**Labels**: Enriched with Kubernetes metadata via `k8sattributes` processor:
- `k8s_namespace_name`
- `k8s_pod_name`
- `k8s_node_name`
- `k8s_deployment_name`, `k8s_statefulset_name`, etc.
- Pod labels: `app`, `app_kubernetes_io_name`, `app_kubernetes_io_component`, etc.

---

### 5. Infrastructure Metrics (via OTel Prometheus receiver)

**Source**: OTel deployment collector using Prometheus receiver scrape jobs  
**Important**: These metrics are collected by OTel and remote-written to Prometheus. They are **not** scraped by Prometheus ServiceMonitors in this design.

#### 5.1 cert-manager Metrics

**Source**: `cert-manager` controller and `cert-manager-webhook` pods  
**Endpoint**: `http://<pod-ip>:9402/metrics`  
**Namespace**: `cert-manager`  
**Discovery**: Pod discovery using `prometheus.io/*` annotations

##### Certificate Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `certmanager_certificate_expiration_timestamp_seconds` | Gauge | Certificate expiration time as Unix timestamp | `name`, `namespace`, `issuer_name`, `issuer_kind`, `issuer_group` |
| `certmanager_certificate_renewal_timestamp_seconds` | Gauge | Scheduled certificate renewal time as Unix timestamp | `name`, `namespace`, `issuer_name`, `issuer_kind`, `issuer_group` |
| `certmanager_certificate_ready_status` | Gauge | Whether the certificate is ready | `name`, `namespace`, `condition` |

##### Controller Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `certmanager_controller_sync_call_count` | Counter | Number of controller sync calls | `controller` |
| `certmanager_controller_sync_call_duration_seconds` | Histogram | Duration of controller sync calls | `controller` |
| `certmanager_controller_sync_error_count` | Counter | Number of controller sync errors | `controller` |

##### ACME / HTTP Client Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `certmanager_http_acme_client_request_count` | Counter | Number of ACME client HTTP requests | `host`, `method`, `path`, `status` |
| `certmanager_http_acme_client_request_duration_seconds` | Histogram | ACME client HTTP request duration | `host`, `method`, `path`, `status` |

##### Runtime / Process Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `go_*` | Various | Go runtime metrics exposed by cert-manager components | Varies |
| `process_*` | Various | Process metrics exposed by cert-manager components | Varies |
| `controller_runtime_*` | Various | Controller-runtime metrics exposed by webhook/controller components | Varies |

**Notes**:
- The controller exposes cert-manager-specific metrics plus Go/process metrics.
- The webhook exposes controller-runtime, Go runtime, and process metrics.
- The cainjector also exposes metrics on `:9402`, but it is intentionally not part of the current scrape config.

#### 5.2 MetalLB Metrics

**Source**: `controller` and `speaker` pods  
**Endpoint**: `http://<pod-ip>:7472/metrics`  
**Namespace**: `metallb-system`  
**Discovery**: Pod discovery filtering on `component=controller|speaker`

##### Allocator Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_allocator_addresses_in_use_total` | Gauge | Number of IP addresses in use, per pool | `pool` |
| `metallb_allocator_addresses_total` | Gauge | Number of usable IP addresses, per pool | `pool` |

##### Kubernetes Client Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_k8s_client_updates_total` | Counter | Number of Kubernetes object updates processed | Varies |
| `metallb_k8s_client_update_errors_total` | Counter | Number of Kubernetes object update failures | Varies |
| `metallb_k8s_client_config_loaded_bool` | Gauge | Whether MetalLB config has successfully loaded at least once | - |
| `metallb_k8s_client_config_stale_bool` | Gauge | Whether MetalLB is running with stale config | - |

##### BGP Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_bgp_session_up` | Gauge | BGP session state (1=up, 0=down) | `peer` |
| `metallb_bgp_updates_total` | Counter | Number of BGP UPDATE messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_announced_prefixes_total` | Gauge | Number of prefixes currently advertised on the BGP session | `peer`, `vrf` (optional) |

##### FRR-only BGP Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_bgp_opens_sent` | Counter | Number of BGP OPEN messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_opens_received` | Counter | Number of BGP OPEN messages received | `peer`, `vrf` (optional) |
| `metallb_bgp_notifications_sent` | Counter | Number of BGP NOTIFICATION messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_updates_total_received` | Counter | Number of BGP UPDATE messages received | `peer`, `vrf` (optional) |
| `metallb_bgp_keepalives_sent` | Counter | Number of BGP KEEPALIVE messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_keepalives_received` | Counter | Number of BGP KEEPALIVE messages received | `peer`, `vrf` (optional) |
| `metallb_bgp_route_refresh_sent` | Counter | Number of BGP route refresh messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_total_sent` | Counter | Total number of BGP messages sent | `peer`, `vrf` (optional) |
| `metallb_bgp_total_received` | Counter | Total number of BGP messages received | `peer`, `vrf` (optional) |

##### FRR-only BFD Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `metallb_bfd_session_up` | Gauge | BFD session state (1=up, 0=down) | `peer`, `vrf` (optional) |
| `metallb_bfd_control_packet_input` | Counter | Number of received BFD control packets | `peer`, `vrf` (optional) |
| `metallb_bfd_control_packet_output` | Counter | Number of sent BFD control packets | `peer`, `vrf` (optional) |
| `metallb_bfd_echo_packet_input` | Counter | Number of received BFD echo packets | `peer`, `vrf` (optional) |
| `metallb_bfd_echo_packet_output` | Counter | Number of sent BFD echo packets | `peer`, `vrf` (optional) |
| `metallb_bfd_session_up_events` | Counter | Number of BFD session up events | `peer`, `vrf` (optional) |
| `metallb_bfd_session_down_events` | Counter | Number of BFD session down events | `peer`, `vrf` (optional) |
| `metallb_bfd_session_zebra_notifications` | Counter | Number of BFD zebra notifications | `peer`, `vrf` (optional) |

##### Speaker / Controller Runtime Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `go_*` | Various | Go runtime metrics exposed by MetalLB components | Varies |
| `process_*` | Various | Process metrics exposed by MetalLB components | Varies |
| `controller_runtime_*` | Various | Controller-runtime / reconciliation metrics where exposed | Varies |

#### 5.3 OVN / Kube-OVN Metrics

**Source**: `kube-ovn-cni`, `kube-ovn-controller`, `kube-ovn-monitor`, `kube-ovn-pinger` services  
**Endpoint**: `http://<service-endpoint>:metrics`  
**Namespace**: `kube-system`  
**Discovery**: Endpoint discovery using service label `app` and endpoint port name `metrics`

This replaces the old dedicated `ServiceMonitor` objects for:
- `app=kube-ovn-cni`
- `app=kube-ovn-controller`
- `app=kube-ovn-monitor`
- `app=kube-ovn-pinger`

##### OVN Monitor Metrics (`kube-ovn-monitor`)

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `kube_ovn_ovn_status` | Gauge | OVN health status: follower/standby=2, leader/active=1, unhealthy=0 | Varies |
| `kube_ovn_failed_req_count` | Gauge | Number of failed requests to OVN stack | Varies |
| `kube_ovn_log_file_size` | Gauge | Size of an OVN component log file | `component` |
| `kube_ovn_db_file_size` | Gauge | Size of an OVN database file | `component` |
| `kube_ovn_chassis_info` | Gauge | Whether OVN chassis is up (1) or down (0) with chassis metadata | `chassis`, others |
| `kube_ovn_db_status` | Gauge | OVN NB/SB DB health status | `db` |
| `kube_ovn_logical_switch_info` | Gauge | Logical switch metadata | `logical_switch` |
| `kube_ovn_logical_switch_external_id` | Gauge | External IDs associated with logical switches | `logical_switch`, `key`, `value` |
| `kube_ovn_logical_switch_port_binding` | Gauge | Association between logical switch and logical switch port | `logical_switch`, `port` |
| `kube_ovn_logical_switch_tunnel_key` | Gauge | Tunnel key associated with logical switch | `logical_switch` |
| `kube_ovn_logical_switch_ports_num` | Gauge | Number of logical switch ports connected to the switch | `logical_switch` |
| `kube_ovn_logical_switch_port_info` | Gauge | Logical switch port metadata | `logical_switch`, `port` |
| `kube_ovn_logical_switch_port_tunnel_key` | Gauge | Tunnel key associated with logical switch port | `logical_switch`, `port` |
| `kube_ovn_cluster_enabled` | Gauge | Whether OVN clustering is enabled | - |
| `kube_ovn_cluster_role` | Gauge | Server role metric | `role` |
| `kube_ovn_cluster_status` | Gauge | Server status metric | `status` |
| `kube_ovn_cluster_term` | Gauge | Current raft term known by this server | - |
| `kube_ovn_cluster_leader_self` | Gauge | Whether this server considers itself the leader | - |
| `kube_ovn_cluster_vote_self` | Gauge | Whether this server voted for itself as leader | - |
| `kube_ovn_cluster_election_timer` | Gauge | Current election timer value | - |
| `kube_ovn_cluster_log_not_committed` | Gauge | Number of log entries not yet committed | - |
| `kube_ovn_cluster_log_not_applied` | Gauge | Number of log entries not yet applied | - |
| `kube_ovn_cluster_log_index_start` | Gauge | Log entry start index | - |
| `kube_ovn_cluster_log_index_next` | Gauge | Next log entry index | - |
| `kube_ovn_cluster_inbound_connections_total` | Gauge | Total inbound connections to the server | - |
| `kube_ovn_cluster_outbound_connections_total` | Gauge | Total outbound connections from the server | - |
| `kube_ovn_cluster_inbound_connections_error_total` | Gauge | Failed inbound connections | - |
| `kube_ovn_cluster_outbound_connections_error_total` | Gauge | Failed outbound connections | - |

##### OVS Monitor Metrics (`kube-ovn-monitor`)

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `ovs_status` | Gauge | OVS health status (1 healthy, 0 unhealthy) | - |
| `ovs_info` | Gauge | Basic OVS metadata | Varies |
| `failed_req_count` | Gauge | Failed requests to OVS stack | - |
| `log_file_size` | Gauge | Size of OVS log file | `component` |
| `db_file_size` | Gauge | Size of OVS database file | `component` |
| `datapath` | Gauge | Existing datapath marker | `datapath` |
| `dp_total` | Gauge | Total number of datapaths on the system | - |
| `dp_if` | Gauge | Existing datapath interface marker | `datapath`, `interface` |
| `dp_if_total` | Gauge | Number of ports connected to the datapath | `datapath` |
| `dp_flows_total` | Gauge | Number of flows in a datapath | `datapath` |
| `dp_flows_lookup_hit` | Gauge | Packets matching existing datapath flows | `datapath` |
| `dp_flows_lookup_missed` | Gauge | Packets not matching any datapath flows | `datapath` |
| `dp_flows_lookup_lost` | Gauge | Packets destined for userspace but dropped before arrival | `datapath` |
| `dp_masks_hit` | Gauge | Total number of masks visited while matching packets | `datapath` |
| `dp_masks_total` | Gauge | Number of masks in a datapath | `datapath` |
| `dp_masks_hit_ratio` | Gauge | Average number of masks visited per packet | `datapath` |
| `interface` | Gauge | OVS interface marker | `interface` |
| `interface_admin_state` | Gauge | Administrative state of OVS interface | `interface` |
| `interface_link_state` | Gauge | Physical link state of OVS interface | `interface` |
| `interface_mac_in_use` | Gauge | MAC address in use by OVS interface | `interface`, `mac` |
| `interface_mtu` | Gauge | Configured MTU for OVS interface | `interface` |
| `interface_of_port` | Gauge | OpenFlow port ID for OVS interface | `interface` |
| `interface_if_index` | Gauge | Interface index for OVS interface | `interface` |
| `interface_tx_packets` | Gauge | Transmitted packets on OVS interface | `interface` |
| `interface_tx_bytes` | Gauge | Transmitted bytes on OVS interface | `interface` |
| `interface_tx_error` | Gauge | Transmit errors on OVS interface | `interface` |
| `interface_rx_packets` | Gauge | Received packets on OVS interface | `interface` |
| `interface_rx_bytes` | Gauge | Received bytes on OVS interface | `interface` |
| `interface_rx_errors` | Gauge | Receive errors on OVS interface | `interface` |
| `interface_rx_dropped` | Gauge | Dropped received packets on OVS interface | `interface` |
| `interface_rx_frame_err` | Gauge | RX frame errors on OVS interface | `interface` |
| `interface_rx_over_err` | Gauge | RX overrun errors on OVS interface | `interface` |
| `interface_tx_dropped` | Gauge | Dropped transmitted packets on OVS interface | `interface` |
| `interface_tx_errors` | Gauge | Total transmit errors on OVS interface | `interface` |
| `interface_collisions` | Gauge | Interface collisions | `interface` |

##### kube-ovn-pinger Metrics

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

##### kube-ovn-controller Metrics

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

##### kube-ovn-cni Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `cni_op_latency_seconds` | Histogram | CNI operation latency | `operation` |
| `cni_wait_address_seconds_total` | Counter | Time waiting for controller to assign an address | `operation` |
| `cni_wait_connectivity_seconds_total` | Counter | Time waiting for address readiness in overlay network | `operation` |
| `cni_wait_route_seconds_total` | Counter | Time waiting for routed annotation to be added to pod | `operation` |
| `rest_client_request_latency_seconds` | Histogram | Request latency in seconds | `verb`, `url` |

#### 5.4 Envoy Gateway Metrics

**Source**: Envoy Gateway control plane and managed Envoy Proxy instances  
**Common Namespaces**: `envoy-gateway-system` or environment-specific namespace  
**Discovery**: Depends on your scrape design; typically service or pod discovery for both control plane and proxy workloads

**Note**: Envoy Gateway metrics split into:
- **Control plane metrics** from the Envoy Gateway controller
- **Proxy / data plane metrics** from managed Envoy proxies

The exact metric set depends on enabled listeners, protocols, filters, routes, clusters, and telemetry settings.

##### Envoy Gateway Control Plane Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `controller_runtime_*` | Various | Controller-runtime reconciliation, queueing, and client metrics | Varies |
| `workqueue_*` | Various | Kubernetes workqueue depth, adds, retries, latency, and work duration | `name` |
| `rest_client_*` | Various | Kubernetes client request counts and latencies | `verb`, `url`, `code`, `method`, `host` |
| `go_*` | Various | Go runtime metrics from the Envoy Gateway controller | Varies |
| `process_*` | Various | Process metrics from the Envoy Gateway controller | Varies |

##### Envoy Proxy Server Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `envoy_server_live` | Gauge | Whether the Envoy process is live | - |
| `envoy_server_uptime` | Gauge | Envoy process uptime | - |
| `envoy_server_memory_allocated` | Gauge | Memory allocated by Envoy | - |
| `envoy_server_memory_heap_size` | Gauge | Envoy heap size | - |
| `envoy_server_parent_connections` | Gauge | Parent connections | - |
| `envoy_server_total_connections` | Gauge | Total active connections | - |
| `envoy_server_hot_restart_epoch` | Gauge | Hot restart epoch | - |
| `envoy_server_version` | Gauge | Version info marker | `version` |

##### Envoy Cluster Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `envoy_cluster_upstream_cx_active` | Gauge | Active upstream connections | `envoy_cluster_name` |
| `envoy_cluster_upstream_cx_total` | Counter | Total upstream connections | `envoy_cluster_name` |
| `envoy_cluster_upstream_cx_connect_fail` | Counter | Upstream connection failures | `envoy_cluster_name` |
| `envoy_cluster_upstream_rq_total` | Counter | Total upstream requests | `envoy_cluster_name` |
| `envoy_cluster_upstream_rq_pending_total` | Counter | Pending upstream requests | `envoy_cluster_name` |
| `envoy_cluster_upstream_rq_retry` | Counter | Retried upstream requests | `envoy_cluster_name` |
| `envoy_cluster_upstream_rq_timeout` | Counter | Timed out upstream requests | `envoy_cluster_name` |
| `envoy_cluster_membership_total` | Gauge | Total hosts in cluster | `envoy_cluster_name` |
| `envoy_cluster_membership_healthy` | Gauge | Healthy hosts in cluster | `envoy_cluster_name` |

##### Envoy HTTP / Listener Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `envoy_http_downstream_rq_total` | Counter | Total downstream HTTP requests | `envoy_http_conn_manager_prefix`, `response_code`, others |
| `envoy_http_downstream_rq_xx` | Counter | Downstream requests by response class (1xx/2xx/3xx/4xx/5xx) | `envoy_http_conn_manager_prefix` |
| `envoy_http_downstream_rq_time` | Histogram | Downstream request latency | `envoy_http_conn_manager_prefix` |
| `envoy_http_downstream_cx_active` | Gauge | Active downstream HTTP connections | `envoy_http_conn_manager_prefix` |
| `envoy_http_downstream_cx_total` | Counter | Total downstream HTTP connections | `envoy_http_conn_manager_prefix` |
| `envoy_listener_downstream_cx_active` | Gauge | Active downstream listener connections | `envoy_listener_address` |
| `envoy_listener_downstream_cx_total` | Counter | Total downstream listener connections | `envoy_listener_address` |
| `envoy_listener_downstream_pre_cx_timeout` | Counter | Listener pre-connection timeouts | `envoy_listener_address` |

##### Envoy TCP / Network Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `envoy_tcp_downstream_cx_total` | Counter | Total downstream TCP connections | `envoy_tcp_prefix` |
| `envoy_tcp_downstream_cx_destroy` | Counter | Destroyed downstream TCP connections | `envoy_tcp_prefix` |
| `envoy_tcp_downstream_cx_rx_bytes_total` | Counter | Downstream TCP RX bytes | `envoy_tcp_prefix` |
| `envoy_tcp_downstream_cx_tx_bytes_total` | Counter | Downstream TCP TX bytes | `envoy_tcp_prefix` |

##### Gateway API / Route Metrics

| Metric Name / Family | Type | Description | Labels |
|----------------------|------|-------------|--------|
| `envoy_gateway_*` | Various | Envoy Gateway-specific control-plane metrics when enabled by the project | Varies |
| `gatewayapi_*` | Various | Gateway API related metrics where exposed by the control plane or add-ons | Varies |

**Notes**:
- Exact Envoy proxy metrics vary significantly with config and traffic shape.
- Most dashboards group these by listener, cluster, route, service, gateway, and response code.

---

## Kubernetes Component Metrics

These metrics are scraped **directly by Prometheus** via ServiceMonitors (NOT via OTel collectors).

**Note**: This section covers the remaining direct-Prometheus targets. Infrastructure metrics for `cert-manager`, `MetalLB`, `OVN / Kube-OVN`, and any Envoy Gateway targets moved to OTel are documented above.

### 1. API Server Metrics

**Source**: `kube-apiserver` (scraped by Prometheus)  
**Endpoint**: `https://kubernetes.default.svc:443/metrics`  
**Labels**: `instance`, `job`, `endpoint`, `service`, `namespace`

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

### 2. Scheduler Metrics

**Source**: `kube-scheduler` (scraped by Prometheus)  
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

### 3. Controller Manager Metrics

**Source**: `kube-controller-manager` (scraped by Prometheus)  
**Endpoint**: `https://:10257/metrics`

Common metrics:
- `workqueue_adds_total`
- `workqueue_depth`
- `workqueue_queue_duration_seconds`
- `workqueue_work_duration_seconds`
- `workqueue_retries_total`

### 4. Kubelet Metrics (cAdvisor)

**Source**: `kubelet` cAdvisor endpoint (scraped by Prometheus)  
**Endpoint**: `https://:10250/metrics/cadvisor`

Common metrics:
- `container_cpu_usage_seconds_total`
- `container_memory_usage_bytes`
- `container_memory_working_set_bytes`
- `container_network_receive_bytes_total`
- `container_network_transmit_bytes_total`
- `container_fs_usage_bytes`
- `container_fs_reads_total`
- `container_fs_writes_total`
- `container_start_time_seconds`
- `container_last_seen`

### 5. Kubelet Metrics (kubelet /metrics)

**Source**: `kubelet` endpoint (scraped by Prometheus)  
**Endpoint**: `https://:10250/metrics`

Common metrics:
- `kubelet_running_pods`
- `kubelet_running_containers`
- `kubelet_volume_stats_*`
- `kubelet_pod_start_duration_seconds`
- `kubelet_pod_worker_duration_seconds`
- `kubelet_runtime_operations_*`
- `kubelet_pleg_*`

### 6. CoreDNS Metrics

**Source**: `coredns` (scraped by Prometheus)  
**Endpoint**: `http://:9153/metrics`

Common metrics:
- `coredns_dns_request_duration_seconds`
- `coredns_dns_requests_total`
- `coredns_dns_responses_total`
- `coredns_forward_requests_total`
- `coredns_cache_hits_total`
- `coredns_cache_misses_total`

### 7. etcd Metrics

**Source**: `etcd` (scraped by Prometheus if configured)  
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

### 8. Kube Proxy Metrics

**Source**: `kube-proxy` (scraped by Prometheus)  
**Endpoint**: `http://:10249/metrics`

Common metrics:
- `kubeproxy_sync_proxy_rules_duration_seconds`
- `kubeproxy_network_programming_duration_seconds`
- `rest_client_requests_total`
- `rest_client_request_duration_seconds`

---

## Node and System Metrics

### 1. Node Exporter Metrics

**Source**: `node-exporter` DaemonSet (scraped by Prometheus)  
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

### 2. Kube State Metrics

**Source**: `kube-state-metrics` Deployment (scraped by Prometheus)  
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

If OpenStack services are instrumented to send OTLP metrics, they will include:
- Custom application metrics
- Auto-instrumented framework metrics
- Resource usage from application perspective

**Labels**:
- `service_name`
- Kubernetes labels from `k8sattributes` processor
- Custom application labels

---

## Metric Label Reference

### Common Labels Added by OTel Collectors

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
| `k8s_cluster_name` | attributes processor | Fixed cluster name |

### Additional Labels Common on Infrastructure Metrics

| Label | Source | Description |
|-------|--------|-------------|
| `component` | OTel relabeling / pod labels | Component name such as `controller`, `speaker`, `webhook` |
| `namespace` | Prometheus SD / OTel relabeling | Kubernetes namespace of scrape target |
| `pod` | Prometheus SD / OTel relabeling | Pod name of scrape target |
| `service` | Prometheus SD / OTel relabeling | Service name for service/endpoints-based discovery |
| `peer` | MetalLB metrics | BGP/BFD peer identifier |
| `pool` | MetalLB metrics | Address pool |
| `vrf` | MetalLB metrics | VRF name |
| `controller` | cert-manager metrics | Controller name inside cert-manager |
| `subnet` | Kube-OVN metrics | Subnet identifier |
| `logical_switch` | Kube-OVN metrics | OVN logical switch |
| `interface` | OVS/Kube-OVN / Envoy | Interface or listener-specific label |
| `node` | Kube-OVN / Prometheus | Node associated with metric |
| `envoy_cluster_name` | Envoy Proxy metrics | Upstream cluster name |
| `envoy_listener_address` | Envoy Proxy metrics | Listener address label |
| `envoy_http_conn_manager_prefix` | Envoy Proxy metrics | HTTP connection manager prefix |

### Labels from Prometheus ServiceMonitors

| Label | Description |
|-------|-------------|
| `instance` | Scrape target address (IP:port) |
| `job` | ServiceMonitor job name |
| `endpoint` | Endpoint name |
| `service` | Service name |
| `namespace` | Namespace |
| `pod` | Pod name (if available) |
| `node` | Node name (if added via relabeling) |

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
kubectl logs -n opentelemetry deployment/opentelemetry-kube-stack-deployment-collector -c otc-container
```

3. **Verify metrics are being collected**:
```bash
kubectl logs -n opentelemetry deployment/opentelemetry-kube-stack-deployment-collector \
  -c otc-container | grep -E "certmanager_|metallb_|kube_ovn_|pinger_|ovs_|envoy_|controller_runtime_"
```

### Missing cert-manager Metrics

1. Verify the controller and webhook pods exist in `cert-manager`
2. Confirm the pods expose `:9402/metrics`
3. Confirm annotation-based scraping is enabled
4. Verify the deployment collector can discover pods in `cert-manager`

### Missing MetalLB Metrics

1. Verify MetalLB pods exist in `metallb-system`
2. Confirm the metrics port is `7472`
3. Verify the `component` label exists on `controller` and `speaker` pods
4. If secure metrics are enabled, update OTel to use HTTPS/TLS settings

### Missing OVN Metrics

1. Verify these services/endpoints exist in `kube-system`:
   - `app=kube-ovn-cni`
   - `app=kube-ovn-controller`
   - `app=kube-ovn-monitor`
   - `app=kube-ovn-pinger`
2. Confirm each target has a `metrics` port
3. Verify the deployment collector can list/watch endpoints in `kube-system`

### Missing Envoy Gateway Metrics

1. Verify Envoy Gateway control plane is exposing metrics
2. Verify managed Envoy proxy pods/services expose metrics
3. Confirm your scrape config covers both control plane and proxy workloads
4. Expect the exact Envoy metric set to vary by listeners, routes, clusters, and traffic

### High Cardinality Issues

If Prometheus is struggling with too many metrics:

1. Drop unnecessary metrics via relabeling or scrape-time filtering
2. Reduce collection intervals (`30s` → `60s`)
3. Use recording rules to aggregate high-cardinality metrics
4. Be selective with OVN/Kube-OVN metrics, especially interface and per-target ping metrics
5. Be selective with Envoy proxy metrics if route/listener/cardinality explodes

### Duplicate Metrics

If you see the same metric with different prefixes:
- `system_*` from hostmetrics
- `node_*` from node-exporter
- `container_*` from cAdvisor

This is normal. They provide different levels of detail.

Also note:
- Cluster-wide infrastructure scrapes should stay on the **deployment collector**
- Running the same Prometheus receiver jobs on multiple deployment collector replicas will duplicate scrapes unless explicitly sharded

---

## Summary

Your configuration collects metrics from:

1. **OTel Collectors (Remote Write to Prometheus)**:
   - Host metrics via `hostmetrics`
   - Application OTLP metrics
   - `cert-manager` metrics via OTel Prometheus receiver
   - `MetalLB` metrics via OTel Prometheus receiver
   - `OVN / Kube-OVN` metrics via OTel Prometheus receiver
   - `Envoy Gateway / Envoy Proxy` metrics via OTel Prometheus receiver where configured
   - kubeletstats receiver remains disabled

2. **Prometheus Direct Scraping**:
   - Kubernetes components
   - Kubelet / cAdvisor
   - Node exporter
   - Kube-state-metrics

## Key Metric Sources by Prefix

| Metric Prefix | Source | Collection Method | What It Measures |
|--------------|--------|-------------------|------------------|
| `system_*` | hostmetrics receiver | OTel DaemonSet → Remote Write | Node-level system metrics |
| `certmanager_*` | cert-manager controller/webhook | OTel Deployment → Remote Write | Certificate lifecycle, controller activity, ACME operations |
| `metallb_*` | MetalLB controller/speaker | OTel Deployment → Remote Write | Address pools, config health, BGP/BFD state |
| `kube_ovn_*`, `pinger_*`, `ovs_*` | Kube-OVN services | OTel Deployment → Remote Write | OVN/OVS health, subnet IP usage, connectivity |
| `envoy_*`, `controller_runtime_*`, `workqueue_*` | Envoy Gateway / Envoy Proxy | OTel Deployment → Remote Write | Gateway control-plane and proxy data-plane health and traffic |
| `container_*` | kubelet/cAdvisor | Prometheus scraping | Pod and container resource usage |
| `node_*` | node-exporter | Prometheus scraping | Detailed node metrics |
| `kube_*` | kube-state-metrics | Prometheus scraping | Kubernetes object state and metadata |
| `apiserver_*`, `scheduler_*`, etc. | K8s components | Prometheus scraping | Control plane component metrics |

All metrics are enriched with Kubernetes metadata and stored in Prometheus for querying in Grafana.
