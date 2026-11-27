# Prometheus Pushgateway

Prometheus Pushgateway is useful for short-lived jobs, such as Kubernetes `CronJob` workloads, that need to push metrics before they exit.

## Paths

* Base Helm values: `/opt/genestack-observability/helm-configs/prometheus-pushgateway/`
* Service overrides: `/etc/genestack/helm-configs/observability/prometheus-pushgateway/`
* Base Kustomize: `/opt/genestack-observability/kustomize/prometheus-pushgateway/base/`
* Kustomize overlay: `/etc/genestack/kustomize/observability/prometheus-pushgateway/overlay/`

## Install

```shell
/opt/genestack/bin/install-observability.sh prometheus-pushgateway
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=prometheus-pushgateway
kubectl -n monitoring get servicemonitor prometheus-pushgateway
```
