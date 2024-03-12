# Prometheus

We are taking advantage of the prometheus community kube-prometheus-stack as well as other various components for monitoring and alerting. For more information take a look at [Prometheus Kube Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

#### Install kube-prometheus-stack helm chart

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/prometheus | kubectl apply --server-side -f -
```

!!! success
    If the installation is successful, you should see the related exporter pods in the prometheus namespace.
