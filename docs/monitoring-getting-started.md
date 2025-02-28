# Getting started with genestack monitoring

In order to begin monitoring your genestack deployment we first need to deploy the core prometheus components

## Install the Prometheus stack

Install [Prometheus](prometheus.md) which is part of the kube-prometheus-stack and includes:

* Prometheus and the Prometheus operator to manage the Prometheus cluster deployment
* AlertManager which allows for alerting configurations to be set in order to notify various services like email or PagerDuty for specified alerting thresholds

The [Prometheus](prometheus.md) kube-prometheus-stack will also deploy a couple core metric exporters as part of the stack, those include:

* Node Exporter(Hardware metrics)
* Kube State Exporter(Kubernetes cluster metrics)

## Install Grafana

We can then deploy our visualization dashboard Grafana

* [Install Grafana](grafana.md)

Grafana is used to visualize various metrics provided by the monitoring system as well as alerts and logs, take a look at the [Grafana](https://grafana.com/) documentation for more information

## Install the metric exporters and pushgateway

Now let's deploy our exporters and pushgateway!

* [Mysql Exporter](prometheus-mysql-exporter.md)
* [RabbitMQ Exporter](prometheus-rabbitmq-exporter.md)
* [Postgres Exporter](prometheus-postgres-exporter.md)
* [Memcached Exporter](prometheus-memcached-exporter.md)
* [Openstack Exporter](prometheus-openstack-metrics-exporter.md)
* [Pushgateway](prometheus-pushgateway.md)

## Next steps

### Configure alert manager

Configure the alert manager to send the specified alerts to slack as an example, see: [Slack Alerts](alertmanager-slack.md)

... and more ...

### Update alerting rules

Within the genestack repo we can update our custom alerting rules via the alerting_rules.yaml to fit our needs

View alerting_rules.yaml in:

``` shell
less /etc/genestack/helm-configs/prometheus/alerting_rules.yaml
```

However, many opreators comes with ServiceMonitor and PodMonitor services. These services expose, scrape endpoints
out of the box. These operators will also provide alerting rules curated for the specific service. See specific
service install for any monitoring rules. Example: [RabbitMQ Operator Monitoring](infrastructure-rabbitmq.md#rabbitmq-operator-monitoring)
