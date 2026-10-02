# OpenStack Exporter

OpenStack Exporter probes OpenStack API endpoints and exposes their availability metrics to Prometheus.

## Paths

* Base chart/configuration: `/opt/genestack-observability/helm-configs/openstack-api-exporter-chart/`
* Service overrides: `/etc/genestack/helm-configs/openstack-api-exporter-chart/`
* Kustomize overlay: `/etc/genestack/kustomize/openstack-api-exporter-chart/overlay/`

## Prerequisites

* `kube-prometheus-stack` installed
* `keystone-auth-openstack-exporter` secret available in the `monitoring` namespace

The exporter installer and shared monitoring helpers ensure the required Keystone authentication secret exists.

## Install

```shell
/opt/genestack/bin/install-observability.sh openstack-exporter
```

## Verify

```shell
kubectl -n monitoring get pods -l app=openstack-exporter
kubectl -n monitoring get svc,servicemonitor | grep openstack-exporter
kubectl -n monitoring port-forward svc/openstack-exporter 9180:<service-port>
```

Then open Prometheus and confirm the `openstack-exporter` ServiceMonitor target is healthy:

```shell
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```
