# Deploy a Memcached

## Deploy the Memcached Cluster

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached/base | kubectl apply --namespace openstack -f -
```

!!! note

    Memcached has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

### Alternative - Deploy the Memcached Cluster With Monitoring Enabled

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached/base-monitoring | kubectl apply --namespace openstack -f -
```

!!! note

    Memcached has a base-monitoring configuration which is HA and production ready that also includes a metrics exporter for prometheus metrics collection. If you'd like to have monitoring enabled for your memcached cluster ensure the prometheus operator is installed first ([Deploy Prometheus](prometheus.md)).

## Verify readiness with the following command.

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```
