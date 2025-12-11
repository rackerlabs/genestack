# RabbitMQ Exporter

RabbitMQ Exporter is used to expose metrics from a running RabbitMQ deployment.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Install the RabbitMQ Exporter

??? example "`/opt/genestack/bin/install-prometheus-rabbitmq-exporter.sh`"

    ``` shell
    --8<-- "bin/install-prometheus-rabbitmq-exporter.sh"
    ```

If the installation is successful, you should see the exporter pod in the openstack namespace.
