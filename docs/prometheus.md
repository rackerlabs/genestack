##Prometheus

We are using Prometheus for monitoring and metrics collection backend.
To read more about Prometheus see: https://prometheus.io

#### Install kube-prometheus helm chart

```
cd /opt/genestack/kustomize/prometheus

kubectl kustomize --enable-helm . | kubectl create -f -
```
