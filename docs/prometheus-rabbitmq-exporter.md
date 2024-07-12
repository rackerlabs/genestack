# RabbitMQ Exporter

RabbitMQ Exporter is used to expose metrics from a running RabbitMQ deployment.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Install the RabbitMQ Exporter

``` shell
kubectl kustomize --enable-helm /opt/genestack/base-kustomize/prometheus-rabbitmq-exporter | \
    kubectl --namespace openstack apply --server-side -f -
```

!!! success
    If the installation is successful, you should see the exporter pod in the openstack namespace.
