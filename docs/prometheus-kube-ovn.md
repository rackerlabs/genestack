# Kube-OVN Monitoring

Kube-OVN exposes a lot of important metrics about the controller, pinger and cni plugin. We simply
create a service monitor to pull these metrics into Prometheus.


## Installation

``` shell
kubectl apply -f /opt/genestack/kustomize/prometheus-ovn/
```

!!! success
    If the installation is successful, you should see metrics with `kube_ovn_*` in Prometheus.
