# Genestack Alerting

Genestack is made up of a vast array of components working away to provide a Kubernetes and OpenStack cloud infrastructure
to serve our needs. Here we'll discuss in a bit more detail about how we configure and make use of our alerting mechanisms
to maintain the health of our systems.

## Overview

In this document we'll dive a bit deeper into the alerting components and how they're configured and used to maintain the health of our genestack.
Please take a look at the [Monitoring Information Doc](monitoring-info.md) for more information regarding how the metrics and stats are collected in order to make use of our alerting mechanisms.

## Prometheus Alerting

As noted in the [Monitoring Information Doc](monitoring-info.md) we make heavy use of [Prometheus](https://prometheus.io) and within the Genestack workflow specifically we deploy the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) which handles deployment of the Prometheus servers, operators, alertmanager and various other components.
Genestack uses Prometheus for metrics and stats collection and overall monitoring of its systems that are described in the [Monitoring Information Doc](monitoring-info.md).
With the metrics and stats collected we can now use Prometheus to generate alerts based on those metrics and stats using the Prometheus [Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/).
The Prometheus alerting rules allows us to define conditions we want to escalate using the [Prometheus expression language](https://prometheus.io/docs/prometheus/latest/querying/basics/) which can be visualized and sent to an external notification systems for further action.

A simple example of an alerting rule would be this RabbitQueueSizeTooLarge
!!! example "RabbitQueueSizeTooLarge Alerting Rule Example"

        ``` yaml
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
                summary: "Rabbit queue size too large (instance {{ `{{ $labels.instance }}` }} )"
        ```

In Genestack we have separated the alerting rules config out from the primary helm configuration using the `additionalPrometheusRulesMap` directive to make it a bit easier to maintain.
Doing it this way allows for easier review of new rules, better maintainability, easier updates of the stack and helps with portability for larger deployments. Keeping our configurations separated and checked in to the repo in such a manner is ideal for these reasons.
The alternative is to create the rules within your observability platform, in Genestack's default workflow this would be Grafana. Although the end user is free to make such a choice you end up losing a lot of the benefits we just mentioned while creating additional headaches when deploying to new clusters or even during basic updates.

You can view the rest of the default alerting rule configurations in the Genestack repo [alerting rules](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/alerting_rules.yaml) yaml file.

To deploy any new rules you would simply run the [Prometheus Deployment](prometheus.md) and Helm/Prometheus will take care of updating the configurations from there.
!!! example "Run the Prometheus deployment Script `bin/install-prometheus.sh`"

    ``` shell
    --8<-- "bin/install-prometheus.sh"
    ```

## Alert Manager

The kube-prometheus-stack not only contains our monitoring components such as Prometheus and related CRD's, but it also contains another important features, the [Alert Manager](https://prometheus.io/docs/alerting/latest/alertmanager/).
The Alert Manager is a crucial component in the alerting pipeline as it takes care of grouping, deduplicating and even routing the alerts to the correct receiver integrations.
Prometheus is responsible for generating the alerts based on the [Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) we [defined](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/alerting_rules.yaml).
Prometheus then sends these alerts to the [Alert Manager](https://prometheus.io/docs/alerting/latest/alertmanager/) for further processing.

The below diagram gives a better idea of how the Alert Manager works with Prometheus as a whole.
![Prometheus Architecture](assets/images/prometheus-architecture.png)

Genestack provides a basic [alertmanager_config](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/alertmanager_config.yaml) that's separated out from the primary Prometheus configurations for similar reasons the [alerting rules](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/alerting_rules.yaml) are.
Here we can see the key components of the Alert Manager config that allows us to group and send our alerts to external services for further action.

* [Inhibit Rules](https://prometheus.io/docs/alerting/latest/configuration/#inhibition-related-settings)
    Inhibition rules allows us to establish dependencies between systems or services so that only the most relevant set of alerts are sent out during an outage
* [Routes](https://prometheus.io/docs/alerting/latest/configuration/#route-related-settings)
    Routing-related settings allow configuring how alerts are routed, aggregated, throttled, and muted based on time.
* [Receivers](https://prometheus.io/docs/alerting/latest/configuration/#general-receiver-related-settings)
    Receiver settings allow configuring notification destinations for our alerts.

These are all explained in greater detail in the [Alert Manager Docs](https://prometheus.io/docs/alerting/latest/configuration/#configuration).

The Alert Manager has various baked-in methods to allow those notifications to be sent to services like [email](https://prometheus.io/docs/alerting/latest/configuration/#email_config), [PagerDuty](https://prometheus.io/docs/alerting/latest/configuration/#pagerduty_config) and [Microsoft Teams](https://prometheus.io/docs/alerting/latest/configuration/#msteams_config).
For a full list and further information view the [receiver information documentation](https://prometheus.io/docs/alerting/latest/configuration/#receiver-integration-settings).

The following list contains a few examples of these receivers as part of the [alertmanager_config](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/alertmanager_config.yaml) found in Genestack.

* [Slack Receiver](alertmanager-slack.md)
* [PagerDuty Receiver](alertmanager-pagerduty.md)
* [Microsoft Teams Receiver](alertmanager-msteams.md)

We can now take all this information and build out an alerting workflow that suits our needs!

## Genestack alerts

This section contains some information on individual Genestack alert.

### MariaDB backup alert

Based on a schedule of 6 hours by default, it allows 1 hour to upload and
alerts when MySQL doesn't successfully complete a backup.

It alerts at warning level the first time this happens, and at critical level the second time this happens.
