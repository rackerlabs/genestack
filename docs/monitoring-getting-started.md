# Getting Started with Genestack Monitoring

This guide walks you through setting up a complete monitoring stack for your Genestack deployment. The monitoring system consists of three main layers: metrics collection, visualization, and alerting.

## Overview

The Genestack monitoring stack includes:

- **Prometheus** - Time-series database and metrics collection engine
- **Grafana** - Visualization and dashboards
- **AlertManager** - Alert routing and notification management
- **Metric Exporters** - Service-specific metrics collection for OpenStack components

## Prerequisites

Before proceeding, ensure you have:

- A running Genestack deployment
- Helm 3.x installed
- Access to your Kubernetes cluster with appropriate permissions

## Step 1: Install the Prometheus Stack

The kube-prometheus-stack is the foundation of your monitoring infrastructure. It deploys and manages the core monitoring components.

Install Prometheus, which includes:

- **Prometheus Operator** - Manages the Prometheus cluster deployment lifecycle
- **Prometheus Server** - Collects and stores metrics from configured targets
- **AlertManager** - Handles alerts sent by Prometheus and routes them to notification channels (email, PagerDuty, Slack, etc.)
- **Node Exporter** - Collects hardware and OS-level metrics from cluster nodes
- **Kube State Metrics** - Exposes Kubernetes cluster state metrics

See the [Prometheus installation guide](prometheus.md) for detailed setup instructions.

## Step 2: Install Grafana

Grafana provides visualization dashboards for your metrics, alerts, and logs.

Install Grafana to:

- Create custom dashboards for monitoring OpenStack services
- Visualize metrics collected by Prometheus
- Set up alert notifications and integrations
- Analyze logs and trace data

For more information about Grafana's capabilities, visit the [Grafana](grafana.md).

## Step 3: Deploy Service-Specific Metric Exporters

With the core monitoring stack in place, deploy exporters to collect metrics from your OpenStack services and infrastructure components. All exporters are available for easy deployment.

## Step 4: Configure AlertManager

Configure AlertManager to send notifications when alerts are triggered. Available integrations include:

- [Slack Alerts](alertmanager-slack.md) - Send alerts to Slack channels
- Email notifications
- PagerDuty integration
- Webhook receivers

## Step 5: Customize Alerting Rules

### Custom Alerting Rules

Genestack includes default alerting rules that can be customized for your environment. To view or modify the custom rules:

```shell
less /etc/genestack/helm-configs/prometheus/alerting_rules.yaml
```

Edit this file to add, modify, or remove alerting rules based on your operational requirements.

### Operator-Provided Alerting Rules

Many Genestack operators come with built-in ServiceMonitor and PodMonitor resources that automatically:

- Expose scrape endpoints for metrics collection
- Provide pre-configured alerting rules tailored to the specific service

These operator-managed rules are curated for best practices and don't require manual configuration. For service-specific monitoring details, refer to the individual service documentation. For example: [RabbitMQ Operator Monitoring](infrastructure-rabbitmq.md#rabbitmq-operator-monitoring).

## Next Steps

Once your monitoring stack is deployed:

1. **Access Grafana** - Log in to Grafana and explore the pre-built dashboards
2. **Verify Metrics Collection** - Check that Prometheus is successfully scraping all targets
3. **Test Alerting** - Trigger a test alert to verify AlertManager configuration
4. **Create Custom Dashboards** - Build dashboards specific to your operational needs
5. **Tune Alert Thresholds** - Adjust alerting rules based on your environment's baseline behavior
