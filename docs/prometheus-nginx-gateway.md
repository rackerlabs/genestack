# NGINX Gateway Fabric Monitoring

NGINX Gateway Fabric exposes a lot of important metrics about the gateway. We simply
create a pod monitor to pull these metrics into Prometheus.


## Installation

``` shell
kubectl apply -f /etc/genestack/kustomize/prometheus-nginx-gateway/base
```

!!! success
    If the installation is successful, you should see metrics with `nginx_gateway_fabric_*` in Prometheus.
