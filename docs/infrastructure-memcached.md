# Deploy a Memcached

## Deploy the Memcached Cluster

``` shell
kubectl kustomize --enable-helm /etc/genestack/kustomize/memcached/base | kubectl apply --namespace openstack -f -
```

!!! note

    Memcached has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

### Alternative - Deploy the Memcached Cluster With Monitoring Enabled

!!! note

    Memcached has a base-monitoring configuration which is HA and production ready that also includes a metrics exporter for prometheus metrics collection. If you'd like to have monitoring enabled for your memcached cluster ensure the prometheus operator is installed first ([Deploy Prometheus](prometheus.md)).

View the [memcached exporter](prometheus-memcached-exporter.md) instructions to install a HA ready memcached cluster with monitoring and metric collection enabled.

## Verify readiness with the following command.

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```

### Create shared os-memcached secret

``` shell
kubectl --namespace openstack \
        create secret generic os-memcached \
        --type Opaque \
        --from-literal=memcache_secret_key="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

!!! Note

    This is a shared secret that is distributed to all services that require it. Rotating this value means updating all services.
