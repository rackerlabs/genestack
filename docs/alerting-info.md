# Genestack Alerting

Genestack is made up of a vast array of components working away to provide a Kubernetes and OpenStack cloud infrastructure to serve our needs. Here we'll discuss in a bit more detail about how we configure and make use of our alerting mechanisms to maintain the health of our systems.

## Overview

In this document we'll dive a bit deeper into the alerting components and how they're configured and used to maintain the health of our genestack. Please take a look at the [Monitoring Information Doc](observability-info.md) for more information regarding how the metrics and stats are collected in order to make use of our alerting mechanisms.

## Prometheus Alerting

As noted in the [Monitoring Information Doc](observability-info.md) we make heavy use of [Prometheus](https://prometheus.io/) and within the Genestack workflow specifically we deploy the `kube-prometheus-stack` which handles deployment of the Prometheus servers, operators, alertmanager and various other components. Genestack uses Prometheus for metrics and stats collection and overall monitoring of its systems that are described in the Monitoring Information Doc.

With the metrics and stats collected we can now use Prometheus to generate alerts based on those metrics and stats using the Prometheus [Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/). The Prometheus alerting rules allow us to define conditions we want to escalate using the Prometheus expression language which can be visualized and sent to external notification systems for further action.

A simple example of an alerting rule would be this RabbitQueueSizeTooLarge:

!!! example "RabbitQueueSizeTooLarge Alerting Rule Example"

    ```yaml
    rabbitmq-alerts:
      groups:
      - name: Prometheus Alerts
        rules:
        - alert: RabbitQueueSizeTooLarge
          expr: rabbitmq_queuesTotal>25
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Rabbit queue size too large (instance {{ $labels.instance }} )"
    ```

In Genestack we have separated the alerting rules config out from the primary Helm configuration using the `additionalPrometheusRulesMap` directive to make it easier to maintain. Doing it this way allows for easier review of new rules, better maintainability, easier updates of the stack and helps with portability for larger deployments. Keeping our configurations separated and checked in to the repo in such a manner is ideal for these reasons.

The alternative is to create the rules within your observability platform, in Genestack's default workflow this would be Grafana. Although the end user is free to make such a choice you end up losing a lot of the benefits we just mentioned while creating additional headaches when deploying to new clusters or even during basic updates.

Prometheus alerting rule source files are now maintained in the observability repository under:

```text
/opt/genestack-observability/alerts/prometheus-alerts/
/opt/genestack-observability/alerts/recording/
```

They are rendered into native `PrometheusRule` resources by the separate Genestack Prometheus rules release. Alertmanager defaults are stored at `/opt/genestack-observability/helm-configs/kube-prometheus-stack/alertmanager_config.yaml`, while site-specific Alertmanager overrides remain under `/etc/genestack/helm-configs/kube-prometheus-stack/`.

To deploy or update Genestack-managed Prometheus rules:

!!! example "Deploy Prometheus alerting and recording rules"

    ```shell
    /opt/genestack/bin/install-observability.sh prometheus-rules
    ```

## Alert Manager

The kube-prometheus-stack not only contains our monitoring components such as Prometheus and related CRDs, but it also contains another important feature, the [Alert Manager](https://prometheus.io/docs/alerting/latest/alertmanager/). The Alert Manager is a crucial component in the alerting pipeline as it takes care of grouping, deduplicating and even routing the alerts to the correct receiver integrations. Prometheus is responsible for generating the alerts based on the Alerting Rules you define for your environment.

Prometheus then sends these alerts to the Alert Manager for further processing.

The below diagram gives a better idea of how the Alert Manager works with Prometheus as a whole.

Genestack provides a basic `alertmanager_config` that is separated out from the primary Prometheus configuration so it can be overridden independently. Here we can see the key components of the Alert Manager config that allows us to group and send our alerts to external services for further action.

* [Inhibit Rules](https://prometheus.io/docs/alerting/latest/configuration/#inhibit_rule) allow us to establish dependencies between systems or services so that only the most relevant set of alerts are sent out during an outage.
* [Routes](https://prometheus.io/docs/alerting/latest/configuration/#route) allow configuring how alerts are routed, aggregated, throttled, and muted based on time.
* [Receivers](https://prometheus.io/docs/alerting/latest/configuration/#receiver) allow configuring notification destinations for our alerts.

These are all explained in greater detail in the [Alert Manager Docs](https://prometheus.io/docs/alerting/latest/alertmanager/).

The Alert Manager has various baked-in methods to allow those notifications to be sent to services like email, PagerDuty and Microsoft Teams. For a full list and further information view the Prometheus receiver information documentation.

The following list contains a few examples of these receivers as part of the `alertmanager_config` found in Genestack.

* [Slack Receiver](alertmanager-slack.md)
* [PagerDuty Receiver](alertmanager-pagerduty.md)
* [Microsoft Teams Receiver](alertmanager-msteams.md)

We can now take all this information and build out an alerting workflow that suits our needs!

## Genestack alerts

Genestack supplies default alerts, some of which are configured as part of the Prometheus install and some of them come from the exporter deployments directly and are not controlled by Genestack. Genestack-managed alerting and recording rule source files are maintained under `/opt/genestack-observability/alerts/`.
