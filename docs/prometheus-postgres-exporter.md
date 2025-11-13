# PostgresSQL Exporter

PostgresSQL Exporter is used to expose metrics from a running PostgresSQL deployment.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Install the PostgresSQL Exporter

``` shell
bin/install-prometheus-postgres-exporter.sh
```
!!! note "Helm chart versions are defined in (opt)/genestack/helm-chart-versions.yaml and can be overridden in (etc)/genestack/helm-chart-versions.yaml"
!!! success
    If the installation is successful, you should see the exporter pod in the openstack namespace.
