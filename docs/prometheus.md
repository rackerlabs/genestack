# Prometheus

We are using Prometheus for monitoring and metrics collection backend. To read more about Prometheus using the [upstream docs](https://prometheus.io).

#### Install kube-prometheus helm chart

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/prometheus | kubectl apply --server-side -f -
```
