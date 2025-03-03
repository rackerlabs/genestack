# Genestack Monitoring

Genestack is made up of a vast array of components working away to provide a Kubernetes and OpenStack cloud infrastructure
to serve our needs. Here we'll discuss in a bit more detail about how we're monitoring these components and what that
looks like.

## Overview

In this document we'll dive a bit deeper into the components and how they're being used, for a quick overview take a look
at the [Monitoring Overview](prometheus-monitoring-overview.md) documentation.

The following tooling are what was chosen as part of Genestack's default monitoring workflow primarily for their open-sourced nature and ease of integration.
These tools are not an absolute requirement and can easily be replaced by tooling of the end users choice as they see fit.

## Prometheus

Prometheus is the heavy lifter in Genestack when it comes to monitoring. We rely on Prometheus to monitor and collect metrics
for everything from the node/host health itself to Kubernetes stats and even OpenStack service metrics and operations.

Prometheus is an open-source systems monitoring and alerting toolkit built in 2012. It joined the Cloud Native Computing Foundation in 2016 as the second hosted project, after Kubernetes.

Prometheus is a powerful system that collects and stores its metrics as time series data, i.e. metrics information is stored with the timestamp at which it was recorded, alongside optional key-value pairs called labels.

To read more about Prometheus from the official source take a look at [Prometheus Docs](https://prometheus.io).

To install Prometheus within the Genestack workflow we make use of the helm charts found in the kube-prometheus-stack.

## The Kube Prometheus Stack

Genestack takes full advantage of [Helm](https://helm.sh/) and [Kustomize maninfests](https://kustomize.io/) to build a production grade Kubernetes and OpenStack Cloud.
When it comes to monitoring Genestack this is no different, Genestack makes use of the [Prometheus Community's](https://github.com/prometheus-community) [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

The kube-prometheus-stack provides an easy to operate end-to-end Kubernetes cluster monitoring system with Prometheus using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).

The kube-prometheus-stack offers many components that make monitoring fairly straight forward, scalable and easy to maintain.
In Genestack we have opted to make use of a subset of the components. As our needs change we may make further use of more of the components that the kube-prometheus-stack provides.
At the time of writing the primary components Genestack is not making use of as part of the kube-prometheus-stack are [Thanos](https://thanos.io/), a HA, long term storage Prometheus setup and [Grafana](https://grafana.com/), a metrics and alerting visualization platform.

Thanos hasn't been a need or priority to setup by default in Genestack but is available to anyone utilizing Genestack by configuring the ThanosService section found in the [prometheus-helm-overrides.yaml](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/prometheus/prometheus-helm-overrides.yaml) in the Genestack repo.
For configuration documentation of Thanos view the [Thanos Docs](https://thanos.io/tip/thanos/getting-started.md/).

As for Grafana, we install this separately to fit our needs with datasources, custom routes, auth and certs. To see more information about how we're installing Grafana as part of the Genestack workflow see: [Grafana README](https://github.com/rackerlabs/genestack/blob/main/base-helm-configs/grafana/README.md) and the installation documentation found at [Install Grafana](grafana.md).

Some of the components that we do take advantage of are the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), [AlertManager](https://prometheus.io/docs/alerting/latest/alertmanager/)
and various custom resource definitions(CRD). These CRD's include the AlertManagerConfig, PrometheusRule and things like the ServiceMonitors, which allows for dynamic service monitoring configured outside the traditional Prometheus configuration methods.
For a more complete list and their definitions view: [Prometheus Operator Design](https://prometheus-operator.dev/docs/getting-started/design/).

The below diagram gives a good view of how these components are all connected.
![Prometheus Architecture](assets/images/prometheus-architecture.png)

To install the kube-prometheus-stack as part of Genestack's workflow view the [Installing Prometheus Doc](prometheus.md).

As for the metrics themselves they are largely provided by 'exporters' which simply export the data exposed by various services we wish to monitor in order for Prometheus to injest them.
The kube-prometheus-stack provides a set of key exporters deployed by default, such as, node-exporter and kube-state-metrics, that Genestack relies on to monitor its infrastructure.

## Metric Exporters

Genestack makes heavy use of prometheus exporters as there are many services that require monitoring. Below is the list of exporters Genestack deploys to monitor its systems.

* ### Node Exporter:
The [node-exporter](https://github.com/prometheus/node_exporter) is geared toward hardware and OS metrics exposed by *NIX kernels.
The node-exporter exposes many important metrics by default such as cpu, hwmon, meminfo, loadavg and many more. For a full list view the [node-exporter README](https://github.com/prometheus/node_exporter?tab=readme-ov-file#collectors).

* ### Kube State Metrics:
The [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) service provides metrics regarding the health of Kubernetes objects such as deployments, nodes and pods.
The kube-state-metrics service provides detailed information about the health and state of Kubernetes components and objects such as ConfigMaps, Jobs, Nodes, Deployments and many many more.
View the [kube-state-docs](https://github.com/kubernetes/kube-state-metrics/tree/main/docs) for a complete list and further information.

Beyond those two highly important ones installed by default are many more equally important metric exporters that we install as part of Genestack's workflow that we'll go over next.

* ### MariaDB/MySQL Exporter:
Genestack uses a couple different database solutions to run OpenStack or just for general storage capabilities, the most prominent of them is MySQL or more specifically within Genestack MariaDB and Galera.
When installing [MariaDB](infrastructure-mariadb.md) as part of Genestack's workflow it is default to enable metrics which deploys its own service monitor as part of the [mariadb-operator](https://mariadb-operator.github.io/mariadb-operator/latest/) helm charts.
This is great if you have already installed Prometheus, if not the MariaDB deploy will fail and there may be other potential database disrupting issues if you have a need to update metrics settings alone. It is encouraged to install the [Mysql Exporter](prometheus-mysql-exporter.md) as a separate exporter that can be updated without having to run MariaDB deploy/update commands.
The [mysql-exporter](https://github.com/prometheus/mysqld_exporter) is provided by the prometheus organization and is also what's used within the MariaDB Operator. When installed separately via the Genestack [Mysql Exporter](prometheus-mysql-exporter.md) installation instructions the [prometheus-mysql-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-mysql-exporter) helm charts are used.
The mysql-exporter provides many important metrics related to the overall health and operation of your MariaDB/Galera cluster. You can view more details about what's exported in the [mysqld-exporter README](https://github.com/prometheus/mysqld_exporter?tab=readme-ov-file#mysql-server-exporter-).

* ### Postgres Exporter:
Genestack also makes use of PostgreSQL for a limited set of services. At the time of writing only [Gnocchi](openstack-gnocchi.md) is making use of it. It's still an important part of the system and requires monitoring.
To do so we make use of the Prometheus community helm charts [prometheus-postgres-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-postgres-exporter) and it's installed as part of Genestack's workflow by following the [Postgres Exporter](prometheus-postgres-exporter.md).
Further information about the exporter and the metrics it collects and exposes can be found in the [postgres_exporter](https://github.com/prometheus-community/postgres_exporter/blob/master/README.md) documentation.

* ### RabbitMQ Exporter:
Many OpenStack services require RabbitMQ to operate and is part of Genestack's infrastructure deployment. [RabbitMQ](infrastructure-rabbitmq.md) cluster can be finicky at times and it's important to be able to monitor it.
Genestack makes use of the Prometheus community's [prometheus-rabbitmq-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-rabbitmq-exporter) helm charts and is installed as part of Genestack's workflow via [RabbitMQ Exporter](prometheus-rabbitmq-exporter.md).
The RabbitMQ exporter provides many detailed metrics such as channels, connections and queues. View a complete list of the metrics exposed in the [RabbitMQ Exporter Docs](https://github.com/kbudde/rabbitmq_exporter/blob/main/metrics.md).

* ### Memcached Exporter:
Many OpenStack services make use of Memcached as a caching layer which is part of Genestack's infrastructure deployment found in the [Memcached Deployment Doc](infrastructure-memcached.md).
We monitor Memcached utilizing Prometheus community's helm chart for the [prometheus-memcached-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-memcached-exporter).
The memcached-exporter offers many metrics for things like uptime, connections and limits. For a full list view the [Memcached Exporter Docs](https://github.com/prometheus/memcached_exporter/blob/master/README.md#collectors).

* ### BlackBox Exporter:
The blackbox exporter allows blackbox probing of endpoints over HTTP, HTTPS, DNS, TCP, ICMP and gRPC. This exporter is ideally deployed cross region in order to check the service health across the network.
Deploying it as part of the cluster it's monitoring does still have its benefits as it will reach out the gateways and back in to provide some context about the health of your services. This can also serve as a simple way to check endpoint cert expiration.
Install this exporter following the documentation found at [BlackBox Deployment Doc](prometheus-blackbox-exporter.md). For more information regarding the BlackBox exporter see the upstream [BlackBox Exporter Doc](https://github.com/prometheus/blackbox_exporter)

* ### OVN Monitoring:
OVN is installed a bit differently compared to the rest of the services as you can see in the [OVN Deployment Doc](infrastructure-ovn-setup.md). The installation ends up installing [Kube-OVN](https://github.com/kubeovn/kube-ovn) which exposes metrics about its operations.
However, at this point, there's no way for Prometheus to scrape those metrics. The way Genestack achieves this is by applying ServiceMonitor CRD's so Prometheus knows how to find and scrape these services for metric collection.
In the [Kube-OVN Deployment Doc](https://docs.rackspacecloud.com/prometheus-kube-ovn/) we see a simple command to apply the contents of [prometheus-ovn](https://github.com/rackerlabs/genestack/tree/main/base-kustomize/prometheus-ovn).
The contents are a set of ServiceMonitor manifests that define labels, namespaces and names to match to a service to monitor which is percisely what a [ServiceMonitor](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.ServiceMonitor) CRD is designed to do.
You can view more information about the metrics provided in the [Kube-OVN Metrics Doc](https://kubeovn.github.io/docs/stable/en/reference/metrics/).
Once we've ran the apply command we will have installed ServiceMonitors for Kube-OVN services:
    * CNI
    * Controller
    * OVN
    * Pinger

    You can view more information about OVN monitoring in the [OVN Monitoring Introduction Docs](ovn-monitoring-introduction.md).

* ### Nginx Gateway Monitoring:
Genestack makes use of the Gateway API for its implementation of [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). Genestack deploys this as part of its infrastructure, view the [Gateway Deployment Doc](infrastructure-gateway-api.md) for more information.
Nginx Gateway does expose important metrics for us to gather but it does not do so via a service. Instead we must make use another Prometheus CRD the [PodMonitor](https://prometheus-operator.dev/docs/getting-started/design/#podmonitor).
The install is similar to the above OVN monitoring as you can see in the [Nginx Gateway Exporter Deployment Doc](prometheus-nginx-gateway.md). The primary difference is the need to target and match on a pod that's exposing the metrics rather than a service.
You can view more information about the metrics exposed by the Nginx Gateway by viewing the [Nginx Gateway Fabric Docs](https://docs.nginx.com/nginx-gateway-fabric/how-to/monitoring/prometheus/).

* ### OpenStack Metrics:
OpenStack Metrics are a bit different compared to the rest of the exporters as there's no single service, pod or deployment that exposes Prometheus metrics for collection. Instead, Genestack uses the [OpenStack Exporter](https://github.com/openstack-exporter/openstack-exporter) to gather the metrics for us.
The OpenStack exporter reaches out to all the configured OpenStack services, queries their API for stats and packages them as metrics Prometheus can then process. The OpenStack exporter is configurable and can collect metrics from just about every OpenStack service such as Keystone, Nova, Octavia etc..
View the [OpenStack Exporter Deployment Doc](prometheus-openstack-metrics-exporter.md) for more information on how to configure and deploy the exporter in the Genestack workflow.
You can view more information about the OpenStack exporter in general and what metrics are collected in the [OpenStack Exporter Doc](https://github.com/openstack-exporter/openstack-exporter?tab=readme-ov-file#metrics).

* ### Ceph Monitoring:
[Ceph](https://rook.io/docs/rook/latest-release/Getting-Started/intro/) comes with its own set of optimized collectors and exporters. In terms of deploying [Ceph Internally](storage-ceph-rook-internal.md) there is nothing for us to do. The service and ServiceMonitor CRD's are created and metrics will be available in Prometheus assuming metric collection is enabled in the helm chart.
If we are deploying [Ceph externally](storage-ceph-rook-external.md) then we will want to add another Prometheus CRD, the [ScrapeConfig](https://prometheus-operator.dev/docs/getting-started/design/#scrapeconfig).
The ScrapeConfig allows us to define external sources for Prometheus to scrape.
    !!! example "Example ScrapeConfig for external Ceph monitoring"

        ``` yaml
        apiVersion: monitoring.coreos.com/v1alpha1
        kind: ScrapeConfig
        metadata:
           name: external-ceph-monitor
           namespace: prometheus
           labels:
               prometheus: sys\em-monitoring-prometheus
        spec:
          staticConfigs:
            - labels:
                job: prometheus
              targets:
                - 192.12.34.567:9283
        ```
With this example we can simply apply it to the cluster and Prometheus will soon begin scraping metrics for our external Ceph cluster.
We can see additional information about the Ceph exporter at the [Ceph Github Docs](https://github.com/rook/rook/blob/master/design/ceph/ceph-exporter.md).
For additional information regarding the metrics collected and exposed from Ceph clusters view the [Ceph Telemetry Doc](https://github.com/rook/rook/blob/master/design/ceph/ceph-telemetry.md?plain=1).

* ### Push Gateway:
The [Prometheus Push Gateway](https://github.com/prometheus/pushgateway) is used to gather metrics from short-lived jobs, like Kubernetes CronJobs.
It's not capable of turning Prometheus into a push-based monitoring system and should only be used when there is no other way to collect the desired metrics.
Currently, in Genestack the push gateway is only being used to gather stats from the OVN-Backup CronJob as noted in the [Pushgateway Deployment Doc](prometheus-pushgateway.md).

* ### SNMP Exporter:
The [Prometheus SNMP Exporter](https://github.com/prometheus/snmp_exporter) is
used for gathering SNMP metrics. A default Genestack installation does not make
use of it, so you do not need to install it unless you plan to do additional
configuration beyond Genestack defaults and specifically plan to monitor some
SNMP-enabled devices.

* ### Textfile Collector:
It's possible to gather node/host metrics that aren't exposed by any of the above exporters by utilizing the [Node Exporter Textfile Collector](https://github.com/prometheus/node_exporter?tab=readme-ov-file#textfile-collector).
Currently, in Genestack the textfile-collector is used to collect kernel-taint stats. To view more information about the textfile-collector and how to deploy your own custom exporter view the [Custom Metrics Deployment Doc](prometheus-custom-node-metrics.md).

This is currently the complete list of exporters and monitoring callouts deployed within the Genestack workflow. That said, Genestack is constantly evolving and list may grow or change entirely as we look to further improve our systems!
With all these metrics available we need a way to visualize them to get a better picture of our systems and their health, we'll discuss that next!

## Visualization

In Genestack we deploy [Grafana](https://grafana.com/) as our default visualization tool. Grafana is open-sourced tooling which aligns well with the Genestack ethos while providing seamless visualization of the metrics generated by our systems.
Grafana also plays well with Prometheus and [Loki](infrastructure-loki.md), the default logging tooling deployed in Genestacks workflow, with various datasource plugins making integration a breeze.
Installing [Grafana](grafana.md) within Genestack is fairly straight forward, just follow the [Grafana Deployment Doc](grafana.md).

The installation also takes care of installing the primary [datasources](https://grafana.com/docs/grafana/latest/datasources/) which are Grafana plugins used for querying specific datasets.
For example in Genestack we install the [Prometheus and Loki datasources](https://github.com/rackerlabs/genestack/blob/8b90d22b19795acd364afb05f08617c326f6c8f6/base-helm-configs/grafana/datasources.yaml#L4) as part of Genestack's default workflow.
You can manually add additional datasources by following the [add datasource](https://grafana.com/docs/grafana/latest/datasources/#add-a-data-source) documentation.
More information about the primary datasources can be found in the [Prometheus datasource](https://grafana.com/docs/grafana/latest/datasources/prometheus/) and [Loki datasource](https://grafana.com/docs/grafana/latest/datasources/loki/) documentation.

As things stand now, the Grafana deployment does not deploy dashboards as part of the default deployment instructions. However, there are dashboards available found in the [etc directory](https://github.com/rackerlabs/genestack/tree/main/etc/grafana-dashboards) of the Genestack repo that can be installed manually by importing them into Grafana.
View the [importing dashboards](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/import-dashboards/) documentation for more information.
The dashboards available cover just about every exporter/metric noted here and then some. Some of the dashboards may not be complete or may not provide the desired view. Please feel free to adjust them as needed and submit a PR to [Genestack repo](https://github.com/rackerlabs/genestack) if they may help others!

## Next Steps

With what's deployed as part of our Genestack workflow today we get a fairly clear view of all our systems that allows us to properly monitor our Genestack cluster.
As we begin to expand to more regions or add other services that exist outside of our cluster, such as Swift, with its own monitoring systems a need may arise for tooling not provided within Genestack.
For example, Grafana may not provide all the features we'd like in a dashboard and we may want to find something that could combine multiple regions while being able to provide automation activity on alerts and way to notify support and on-call team members.
At that point it may be time to look at replacing certain tooling or running them in conjunction with things like [Dynatrace](https://www.dynatrace.com/) or [Datadog](https://www.datadoghq.com/) or any of the many tools available to fit our needs.
