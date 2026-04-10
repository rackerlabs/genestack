# Getting Started with Genestack Monitoring

This guide walks you through setting up a complete observability stack for your Genestack deployment. The monitoring system provides unified telemetry collection across metrics, logs, and traces using industry-standard open-source tools.

---

## Overview

The Genestack observability stack includes:

- **OpenTelemetry** - Universal telemetry collection and processing (metrics, logs, traces)
- **Prometheus** - Time-series database and metrics storage
- **Loki** - Log aggregation and querying system
- **Tempo** - Distributed tracing backend
- **Grafana** - Unified visualization platform for all telemetry types
- **AlertManager** - Alert routing and notification management

### Architecture

All components are deployed in the `monitoring` namespace for simplified management and access control.

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Namespace                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  OpenTelemetry Collectors                                   │
│    ↓ Collect ↓                                              │
│  Metrics, Logs, Traces from:                                │
│    • Kubernetes (nodes, pods, containers)                   │
│    • OpenStack services (Nova, Neutron, etc.)               │
│    • Infrastructure (MySQL, RabbitMQ, etc.)                 │
│                                                             │
│  ↓ Store in ↓                                               │
│                                                             │
│  Prometheus (metrics) + Loki (logs) + Tempo (traces)        │
│                                                             │
│  ↓ Visualize in ↓                                           │
│                                                             │
│  Grafana (dashboards, alerts, exploration)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### What Gets Monitored

| Component | Metrics | Logs | Traces |
|-----------|---------|------|--------|
| **Kubernetes** | Node/pod/container resources | Container logs, K8s events | N/A |
| **OpenStack** | API performance | Service logs (Nova, Neutron, etc.) | Request flows |
| **Databases** | Connections, queries, locks | Query logs | Slow query traces |
| **Message Queues** | Messages, consumers, memory | RabbitMQ logs | Message processing |
| **Cache** | Hit ratio, evictions | Memcached logs | Cache operations |

---

## Prerequisites

Before proceeding, ensure you have:

- ✅ A running Genestack deployment
- ✅ Helm 3.x installed
- ✅ `kubectl` access to your Kubernetes cluster
- ✅ Cluster admin or namespace admin permissions
- ✅ Sufficient cluster resources (see [resource requirements](#resource-requirements))

### Required Tools

```bash
# Verify installations
helm version
kubectl version
yq --version  # For YAML manipulation (v4+)
```

### Namespace Preparation

```bash
# Create the monitoring namespace
kubectl create namespace monitoring

# Label it for easy identification
kubectl label namespace monitoring \
  name=monitoring \
  monitoring=enabled
```

---

## Installation Steps

Follow these steps in order to build your complete observability stack.

---

## Step 1: Install the Prometheus Stack

The kube-prometheus-stack is the foundation of your metrics infrastructure. It provides time-series storage, alerting, and scraping capabilities.

### What Gets Installed

- **Prometheus Operator** - Manages Prometheus lifecycle via CRDs
- **Prometheus Server** - Collects and stores metrics (15-day retention)
- **AlertManager** - Routes alerts to notification channels
- **Grafana** - Pre-configured with Prometheus datasource (optional, we'll install separately)

### Installation

```bash
# Install using Genestack script
bin/install-kube-prometheus-stack.sh

# Or install manually with Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f /etc/genestack/helm-configs/prometheus/prometheus-helm-overrides.yaml
```

### Verify Installation

```bash
# Check pods are running
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus

# Expected output:
# prometheus-kube-prometheus-stack-prometheus-0   Running
# alertmanager-kube-prometheus-stack-alertmanager-0   Running

# Check Prometheus targets
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
# Open: http://localhost:9090/targets
# You should see targets for node-exporter and kube-state-metrics
```

**📚 For detailed configuration, see the [Prometheus installation guide](monitoring-prometheus.md).**

---

## Step 2: Install Loki

Loki provides cost-effective log aggregation using label-based indexing (similar to Prometheus but for logs).

### What Gets Installed

- **Loki Gateway** - Receives logs from collectors
- **Loki Write** - Ingests and indexes logs
- **Loki Read** - Serves log queries
- **Loki Backend** - Handles compaction and retention

### Installation

```bash
# Install using Genestack script
bin/install-loki.sh

# Or install manually with Helm
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki \
  -n monitoring \
  -f /etc/genestack/helm-configs/loki/loki-helm-overrides.yaml
```

**📚 For detailed configuration, see the [Loki installation guide](monitoring-loki.md).**


### Verify Installation

```bash
# Check Loki pods
kubectl -n monitoring get pods -l app.kubernetes.io/name=loki

# Test Loki readiness
kubectl -n monitoring port-forward svc/loki-gateway 3100:80 &
curl http://localhost:3100/ready
# Expected: ready
```

### Key Features

- **Label-based indexing** - Only indexes labels, not log content (cost-effective)
- **LogQL** - Query language similar to PromQL
- **S3 backend** - Long-term storage in object storage
- **Multi-tenancy** - Namespace isolation support

---

## Step 3: Install Tempo

Tempo provides distributed tracing for tracking requests across microservices.

### What Gets Installed

- **Tempo Distributor** - Receives traces from applications
- **Tempo Ingester** - Writes traces to storage
- **Tempo Query Frontend** - Serves trace queries
- **Tempo Compactor** - Compacts and manages trace data

### Installation

```bash
# Install using Genestack script
bin/install-tempo.sh

# Or install manually with Helm
helm install tempo grafana/tempo \
  -n monitoring \
  -f /etc/genestack/helm-configs/tempo/tempo-helm-overrides.yaml
```

### Verify Installation

```bash
# Check Tempo pods
kubectl -n monitoring get pods -l app.kubernetes.io/name=tempo

# Test Tempo readiness
kubectl -n monitoring port-forward svc/tempo 3100:3100 &
curl http://localhost:3100/ready
# Expected: ready
```

### Key Features

- **TraceQL** - Query language for searching traces
- **S3 backend** - Cost-effective trace storage
- **Trace correlation** - Links traces to logs and metrics
- **OpenTelemetry native** - First-class OTLP support

---

**📚 For more information, see the [Tempo installation guide](monitoring-tempo.md).**


## Step 4: Install OpenTelemetry

OpenTelemetry provides unified telemetry collection, processing, and export for metrics, logs, and traces.

### What Gets Installed

#### Daemon Collectors (DaemonSet - one per node)

Collects telemetry from each node:
- Container logs from `/var/log/pods`
- Host metrics (CPU, memory, disk, network)
- OTLP metrics and traces from applications
- Kubernetes events

#### Deployment Collector (Single pod)

Collects infrastructure metrics:
- MySQL/MariaDB metrics (connections, queries, locks)
- PostgreSQL metrics (backends, deadlocks, transactions)
- RabbitMQ metrics (messages, queues, consumers)
- Memcached metrics (hit ratio, evictions)
- Metallb metrics
- Cert Manager metrics
- Kube OVN metrics
- HTTP endpoint health checks

### Prerequisites

Before installing OpenTelemetry we'll need secrets for various services we're gather metrics from. 
If this is a fresh cluster deployment we'll need to create the secrets in the `monitoring` namespace:

??? example "Create MariaDB secret"
```shell
kubectl --namespace monitoring \
  create secret generic mariadb-monitoring \
  --type Opaque \
  --from-literal=username="monitoring" \
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
```

??? example "Create Postgres secret"
```shell
kubectl --namespace monitoring \
  create secret generic postgres-monitoring \
  --type Opaque \
  --from-literal=username="monitoring" 
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64}; echo;)"
```

??? example "Create RabbitMQ secret in openstack namespace"
```shell
kubectl --namespace openstack \
  create secret generic rabbitmq-monitoring-user \
  --type Opaque \
  --from-literal=username="monitoring" \
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64}; echo;)"
```
For now we'll have to copy the secret into the monitoring namespace as well. 

??? example "Copy RabbitMQ secret to monitoring namespace"
```shell
kubectl get secret rabbitmq-monitoring-user \
  -n openstack -o yaml \
  | sed 's/namespace: openstack/namespace: monitoring/' \
  | kubectl apply -f -
```

### Installation

```bash
# Install using Genestack script
bin/install-opentelemetry-kube-stack.sh

# Or install manually with Helm
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install opentelemetry-kube-stack open-telemetry/opentelemetry-operator \
  -n monitoring \
  -f /etc/genestack/helm-configs/opentelemetry/otel-helm-overrides.yaml
```

### Verify Installation

```bash
# Check daemon collectors (one per node)
kubectl -n monitoring get pods -l app.kubernetes.io/instance=opentelemetry-kube-stack-daemon

# Check deployment collector
kubectl -n monitoring get pods -l app.kubernetes.io/instance=opentelemetry-kube-stack-deployment

# Verify logs are being collected
kubectl -n monitoring logs daemonset/opentelemetry-kube-stack-daemon-collector --tail=50

# Verify metrics are being sent to Prometheus
kubectl -n monitoring logs deployment/opentelemetry-kube-stack-deployment-collector --tail=50 | grep "prometheusremotewrite"
```
**📚 For more information, see the [Opentelemetry installation guide](monitoring-opentelemetry.md).**


### Key Features

- **Vendor-neutral** - Industry standard for telemetry collection
- **Multi-protocol** - Supports OTLP, Jaeger, Zipkin
- **Processing pipeline** - Transform, filter, batch telemetry data
- **Auto-instrumentation** - Kubernetes metadata enrichment

### Configuration

OpenTelemetry exporters are configured to send data to:
- **Prometheus** - `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write`
- **Loki** - `http://loki-gateway.monitoring.svc.cluster.local/otlp`
- **Tempo** - `http://tempo.monitoring.svc.cluster.local:4318`

All within the same `monitoring` namespace for simplified networking.

---

## Step 5: Install Grafana

Grafana provides unified visualization for metrics, logs, and traces with pre-built and custom dashboards.

### What Gets Installed

- **Grafana Server** - Web UI and API
- **MariaDB** - Database for dashboards and users
- **Pre-configured Datasources**:
  - Prometheus (metrics)
  - Loki (logs)
  - Tempo (traces)

### Installation

```bash
# Install using Genestack script
bin/install-grafana.sh

# Or install manually with Helm
helm install grafana grafana/grafana \
  -n monitoring \
  -f /etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml
```

### Create Grafana Database

```bash
# Apply the MariaDB manifest
kubectl apply -f base-kustomize/grafana/base/grafana-database.yaml

# Wait for database to be ready
kubectl -n monitoring wait --for=condition=ready pod \
  -l app.kubernetes.io/name=mariadb,app.kubernetes.io/instance=grafana \
  --timeout=300s
```

### Access Grafana

```bash
# Get admin password
kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo

# Port-forward to Grafana
kubectl -n monitoring port-forward svc/grafana 3000:80

# Open browser to http://localhost:3000
# Username: admin
# Password: (from above command)
```

### Verify Datasources

After logging in:
1. Go to **Configuration** → **Data Sources**
2. Verify these datasources are configured and working:
   - ✅ **Prometheus** - `http://kube-prometheus-stack-prometheus.monitoring.svc:9090`
   - ✅ **Loki** - `http://loki-gateway.monitoring.svc`
   - ✅ **Tempo** - `http://tempo.monitoring.svc:3100`
3. Click **Test** on each datasource to verify connectivity

### Import Dashboards

```bash
# Import Kubernetes cluster monitoring dashboard
python3 scripts/import-grafana-dashboard.py \
  --grafana-url http://localhost:3000 \
  --dashboard-id 7249 \
  --api-key <your-api-key>

# Or manually import via UI:
# Dashboards → Import → Enter dashboard ID from grafana.com
```

**📚 For more information, see the [Grafana documentation](monitoring-grafana.md).**

---

## Step 6: Deploy Service-Specific Metric Exporters (Optional)

The OpenTelemetry deployment collector already provides metrics for:
- MySQL/MariaDB
- PostgreSQL
- RabbitMQ
- Memcached

However, if you need additional service-specific exporters, they are available for deployment.

### Available Exporters And Additional Metrics Services

- **OpenStack Exporter** - [OpenStack API metrics](prometheus-openstack-metrics-exporter.md)
- **Custom Node Metrics** - [Custom Node Metrics](prometheus-custom-node-metrics.md)
- **Push Gateway** - [Prometheus Push Gateway](prometheus-pushgateway.md)

### When to Use Additional Exporters

Use additional exporters when:
- You need metrics not provided by OpenTelemetry receivers
- You want more granular metrics than OTel provides
- You're integrating third-party services with specific exporters

**Note**: Most infrastructure metrics are already collected by OpenTelemetry, so additional exporters may not be necessary.

---

## Step 7: Configure AlertManager

AlertManager handles alert routing and notifications. Configure it to send alerts to your preferred channels.

### Available Integrations

- **Slack** - Send alerts to Slack channels ([guide](alertmanager-slack.md))
- **Email** - SMTP-based email notifications
- **PagerDuty** - Incident management integration
- **Webhooks** - Custom HTTP endpoints
- **OpsGenie** - On-call management
- **VictorOps** - Incident response

### Configure Slack Alerts (Example)

```bash
# Edit AlertManager configuration
kubectl -n monitoring edit secret alertmanager-kube-prometheus-stack-alertmanager

# Add Slack webhook configuration
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#alerts'
        title: 'Cluster Alert'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
```

### Test AlertManager

```bash
# Port-forward to AlertManager
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093

# Open browser to http://localhost:9093
# You should see the AlertManager UI with configured receivers
```

**📚 For detailed configuration, see [AlertManager Slack integration](alertmanager-slack.md).**

---

## Step 8: Customize Alerting Rules

### Default Alerting Rules

Prometheus includes default alerting rules for common scenarios. View them:

```bash
# List PrometheusRule resources
kubectl -n monitoring get prometheusrule

# View specific rule
kubectl -n monitoring get prometheusrule kube-prometheus-stack-kubernetes-resources -o yaml
```

### Custom Alerting Rules

Create custom alerting rules in `/etc/genestack/helm-configs/prometheus/alerting_rules.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: genestack-custom-alerts
  namespace: monitoring
spec:
  groups:
    - name: database-alerts
      interval: 30s
      rules:
        # High MySQL connection usage
        - alert: MySQLConnectionsHigh
          expr: |
            (mysql_connection_count{state="open"} / 1000) > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "MySQL connection usage high"
            description: "MySQL is using {{ $value }}% of max connections"
        
        # PostgreSQL deadlocks
        - alert: PostgreSQLDeadlocks
          expr: |
            rate(postgresql_deadlocks[5m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PostgreSQL deadlocks detected"
            description: "Database {{ $labels.database }} has deadlocks"
        
        # RabbitMQ message backlog
        - alert: RabbitMQBacklog
          expr: |
            rabbitmq_message_current{state="ready"} > 10000
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "RabbitMQ queue backlog"
            description: "Queue {{ $labels.queue }} has {{ $value }} messages ready"

    - name: openstack-alerts
      interval: 30s
      rules:
        # Nova API down
        - alert: NovaAPIDown
          expr: |
            httpcheck_error{http_url=~".*nova.*"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Nova API is down"
            description: "Nova API endpoint {{ $labels.http_url }} is unreachable"
```

Apply the custom rules:

```bash
kubectl apply -f /etc/genestack/helm-configs/prometheus/alerting_rules.yaml
```

## Verification and Testing

### End-to-End Verification

Run through this checklist to ensure everything is working:

#### 1. Check All Pods Running

```bash
kubectl -n monitoring get pods

# Expected pods:
# - prometheus-kube-prometheus-stack-prometheus-0
# - alertmanager-kube-prometheus-stack-alertmanager-0
# - loki-write-*, loki-read-*, loki-backend-*
# - tempo-*
# - grafana-*
# - opentelemetry-kube-stack-daemon-collector-* (one per node)
# - opentelemetry-kube-stack-deployment-collector-*
```

#### 2. Verify Metrics Collection

```bash
# Port-forward to Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &

# Open http://localhost:9090/targets
# Verify targets are up and being scraped

# Query for metrics
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | select(.value[1]=="1") | .metric.job' | sort -u

# Should see jobs like:
# "kube-state-metrics"
# "node-exporter"
# "opentelemetry-deployment"
# "rabbitmq"
# "mysql"
```

#### 3. Verify Logs Collection

```bash
# Port-forward to Loki
kubectl -n monitoring port-forward svc/loki-gateway 3100:80 &

# Query for recent logs
curl -s 'http://localhost:3100/loki/api/v1/query?query={namespace="kube-system"}&limit=5' | jq '.data.result'

# Should return log entries
```

#### 4. Verify Traces (If Applications are Instrumented)

```bash
# Port-forward to Tempo
kubectl -n monitoring port-forward svc/tempo 3100:3100 &

# Check Tempo is ready
curl http://localhost:3100/ready
# Expected: ready
```

#### 5. Test Grafana Dashboards

```bash
# Access Grafana
kubectl -n monitoring port-forward svc/grafana 3000:80

# Open http://localhost:3000
# Navigate to Dashboards → Browse
# Open "Kubernetes / Compute Resources / Cluster"
# Verify metrics are displaying
```

#### 6. Test Alerting

Create a test alert:

```yaml
# test-alert.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: test-alert
  namespace: monitoring
spec:
  groups:
    - name: test
      rules:
        - alert: TestAlert
          expr: vector(1)
          labels:
            severity: warning
          annotations:
            summary: "This is a test alert"
```

```bash
# Apply test alert
kubectl apply -f test-alert.yaml

# Wait 30 seconds, then check AlertManager
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 &

# Open http://localhost:9093
# You should see the test alert firing

# Cleanup
kubectl -n monitoring delete prometheusrule test-alert
```

---

## Resource Requirements

### Minimum (Small Cluster - Dev/Test)

Total for monitoring namespace:

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Prometheus | 2 cores | 4Gi | 50Gi |
| Loki | 1 core | 2Gi | 20Gi |
| Tempo | 500m | 1Gi | 10Gi |
| Grafana | 500m | 512Mi | 10Gi |
| OTel (per node) | 500m | 512Mi | - |
| OTel (deployment) | 500m | 512Mi | - |
| **Total** | ~6 cores | ~10Gi | 90Gi |

### Production (Large Cluster)

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Prometheus | 4 cores | 16Gi | 500Gi |
| Loki | 4 cores | 8Gi | 100Gi + S3 |
| Tempo | 2 cores | 4Gi | 50Gi + S3 |
| Grafana | 1 core | 2Gi | 10Gi |
| OTel (per node) | 2 cores | 2Gi | - |
| OTel (deployment) | 1 core | 1Gi | - |
| **Total** | ~15 cores | ~35Gi | 660Gi |

**Note**: Storage can be reduced significantly by using S3 backends for Loki and Tempo.

---

## Common Issues and Troubleshooting

### No Metrics Appearing in Prometheus

**Check**:
```bash
# Verify OpenTelemetry is sending metrics
kubectl -n monitoring logs deployment/opentelemetry-kube-stack-deployment-collector | grep prometheusremotewrite

# Check Prometheus targets
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets
```

**Fix**: Verify exporter endpoints in OpenTelemetry config point to `monitoring` namespace.

### No Logs in Loki

**Check**:
```bash
# Verify logsCollection preset is enabled
kubectl get opentelemetrycollector -n monitoring opentelemetry-kube-stack-daemon -o yaml | grep -A 5 "logsCollection"

# Check Loki gateway is reachable
kubectl -n monitoring exec daemonset/opentelemetry-kube-stack-daemon-collector -- wget -O- http://loki-gateway/ready
```

**Fix**: Ensure `logsCollection.enabled: true` in OpenTelemetry values.yaml.

### Grafana Datasources Not Working

**Check**:
```bash
# Verify datasource URLs
# Should all reference monitoring namespace:
# - http://kube-prometheus-stack-prometheus.monitoring.svc:9090
# - http://loki-gateway.monitoring.svc
# - http://tempo.monitoring.svc:3100
```

**Fix**: Update datasource configuration in Grafana Helm values.

### High Memory Usage

**Check**:
```bash
kubectl -n monitoring top pods
```

**Fix**: 
- Increase memory limits in Helm values
- Reduce retention periods
- Enable S3 backends for long-term storage

---

## Next Steps

Once your monitoring stack is deployed:

### 1. Explore Grafana
- **Dashboards** → Browse pre-built Kubernetes dashboards
- **Explore** → Use Prometheus/Loki/Tempo query interfaces
- **Alerting** → View active alerts and alert rules

### 2. Verify Metrics Collection
```bash
# Check all targets are being scraped
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets
```

### 3. Test Log Searching
```bash
# Access Grafana → Explore → Select Loki datasource
# Query: {namespace="openstack"}
# Try: {namespace="openstack"} |= "ERROR"
```

### 4. Create Custom Dashboards
- Use Grafana dashboard editor
- Query Prometheus for metrics
- Query Loki for logs
- Combine multiple datasources in one dashboard

### 5. Tune Alert Thresholds
- Review default alerts in PrometheusRules
- Adjust thresholds based on your baseline
- Add custom alerts for your services

### 6. Set Up Long-Term Storage (Production)
- Configure S3 backends for Loki and Tempo
- Set up Thanos for long-term Prometheus metrics
- Configure backup strategies

### 7. Enable Security
- Configure TLS for external access
- Set up authentication (LDAP, OAuth)
- Configure NetworkPolicies for namespace isolation
- Rotate default credentials

---

## Additional Resources

### Documentation

- [Observability Stack Overview](monitoring-observability-overview.md) - Comprehensive architecture guide
- [Base Component Metrics Reference](monitoring-otel-base-metrics.md) - K8s and related component metrics 
- [Prometheus Documentation](monitoring-prometheus.md) - Prometheus-specific configuration
- [Grafana Documentation](monitoring-grafana.md) - Grafana-specific configuration
- [AlertManager Slack Integration](alertmanager-slack.md) - Slack notifications

### External Documentation

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)
- [Grafana Documentation](https://grafana.com/docs/grafana/)

### Community

- [Genestack GitHub](https://github.com/rackerlabs/genestack)
- [CNCF Observability Resources](https://landscape.cncf.io/card-mode?category=observability-and-analysis)

---

## Summary

You now have a complete observability stack providing:

✅ **Metrics** - Time-series data from Kubernetes, OpenStack, and infrastructure  
✅ **Logs** - Centralized log aggregation from all services  
✅ **Traces** - Distributed tracing for request flows  
✅ **Alerting** - Automated notifications for issues  
✅ **Visualization** - Unified dashboards for all telemetry  

The stack is:
- **Unified** - All components in `monitoring` namespace
- **Scalable** - Handles large-scale deployments
- **Open Source** - No vendor lock-in
- **Production-Ready** - Battle-tested technologies

**Happy monitoring!** 🎉

---
