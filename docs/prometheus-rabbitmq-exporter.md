# RabbitMQ Exporter

RabbitMQ Exporter is used to expose metrics from a running rabbitMQ deployment.

## Installation

Install the RabbitMQ Exporter

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/prometheus-rabbitmq-exporter | \
  kubectl -n openstack apply --server-side -f -
```

If the installation is successful, you should see the exporter pod in openstack namespace.
