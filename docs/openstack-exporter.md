# OpenStack Exporter

OpenStack Exporter probes OpenStack API endpoints and exposes their availability metrics to Prometheus.

## Paths

- Local chart: `/opt/genestack/base-helm-configs/openstack-api-exporter-chart/`
- Service overrides: `/etc/genestack/helm-configs/openstack-api-exporter-chart/`
- Kustomize overlay: `/etc/genestack/kustomize/openstack-api-exporter-chart/overlay/`

## Prerequisites

- `kube-prometheus-stack` installed
- `keystone-auth-openstack-exporter` secret available in the `monitoring` namespace

The supported way to generate the Keystone secret is:

```shell
/opt/genestack/bin/create-secrets.sh
```

## Install

```shell
/opt/genestack/bin/install-openstack-exporter.sh
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
