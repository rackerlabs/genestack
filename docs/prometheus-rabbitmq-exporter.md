## RabbitMQ Exporter

RabbitMQ Exporter is used to expose metrics from a running rabbitMQ deployment.

## Installation

Next, install the exporter

```
cd /opt/genestack/kustomize/prometheus-rabbitmq-exporter

kubectl kustomize --enable-helm . | kubectl create -n openstack -f -
```

If the installation is succesful, you should see the exporter pod in openstack namespace.
