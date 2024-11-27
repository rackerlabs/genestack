# PostgresSQL Exporter

PostgresSQL Exporter is used to expose metrics from a running PostgresSQL deployment.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Install the PostgresSQL Exporter

``` shell
bin/install-chart.sh prometheus-postgres-exporter
```

!!! success
    If the installation is successful, you should see the exporter pod in the openstack namespace.
