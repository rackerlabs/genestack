# Memcached Exporter

Memcached Exporter is used to expose metrics from a running Memcached deployment. The memcached exporter is an integrated part
of the memcached deployment in Genestack but will need to be enabled.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Deploy the Memcached Cluster With Monitoring Enabled

Edit the Helm overrides file for memcached at `/etc/genestack/helm-configs/memcached/memcached-helm-overrides.yaml` and add the following values
to enable the memcached exporter:

``` yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
```

Once the changes have been made, apply the changes to the memcached deployment with the `/opt/genestack/bin/install-memcached.sh` script

??? example "`/opt/genestack/bin/install-memcached.sh`"

    ``` shell
    --8<-- "bin/install-memcached.sh"
    ```
