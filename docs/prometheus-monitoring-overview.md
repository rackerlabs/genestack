# Prometheus Monitoring Overview

Genestack utilizes Prometheus for monitoring, alerting and metrics collection. To read more about Prometheus
please take a look at the [upstream docs](https://prometheus.io).

Components used to monitor and provide alerting and visualization mechanisms for genestack include:

* Prometheus
* AlertManager
* Grafana

Prometheus makes use of various metric exporters used to collect monitoring data related to specific services:

* Node Exporter(Hardware metrics)
* Kube State Exporter(Kubernetes cluster metrics)
* Mysql Exporter(MariaDB/Galera metrics)
* RabbitMQ Exporter(RabbitMQ queue metrics)
* Postgres Exporter(Postgresql metrics)
* Memcached Exporter(Memcached metrics)
* Openstack Exporter(Metrics from various Openstack products)
* Pushgateway (metrics from short-lived jobs)
* SNMP exporter (for monitoring with SNMP)

``` mermaid
%%{ init: {
      "theme": "base",
      "themeVariables": {
        "fontSize":              "15px",
        "fontFamily":            "Inter, Helvetica, Arial",
        "primaryColor":          "#1e90ff",
        "primaryBorderColor":    "#1e90ff",
        "primaryTextColor":      "#ffffff",
        "lineColor":             "#cccccc",
        "secondaryColor":        "#fafafa",
        "tertiaryColor":         "#f5f5f5",
        "edgeLabelBackground":   "#f5f5f5",
        "nodeBorder":            "rgba(0,0,0,0.4)",
        "clusterBkg":            "transparent",
        "clusterBorder":         "rgba(0,0,0,0.4)"
      },
      "flowchart": {
        "curve":      "basis",
        "nodeSpacing": 25,
        "rankSpacing": 40
      }
    } }%%
flowchart TB
  %% ──────────────────────────
  %% INTERNET (blue frame)
  %% ──────────────────────────
  subgraph INTERNET[" "]
    direction LR
    PD["🌩️&nbsp;PagerDuty / Email / Slack"]

    %% ─────────── Datacenter (red)
    subgraph RACKSPACE["Datacenter"]
      direction TB

      %% ──────── Cluster (green)
      subgraph FLEX["Cluster"]
        direction TB

        %% ─── Prometheus Ops (orange)
        subgraph PROMOPS["Prometheus&nbsp;Operations"]
          direction TB

          MC["📦&nbsp;<b>Metric&nbsp;Collectors</b><br/><span style='font-size:11px'>Node Exporter · Kube State · cAdvisor · RabbitMQ · MySQL · OpenStack · Postgres · Memcached</span>"]
          PROM(("🔥 Prometheus"))
          AM(("🔔 AlertManager"))

          MC  -.Scrapes .->  PROM
          PROM -.Targets .-> MC
          PROM --> AM
        end

        GRAF["🌀&nbsp;<b>Grafana</b><br/><span style='font-size:11px'>Visualization&nbsp;dashboard</span>"]
        GRAF -->|Queries| PROM
      end

      ENC["🗄️&nbsp;<b>Webhook&nbsp;Receiver</b><br/><span style='font-size:11px'>(creates tickets)</span>"]
    end
  end

  %% Alerts
  AM  -- Alerts --> PD
  AM  -- Alerts --> ENC

  %% ──────────────────────────
  %% BORDER HIGHLIGHTS
  %% ──────────────────────────
  style INTERNET  stroke-width:4px,stroke:#1e90ff,rx:6px,ry:6px
  style RACKSPACE stroke-width:3px,stroke:#ff4d4d,rx:6px,ry:6px
  style FLEX      stroke-width:3px,stroke:#00b300,rx:6px,ry:6px
  style PROMOPS   stroke-width:3px,stroke:#ff6600,rx:6px,ry:6px

  %% ──────────────────────────
  %% NODE COLOURS
  %% ──────────────────────────
  classDef promNode      fill:#fff3e6,color:#000,stroke:#ff6600,stroke-width:1px
  classDef grafNode      fill:#e6f0ff,color:#003366,stroke:#1e90ff,stroke-width:1px
  classDef alertNode     fill:#ffe6e6,color:#800000,stroke:#ff4d4d,stroke-width:1px
  classDef collectorNode fill:#f2f8f2,color:#003300,stroke:#00b300,stroke-width:1px
  classDef miscNode      fill:#f2f2f2,color:#333,stroke:#999,stroke-width:1px

  class PROM promNode
  class GRAF grafNode
  class AM alertNode
  class MC collectorNode
  class PD,ENC miscNode
```

## Getting started with Genestack monitoring

To get started using monitoring within the Genestack ecosystem begin with the [getting started](monitoring-getting-started.md) page.
