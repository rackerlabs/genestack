# Additional Opentelemetry Metrics Reference

Complete reference for MySQL, PostgreSQL, RabbitMQ, Memcached, SNMP, and HTTP Check metrics collected by the OpenTelemetry deployment collector.

---

## Table of Contents

1. [MySQL Metrics](#mysql-metrics)
2. [PostgreSQL Metrics](#postgresql-metrics)
3. [RabbitMQ Metrics](#rabbitmq-metrics)
4. [Memcached Metrics](#memcached-metrics)
5. [HTTP Check Metrics](#http-check-metrics)
6. [SNMP Metrics](#snmp-metrics)
7. [Common Query Patterns](#common-query-patterns)
8. [Alerting Examples](#alerting-examples)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Deployment Collector                             │
│                    (Single Pod on Control Plane)                     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐             │
│  │ MySQL         │  │ PostgreSQL    │  │ RabbitMQ      │             │
│  │ Receiver      │  │ Receiver      │  │ Receiver      │             │
│  │               │  │               │  │               │             │
│  │ • Connections │  │ • Backends    │  │ • Messages    │             │
│  │ • Queries     │  │ • Commits     │  │ • Queues      │             │
│  │ • Locks       │  │ • Deadlocks   │  │ • Consumers   │             │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘             │
│          │                  │                  │                     │
│  ┌───────┴──────────────────┴──────────────────┴───────┐             │
│  │          resource/service-metrics Processor         │             │
│  │                                                     │             │
│  │  Adds labels: job, instance, service.namespace      │             │
│  └───────────────────────────┬─────────────────────────┘             │
│                              │                                       │
│  ┌───────────────────────────┴───────────────────────────┐           │
│  │        prometheusremotewrite Exporter                 │           │
│  │                                                       │           │
│  │  • Converts resource attributes to labels             │           │
│  │  • Adds external labels (cluster, etc.)               │           │
│  └───────────────────────────┬───────────────────────────┘           │
│                              │                                       │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   Prometheus         │
                    │   (Remote Write)     │
                    └──────────────────────┘
```

---

## MySQL Metrics

### Connection Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `mysql_connection_count` | Gauge | Number of connections by state | connections |
| `mysql_connection_errors` | Sum | Connection errors by type | errors |

**Labels**:
- `state`: `open`, `closed`, `active`, `idle`
- `error_type`: `internal`, `max_connections`, `peer`, `select`, `tcpwrap`

**Query Examples**:
```promql
# Current active connections
mysql_connection_count{state="active"}

# Connection error rate
rate(mysql_connection_errors[5m])

# Connection usage percentage (assuming max_connections=1000)
(mysql_connection_count{state="open"} / 1000) * 100
```

### Query Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `mysql_commands` | Sum | Commands executed by type | commands |
| `mysql_query_slow_count` | Sum | Number of slow queries | queries |

**Labels**:
- `command`: `select`, `insert`, `update`, `delete`, `commit`, `rollback`, etc.

**Query Examples**:
```promql
# Query rate by type
rate(mysql_commands[5m])

# Slow query rate
rate(mysql_query_slow_count[5m])

# Read vs write ratio
sum(rate(mysql_commands{command="select"}[5m])) 
/ 
sum(rate(mysql_commands{command=~"insert|update|delete"}[5m]))
```

### Buffer Pool Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `mysql_buffer_pool_usage` | Gauge | Buffer pool utilization | bytes |
| `mysql_buffer_pool_pages` | Gauge | Buffer pool pages by state | pages |

**Labels**:
- `state`: `data`, `free`, `dirty`, `misc`

**Query Examples**:
```promql
# Buffer pool utilization percentage
(mysql_buffer_pool_usage / mysql_buffer_pool_limit) * 100

# Dirty pages percentage
(mysql_buffer_pool_pages{state="dirty"} / sum(mysql_buffer_pool_pages)) * 100
```

### Lock Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `mysql_locks` | Sum | Table locks by state | locks |
| `mysql_row_locks` | Sum | InnoDB row locks | locks |

**Labels**:
- `state`: `immediate`, `waited`

**Query Examples**:
```promql
# Lock wait rate
rate(mysql_locks{state="waited"}[5m])

# Row lock contention
rate(mysql_row_locks{state="waited"}[5m]) 
/ 
rate(mysql_row_locks[5m])
```

### Thread Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `mysql_threads` | Gauge | Threads by state | threads |

**Labels**:
- `state`: `running`, `cached`, `connected`, `created`

**Query Examples**:
```promql
# Active threads
mysql_threads{state="running"}

# Thread cache efficiency
rate(mysql_threads{state="cached"}[5m]) 
/ 
rate(mysql_threads{state="created"}[5m])
```

### Complete MySQL Metrics List

```yaml
mysql:
  metrics:
    # ✅ Enabled (Connection Health)
    mysql.connection.count: true
    mysql.connection.errors: true
    
    # ✅ Enabled (Query Performance)
    mysql.commands: true
    mysql.query.slow.count: true
    
    # ✅ Enabled (Buffer Pool)
    mysql.buffer_pool.usage: true
    mysql.buffer_pool.pages: true
    
    # ✅ Enabled (Locking)
    mysql.locks: true
    mysql.row_locks: true
    
    # ✅ Enabled (Threads)
    mysql.threads: true
    
    # ⚠️ Optional (Additional)
    mysql.handlers: false              # Handler operations
    mysql.operations: false            # CRUD operations count
    mysql.page_operations: false       # InnoDB page operations
    mysql.row_operations: false        # Row operations (read/insert/update/delete)
    mysql.sorts: false                 # Sort operations
    mysql.table.io.wait: false         # Table I/O wait times
    mysql.double_writes: false         # InnoDB doublewrite buffer
    mysql.log_operations: false        # Log operations
    mysql.mysqlx_connections: false    # X Protocol connections
    mysql.prepared_statements: false   # Prepared statement count
```

---

## PostgreSQL Metrics

### Connection Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_backends` | Gauge | Number of backends connected | backends |
| `postgresql_connection_max` | Gauge | Maximum connections allowed | connections |

**Query Examples**:
```promql
# Current connections
postgresql_backends

# Connection usage percentage
(postgresql_backends / postgresql_connection_max) * 100

# Available connections
postgresql_connection_max - postgresql_backends
```

### Transaction Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_commits` | Sum | Committed transactions | transactions |
| `postgresql_rollbacks` | Sum | Rolled back transactions | transactions |

**Labels**:
- `database`: Database name

**Query Examples**:
```promql
# Transaction rate by database
rate(postgresql_commits[5m])

# Rollback rate
rate(postgresql_rollbacks[5m])

# Rollback ratio (should be low)
rate(postgresql_rollbacks[5m]) 
/ 
(rate(postgresql_commits[5m]) + rate(postgresql_rollbacks[5m]))
```

### Database Size Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_db_size` | Gauge | Database size | bytes |
| `postgresql_table_size` | Gauge | Table size | bytes |
| `postgresql_index_size` | Gauge | Index size | bytes |

**Labels**:
- `database`: Database name
- `table`: Table name (for table/index metrics)

**Query Examples**:
```promql
# Total database size
sum(postgresql_db_size)

# Largest databases
topk(5, postgresql_db_size)

# Database growth rate
deriv(postgresql_db_size[1h]) * 3600 * 24  # Bytes per day

# Index to table size ratio
sum(postgresql_index_size) by (database, table) 
/ 
sum(postgresql_table_size) by (database, table)
```

### Lock Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_deadlocks` | Sum | Number of deadlocks detected | deadlocks |
| `postgresql_database_locks` | Gauge | Current locks by mode | locks |

**Labels**:
- `mode`: `AccessShare`, `RowShare`, `RowExclusive`, `ShareUpdateExclusive`, `Share`, `ShareRowExclusive`, `Exclusive`, `AccessExclusive`
- `database`: Database name

**Query Examples**:
```promql
# Deadlock rate
rate(postgresql_deadlocks[5m])

# Exclusive locks (potential contention)
postgresql_database_locks{mode="Exclusive"}

# Total locks by database
sum(postgresql_database_locks) by (database)
```

### I/O Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_blocks_read` | Sum | Blocks read from disk vs cache | blocks |

**Labels**:
- `source`: `cache` or `disk`
- `database`: Database name

**Query Examples**:
```promql
# Blocks read from disk (cache misses)
rate(postgresql_blocks_read{source="disk"}[5m])

# Cache hit ratio
sum(rate(postgresql_blocks_read{source="cache"}[5m])) 
/ 
sum(rate(postgresql_blocks_read[5m]))

# Blocks read per second by database
rate(postgresql_blocks_read[5m])
```

### Background Writer Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `postgresql_bgwriter_checkpoint_count` | Sum | Checkpoints by type | checkpoints |
| `postgresql_bgwriter_duration` | Sum | Checkpoint duration | milliseconds |
| `postgresql_bgwriter_buffers_writes` | Sum | Buffers written | buffers |

**Labels**:
- `type`: `scheduled` or `requested`

**Query Examples**:
```promql
# Checkpoint frequency
rate(postgresql_bgwriter_checkpoint_count[5m])

# Average checkpoint duration
rate(postgresql_bgwriter_duration[5m]) 
/ 
rate(postgresql_bgwriter_checkpoint_count[5m])

# Requested checkpoints (should be low)
rate(postgresql_bgwriter_checkpoint_count{type="requested"}[5m])
```

### Complete PostgreSQL Metrics List

```yaml
postgresql:
  metrics:
    # ✅ Enabled (Connection Health)
    postgresql.backends: true
    postgresql.connection.max: true
    
    # ✅ Enabled (Transactions)
    postgresql.commits: true
    postgresql.rollbacks: true
    
    # ✅ Enabled (Database Size)
    postgresql.db_size: true
    
    # ✅ Enabled (Locking)
    postgresql.deadlocks: true
    postgresql.database.locks: true
    
    # ✅ Enabled (I/O)
    postgresql.blocks_read: true
    
    # ✅ Enabled (Background Writer)
    postgresql.bgwriter.checkpoint.count: true
    
    # ⚠️ Optional (Additional)
    postgresql.bgwriter.buffers.allocated: false
    postgresql.bgwriter.buffers.writes: false
    postgresql.bgwriter.duration: false
    postgresql.bgwriter.maxwritten: false
    postgresql.database.count: false
    postgresql.index.scans: false
    postgresql.index.size: false
    postgresql.operations: false           # Insert/update/delete counts
    postgresql.rows: false                 # Row counts
    postgresql.table.count: false
    postgresql.table.size: false
    postgresql.table.vacuum.count: false
    postgresql.wal.age: false              # Replication only
    postgresql.wal.lag: false              # Replication only
```

---

## RabbitMQ Metrics

### Node Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_node_disk_free` | Gauge | Free disk space on node | bytes |
| `rabbitmq_node_disk_free_limit` | Gauge | Disk free space alarm threshold | bytes |
| `rabbitmq_node_disk_free_alarm` | Gauge | Disk alarm active (0 or 1) | boolean |
| `rabbitmq_node_mem_used` | Gauge | Memory used by node | bytes |
| `rabbitmq_node_mem_limit` | Gauge | Memory limit threshold | bytes |
| `rabbitmq_node_mem_alarm` | Gauge | Memory alarm active (0 or 1) | boolean |

**Labels**:
- `node`: RabbitMQ node name

**Query Examples**:
```promql
# Disk usage percentage
(1 - (rabbitmq_node_disk_free / rabbitmq_node_disk_free_limit)) * 100

# Memory usage percentage
(rabbitmq_node_mem_used / rabbitmq_node_mem_limit) * 100

# Nodes with alarms active
rabbitmq_node_disk_free_alarm == 1 or rabbitmq_node_mem_alarm == 1

# Available disk space
rabbitmq_node_disk_free
```

### File Descriptor Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_node_fd_used` | Gauge | File descriptors in use | descriptors |
| `rabbitmq_node_fd_total` | Gauge | Total file descriptors available | descriptors |

**Query Examples**:
```promql
# File descriptor usage percentage
(rabbitmq_node_fd_used / rabbitmq_node_fd_total) * 100

# Available file descriptors
rabbitmq_node_fd_total - rabbitmq_node_fd_used
```

### Socket Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_node_sockets_used` | Gauge | Sockets in use | sockets |
| `rabbitmq_node_sockets_total` | Gauge | Total sockets available | sockets |

**Query Examples**:
```promql
# Socket usage percentage
(rabbitmq_node_sockets_used / rabbitmq_node_sockets_total) * 100
```

### Process Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_node_proc_used` | Gauge | Erlang processes in use | processes |
| `rabbitmq_node_proc_total` | Gauge | Total Erlang processes allowed | processes |

**Query Examples**:
```promql
# Process usage percentage
(rabbitmq_node_proc_used / rabbitmq_node_proc_total) * 100
```

### Message Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_message_current` | Gauge | Messages in queues by state | messages |
| `rabbitmq_message_published` | Sum | Messages published | messages |
| `rabbitmq_message_delivered` | Sum | Messages delivered | messages |
| `rabbitmq_message_acknowledged` | Sum | Messages acknowledged | messages |
| `rabbitmq_message_dropped` | Sum | Messages dropped | messages |

**Labels**:
- `state`: `ready`, `unacknowledged`
- `queue`: Queue name
- `vhost`: Virtual host

**Query Examples**:
```promql
# Messages waiting in queues
rabbitmq_message_current{state="ready"}

# Unacknowledged messages (potential consumer issues)
rabbitmq_message_current{state="unacknowledged"}

# Message publish rate
rate(rabbitmq_message_published[5m])

# Message delivery rate
rate(rabbitmq_message_delivered[5m])

# Message drop rate (should be zero!)
rate(rabbitmq_message_dropped[5m])

# Consumer lag (messages piling up)
deriv(rabbitmq_message_current{state="ready"}[5m])
```

### Queue Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_queue_count` | Gauge | Number of queues | queues |

**Query Examples**:
```promql
# Total queues
rabbitmq_queue_count

# Queues by vhost
sum(rabbitmq_queue_count) by (vhost)
```

### Consumer Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `rabbitmq_consumer_count` | Gauge | Number of consumers | consumers |

**Labels**:
- `queue`: Queue name
- `vhost`: Virtual host

**Query Examples**:
```promql
# Total consumers
sum(rabbitmq_consumer_count)

# Queues without consumers (potential issue)
rabbitmq_message_current{state="ready"} > 0 
and 
rabbitmq_consumer_count == 0

# Consumers per queue
rabbitmq_consumer_count
```

### Complete RabbitMQ Metrics List

```yaml
rabbitmq:
  metrics:
    # ✅ Enabled (Node Health)
    rabbitmq.node.disk_free: true
    rabbitmq.node.disk_free_limit: true
    rabbitmq.node.disk_free_alarm: true
    rabbitmq.node.mem_used: true
    rabbitmq.node.mem_limit: true
    rabbitmq.node.mem_alarm: true
    
    # ✅ Enabled (Resources)
    rabbitmq.node.fd_used: true
    rabbitmq.node.fd_total: true
    rabbitmq.node.sockets_used: true
    rabbitmq.node.sockets_total: true
    rabbitmq.node.proc_used: true
    rabbitmq.node.proc_total: true
    
    # ✅ Enabled (Messages)
    rabbitmq.message.current: true
    rabbitmq.message.published: true
    rabbitmq.message.delivered: true
    rabbitmq.message.acknowledged: true
    rabbitmq.message.dropped: true
    
    # ✅ Enabled (Queues & Consumers)
    rabbitmq.queue.count: true
    rabbitmq.consumer.count: true
    
    # ⚠️ Optional (Rate Details)
    rabbitmq.node.disk_free_details.rate: false
    rabbitmq.node.fd_used_details.rate: false
    rabbitmq.node.mem_used_details.rate: false
    rabbitmq.node.proc_used_details.rate: false
    rabbitmq.node.sockets_used_details.rate: false
```

---

## Memcached Metrics

### Memory Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_bytes` | Gauge | Current bytes used | bytes |
| `memcached_limit` | Gauge | Maximum bytes allowed | bytes |
| `memcached_current_items` | Gauge | Current items in cache | items |

**Query Examples**:
```promql
# Memory usage percentage
(memcached_bytes / memcached_limit) * 100

# Available memory
memcached_limit - memcached_bytes

# Items in cache
memcached_current_items
```

### Cache Performance Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_operation_hit_ratio` | Gauge | Cache hit ratio | ratio (0-1) |
| `memcached_operations` | Sum | Cache operations by type | operations |
| `memcached_commands` | Sum | Commands by type | commands |

**Labels**:
- `type`: `hit`, `miss` (for operations)
- `command`: `get`, `set`, `delete`, `touch`, etc.

**Query Examples**:
```promql
# Cache hit ratio (higher is better)
memcached_operation_hit_ratio

# Cache hit rate
rate(memcached_operations{type="hit"}[5m])

# Cache miss rate
rate(memcached_operations{type="miss"}[5m])

# Get command rate
rate(memcached_commands{command="get"}[5m])

# Set command rate
rate(memcached_commands{command="set"}[5m])
```

### Eviction Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_evictions` | Sum | Items evicted from cache | evictions |

**Query Examples**:
```promql
# Eviction rate (should be low)
rate(memcached_evictions[5m])

# Total evictions
memcached_evictions
```

### Connection Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_connections_current` | Gauge | Current open connections | connections |
| `memcached_connections_total` | Sum | Total connections opened | connections |

**Query Examples**:
```promql
# Current connections
memcached_connections_current

# Connection rate
rate(memcached_connections_total[5m])
```

### Network Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_network` | Sum | Network bytes by direction | bytes |

**Labels**:
- `direction`: `sent`, `received`

**Query Examples**:
```promql
# Network throughput
rate(memcached_network[5m])

# Bytes sent per second
rate(memcached_network{direction="sent"}[5m])

# Bytes received per second
rate(memcached_network{direction="received"}[5m])
```

### CPU and Thread Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `memcached_cpu_usage` | Sum | CPU usage | seconds |
| `memcached_threads` | Gauge | Number of worker threads | threads |

**Labels**:
- `type`: `system`, `user`

**Query Examples**:
```promql
# CPU usage rate
rate(memcached_cpu_usage[5m])

# Worker threads
memcached_threads
```

### Complete Memcached Metrics List

```yaml
memcached:
  metrics:
    # ✅ Enabled (Memory)
    memcached.bytes: true
    memcached.current_items: true
    
    # ✅ Enabled (Performance)
    memcached.operation_hit_ratio: true
    memcached.operations: true
    memcached.commands: true
    
    # ✅ Enabled (Evictions)
    memcached.evictions: true
    
    # ✅ Enabled (Connections)
    memcached.connections.current: true
    
    # ⚠️ Optional (Additional)
    memcached.connections.total: false
    memcached.network: false
    memcached.cpu.usage: false
    memcached.threads: false
    memcached.limit: false                # Static config
```

---

## HTTP Check Metrics

### Availability Metrics

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `httpcheck_status` | Gauge | HTTP status code (200, 404, 500, etc.) | status_code |
| `httpcheck_duration` | Gauge | Request duration | milliseconds |
| `httpcheck_error` | Gauge | Error indicator (0 = success, 1 = error) | boolean |

**Labels**:
- `http_url`: Full URL being checked
- `http_method`: HTTP method (GET, POST, etc.)
- `http_status_code`: Response status code
- `http_status_class`: Status class (2xx, 4xx, 5xx)

**Query Examples**:
```promql
# Endpoint availability (1 = up, 0 = down)
httpcheck_error == 0

# All endpoints up
count(httpcheck_error == 0)

# Failed endpoints
httpcheck_error == 1

# Response time
httpcheck_duration

# Average response time by endpoint
avg(httpcheck_duration) by (http_url)

# Slow endpoints (> 1 second)
httpcheck_duration > 1000

# Endpoints by status code
count(httpcheck_status) by (http_status_code)
```

### Uptime Calculation

```promql
# Uptime percentage over last hour
(sum(rate(httpcheck_error == 0[1h])) / sum(rate(httpcheck_error[1h]))) * 100

# Availability by endpoint
avg_over_time((httpcheck_error == 0)[1h:30s]) * 100
```

### Complete HTTP Check Metrics

```yaml
httpcheck:
  # Automatically collects all metrics - no configuration needed
  # Metrics generated:
  #   - httpcheck.status
  #   - httpcheck.duration
  #   - httpcheck.error
```

---

## SNMP Metrics

SNMP metrics are **custom-defined** based on the devices you're monitoring. Below are common examples.

### Network Interface Metrics

```yaml
snmp:
  metrics:
    # Interface traffic
    if.in.octets:
      unit: "bytes"
      gauge:
        value_type: int
      column_oids:
        - oid: "1.3.6.1.2.1.2.2.1.10"  # ifInOctets
      attributes:
        interface:
          value: prefix
          oid: "1.3.6.1.2.1.2.2.1.2"   # ifDescr
    
    if.out.octets:
      unit: "bytes"
      gauge:
        value_type: int
      column_oids:
        - oid: "1.3.6.1.2.1.2.2.1.16"  # ifOutOctets
      attributes:
        interface:
          value: prefix
          oid: "1.3.6.1.2.1.2.2.1.2"   # ifDescr
    
    # Interface errors
    if.in.errors:
      unit: "errors"
      gauge:
        value_type: int
      column_oids:
        - oid: "1.3.6.1.2.1.2.2.1.14"  # ifInErrors
      attributes:
        interface:
          value: prefix
          oid: "1.3.6.1.2.1.2.2.1.2"
```

**Query Examples**:
```promql
# Interface throughput
rate(if_in_octets[5m]) * 8  # Convert to bits/sec

# Total bandwidth by device
sum(rate(if_in_octets[5m])) by (device)

# Interface error rate
rate(if_in_errors[5m])
```

### Common SNMP OIDs

| OID | Description | Metric Type |
|-----|-------------|-------------|
| `1.3.6.1.2.1.1.5.0` | System Name (sysName) | String |
| `1.3.6.1.2.1.1.3.0` | System Uptime (sysUpTime) | TimeTicks |
| `1.3.6.1.2.1.2.2.1.10` | Interface In Octets (ifInOctets) | Counter |
| `1.3.6.1.2.1.2.2.1.16` | Interface Out Octets (ifOutOctets) | Counter |
| `1.3.6.1.2.1.2.2.1.14` | Interface In Errors (ifInErrors) | Counter |
| `1.3.6.1.2.1.2.2.1.20` | Interface Out Errors (ifOutErrors) | Counter |
| `1.3.6.1.4.1.2021.11.9.0` | CPU Idle (Net-SNMP) | Integer |
| `1.3.6.1.4.1.2021.4.6.0` | Total Memory (Net-SNMP) | Integer |

---

## Common Query Patterns

### Aggregations Across Services

```promql
# Total database connections
mysql_connection_count{state="open"} + postgresql_backends

# Total cache hit ratio
(
  (memcached_operation_hit_ratio * memcached_operations) +
  0  # Add other caches here
) / memcached_operations

# All service endpoints up
count(httpcheck_error == 0) / count(httpcheck_error)
```

### Resource Usage Summary

```promql
# Database memory usage
sum(mysql_buffer_pool_usage) + sum(postgresql_backend_memory)

# Queue message backlog
sum(rabbitmq_message_current{state="ready"})

# Cache memory usage
sum(memcached_bytes)
```

### Performance Indicators

```promql
# Transaction throughput (transactions/sec)
sum(rate(mysql_commands[5m])) + sum(rate(postgresql_commits[5m]))

# Message throughput (messages/sec)
rate(rabbitmq_message_published[5m])

# Cache operations per second
rate(memcached_operations[5m])

# Average endpoint response time
avg(httpcheck_duration)
```

---

## Alerting Examples

### MySQL Alerts

```yaml
groups:
  - name: mysql
    rules:
      # High connection usage
      - alert: MySQLConnectionsHigh
        expr: |
          (mysql_connection_count{state="open"} / mysql_connection_max) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL connection usage high ({{ $value }}%)"
      
      # Slow query rate high
      - alert: MySQLSlowQueriesHigh
        expr: |
          rate(mysql_query_slow_count[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL slow queries elevated ({{ $value }} queries/sec)"
      
      # Lock waits increasing
      - alert: MySQLLockWaits
        expr: |
          rate(mysql_locks{state="waited"}[5m]) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL lock waits detected ({{ $value }} waits/sec)"
```

### PostgreSQL Alerts

```yaml
groups:
  - name: postgresql
    rules:
      # Connection limit approaching
      - alert: PostgreSQLConnectionsHigh
        expr: |
          (postgresql_backends / postgresql_connection_max) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connection usage high ({{ $value }}%)"
      
      # Deadlocks detected
      - alert: PostgreSQLDeadlocks
        expr: |
          rate(postgresql_deadlocks[5m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL deadlocks detected ({{ $value }} deadlocks/sec)"
      
      # Database growing rapidly
      - alert: PostgreSQLDatabaseGrowth
        expr: |
          deriv(postgresql_db_size[1h]) * 3600 > 1e9  # 1GB per hour
        for: 5m
        labels:
          severity: info
        annotations:
          summary: "PostgreSQL database {{ $labels.database }} growing rapidly"
```

### RabbitMQ Alerts

```yaml
groups:
  - name: rabbitmq
    rules:
      # Memory alarm
      - alert: RabbitMQMemoryAlarm
        expr: |
          rabbitmq_node_mem_alarm == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ memory alarm active on {{ $labels.node }}"
      
      # Messages piling up
      - alert: RabbitMQMessageBacklog
        expr: |
          rabbitmq_message_current{state="ready"} > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "RabbitMQ queue backlog ({{ $value }} messages ready)"
      
      # No consumers on queue
      - alert: RabbitMQNoConsumers
        expr: |
          rabbitmq_message_current{state="ready"} > 0 
          and 
          rabbitmq_consumer_count == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ queue {{ $labels.queue }} has messages but no consumers"
      
      # Message drop rate
      - alert: RabbitMQMessagesDropped
        expr: |
          rate(rabbitmq_message_dropped[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ dropping messages ({{ $value }} messages/sec)"
```

### Memcached Alerts

```yaml
groups:
  - name: memcached
    rules:
      # Low cache hit ratio
      - alert: MemcachedLowHitRatio
        expr: |
          memcached_operation_hit_ratio < 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Memcached hit ratio low ({{ $value }})"
      
      # High eviction rate
      - alert: MemcachedHighEvictions
        expr: |
          rate(memcached_evictions[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memcached eviction rate high ({{ $value }} evictions/sec)"
      
      # Memory usage high
      - alert: MemcachedMemoryHigh
        expr: |
          (memcached_bytes / memcached_limit) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memcached memory usage high ({{ $value }}%)"
```

### HTTP Check Alerts

```yaml
groups:
  - name: httpcheck
    rules:
      # Endpoint down
      - alert: HTTPEndpointDown
        expr: |
          httpcheck_error == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "HTTP endpoint {{ $labels.http_url }} is down"
      
      # Slow response time
      - alert: HTTPEndpointSlow
        expr: |
          httpcheck_duration > 5000  # 5 seconds
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HTTP endpoint {{ $labels.http_url }} responding slowly ({{ $value }}ms)"
      
      # Non-200 status codes
      - alert: HTTPEndpointError
        expr: |
          httpcheck_status >= 400
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HTTP endpoint {{ $labels.http_url }} returning {{ $labels.http_status_code }}"
```

---

## Grafana Dashboard Examples

### MySQL Dashboard

```json
{
  "panels": [
    {
      "title": "MySQL Connections",
      "targets": [
        {
          "expr": "mysql_connection_count{state='open'}"
        }
      ]
    },
    {
      "title": "Query Rate",
      "targets": [
        {
          "expr": "sum(rate(mysql_commands[5m])) by (command)"
        }
      ]
    },
    {
      "title": "Slow Queries",
      "targets": [
        {
          "expr": "rate(mysql_query_slow_count[5m])"
        }
      ]
    }
  ]
}
```

### RabbitMQ Dashboard

```json
{
  "panels": [
    {
      "title": "Messages Ready",
      "targets": [
        {
          "expr": "rabbitmq_message_current{state='ready'}"
        }
      ]
    },
    {
      "title": "Message Rate",
      "targets": [
        {
          "expr": "rate(rabbitmq_message_published[5m])",
          "legendFormat": "Published"
        },
        {
          "expr": "rate(rabbitmq_message_delivered[5m])",
          "legendFormat": "Delivered"
        }
      ]
    },
    {
      "title": "Consumer Count",
      "targets": [
        {
          "expr": "rabbitmq_consumer_count"
        }
      ]
    }
  ]
}
```

---

## Summary

This reference covers **all metrics** from the deployment collector's database and service receivers:

| Service | Metrics Count | Key Metrics |
|---------|---------------|-------------|
| **MySQL** | 25+ metrics | Connections, queries, locks, buffer pool |
| **PostgreSQL** | 30+ metrics | Backends, transactions, deadlocks, I/O |
| **RabbitMQ** | 20+ metrics | Messages, queues, consumers, node health |
| **Memcached** | 15+ metrics | Cache hits, evictions, memory, operations |
| **HTTP Check** | 3 metrics | Status, duration, errors |
| **SNMP** | Custom | Interface traffic, device metrics |

**Total**: 90+ pre-defined metrics for infrastructure monitoring!

All metrics flow through the deployment collector → Prometheus → Grafana for visualization and alerting.
