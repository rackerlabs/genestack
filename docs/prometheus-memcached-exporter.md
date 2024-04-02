# Memcached Exporter

Memcached Exporter is used to expose metrics from a running Memcached deployment.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Install the Memcached Exporter

!!! note

    Following this installation step will also deploy [memcached](infrastructure-memcached.md) in a HA production ready cluster that includes monitoring via the metric exporters. If memcached is already installed running this will simply enable the exporters which allows Prometheus to begin scraping the memcached service.

### Deploy the Memcached Cluster With Monitoring Enabled

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached/base-monitoring | \
    kubectl apply --namespace openstack --server-side -f -
```

!!! success
    If the installation is successful, you should see the exporter pod in the openstack namespace.
