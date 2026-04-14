# Getting Started with Genestack Monitoring

This guide documents the supported monitoring install flow for Genestack. The monitoring stack is installed component-by-component, and each component uses the same override layout as the rest of the platform:

- Helm overrides: `/etc/genestack/helm-configs/<service>`
- Kustomize overlays: `/etc/genestack/kustomize/<service>/overlay`

That service-specific layout is the Genestack standard. The docs still group the monitoring stack conceptually so you can reason about it as one system:

- [Prometheus](monitoring-prometheus.md) for metrics storage, scraping, and alerting
- [Loki](monitoring-loki.md) for logs
- [Tempo](monitoring-tempo.md) for traces
- [Grafana](monitoring-grafana.md) for dashboards and datasources
- [OpenTelemetry](monitoring-opentelemetry.md) for telemetry collection and infrastructure receivers
- [OpenStack Exporter](openstack-exporter.md) for OpenStack API availability probes
- [Pushgateway](prometheus-pushgateway.md) for short-lived job metrics

The supported install order is:

1. `kube-prometheus-stack`
2. `loki`
3. `tempo`
4. `grafana`
5. `opentelemetry-kube-stack`

## Prerequisites

- A bootstrapped Genestack host
- `kubectl` pointed at the target cluster
- `helm` 3.x
- `yq` 4.x
- A generated `/etc/genestack/kubesecrets.yaml`

Run bootstrap first:

```shell
/opt/genestack/bootstrap.sh
```

Bootstrap creates the monitoring override directories under `/etc/genestack` so the install scripts can use the same pattern as the rest of Genestack. After bootstrap you should have:

- `/etc/genestack/helm-configs/kube-prometheus-stack`
- `/etc/genestack/helm-configs/loki`
- `/etc/genestack/helm-configs/tempo`
- `/etc/genestack/helm-configs/grafana`
- `/etc/genestack/helm-configs/opentelemetry-kube-stack`
- `/etc/genestack/helm-configs/prometheus-pushgateway`
- `/etc/genestack/helm-configs/openstack-api-exporter-chart`
- `/etc/genestack/helm-configs/openstack-metrics-exporter`
- `/etc/genestack/kustomize/kube-prometheus-stack/overlay`
- `/etc/genestack/kustomize/loki/overlay`
- `/etc/genestack/kustomize/tempo/overlay`
- `/etc/genestack/kustomize/grafana/overlay`
- `/etc/genestack/kustomize/opentelemetry-kube-stack/overlay`

Generate the shared secrets file before installing Grafana or OpenTelemetry:

```shell
/opt/genestack/bin/create-secrets.sh
```

## Namespace Preparation

Create the monitoring namespace if it does not already exist:

```shell
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
```

!!! info "Talos-only"

    Label the `monitoring` namespace before installing components that need privileged host access.
    Skip this on Kubespray unless your cluster enforces the same restriction.

    ```shell
    kubectl label namespace monitoring \
      pod-security.kubernetes.io/enforce=privileged \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/warn=privileged \
      pod-security.kubernetes.io/warn-version=latest \
      pod-security.kubernetes.io/audit=privileged \
      pod-security.kubernetes.io/audit-version=latest \
      --overwrite
    ```

The monitoring install scripts also apply these labels automatically when the provider is set to `talos`.

## Install kube-prometheus-stack

Prometheus, Alertmanager, node-exporter, and kube-state-metrics are installed first:

```shell
/opt/genestack/bin/install-kube-prometheus-stack.sh
```

Verify the deployment:

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=kube-prometheus-stack
kubectl -n monitoring get servicemonitors
```

Use `/etc/genestack/helm-configs/kube-prometheus-stack/` for service-specific overrides and `/etc/genestack/kustomize/kube-prometheus-stack/overlay/` for post-render patches.

## Choose Loki Storage and Install Loki

The default Loki base values use a single-binary filesystem deployment that is suitable for labs and first-pass validation. If you want object storage, add a service override file in `/etc/genestack/helm-configs/loki/` before installing.

Available examples:

- Generic S3-compatible: `/opt/genestack/base-helm-configs/loki/loki-helm-s3-overrides.yaml.example`
- Rook/Ceph RGW: `/opt/genestack/base-helm-configs/loki/loki-helm-rook-rgw-overrides.yaml.example`
- Swift: `/opt/genestack/base-helm-configs/loki/loki-helm-swift-overrides.yaml.example`
- MinIO: `/opt/genestack/base-helm-configs/loki/loki-helm-minio-overrides.yaml.example`

If you are using Rook/Ceph RGW, the helper below creates the object-store user, buckets, Kubernetes secret, and service override files for Loki and Tempo:

```shell
/opt/genestack/bin/setup-monitoring-rgw-storage.sh
```

The helper uses `mc` (the MinIO Client) to create the buckets. If `mc` is not already on `PATH`, the script downloads a temporary copy automatically. Restricted environments must either allow HTTPS access to `dl.min.io` or install `mc` manually before running the helper.

You can override the defaults with environment variables such as `ROOK_NAMESPACE`, `RGW_STORE_NAME`, `RGW_TOOLBOX_DEPLOYMENT`, and `TARGET_NAMESPACE`.

Install Loki:

```shell
/opt/genestack/bin/install-loki.sh
```

If your cluster DNS service is not named `coredns`, add a Loki override file that sets `global.dnsService` before installing. The Loki gateway uses this value to generate its NGINX resolver configuration.

Verify Loki:

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=loki
kubectl -n monitoring port-forward svc/loki-gateway 3100:80
curl http://127.0.0.1:3100/ready
```

## Choose Tempo Storage and Install Tempo

The default Tempo base values use PVC-backed local storage. For object storage, add a service override file in `/etc/genestack/helm-configs/tempo/` before installing.

Available examples:

- Generic S3-compatible: `/opt/genestack/base-helm-configs/tempo/tempo-helm-s3-overrides.yaml.example`
- Rook/Ceph RGW: `/opt/genestack/base-helm-configs/tempo/tempo-helm-rook-rgw-overrides.yaml.example`

Install Tempo:

```shell
/opt/genestack/bin/install-tempo.sh
```

Verify Tempo:

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=tempo
kubectl -n monitoring port-forward svc/tempo 3200:3200
curl http://127.0.0.1:3200/ready
```

## Install Grafana

Grafana uses `/etc/genestack/helm-configs/grafana/` for service overrides. Set `custom_host` there if you are publishing Grafana through an ingress or gateway.

The Grafana installer ensures the `grafana-db` secret exists in `monitoring`. If you generated `/etc/genestack/kubesecrets.yaml` with `create-secrets.sh`, that secret will be applied automatically.

Install Grafana:

```shell
/opt/genestack/bin/install-grafana.sh
```

Verify Grafana:

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=grafana
kubectl -n monitoring port-forward svc/grafana 3000:80
kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

## Install OpenTelemetry

The OpenTelemetry stack deploys the operator, daemon collector, and deployment collector. The default configuration enables MySQL, PostgreSQL, RabbitMQ, and Memcached telemetry, and includes placeholder `httpcheck` targets you can customize for your environment.

Before installation, the script:

- ensures the `monitoring` namespace exists
- applies Talos namespace labels when appropriate
- creates or applies the `mariadb-monitoring` secret in `openstack`
- creates or applies the `rabbitmq-monitoring-user` secret in `openstack`
- copies `mariadb-monitoring` into `monitoring`
- applies the MariaDB monitoring `User` and `Grant` resources in `openstack`
- applies the RabbitMQ monitoring `User` and `Permission` resources in `openstack`
- copies `rabbitmq-monitoring-user` into `monitoring`

If you keep the default PostgreSQL receiver enabled, make sure the secret
`postgres.postgres-cluster.credentials.postgresql.acid.zalan.do` already exists in the `monitoring`
namespace before installing OpenTelemetry.

Install OpenTelemetry:

```shell
/opt/genestack/bin/install-opentelemetry-kube-stack.sh
```

Verify OpenTelemetry:

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=opentelemetry-kube-stack
kubectl -n monitoring get opentelemetrycollectors
```

## Post-Install Checks

After the full stack is installed, confirm the major paths work:

```shell
kubectl -n monitoring get pods
kubectl -n monitoring get servicemonitors,podmonitors,opentelemetrycollectors
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Use Grafana to confirm that Prometheus, Loki, Tempo, and Alertmanager datasources are healthy. Then verify:

- metrics are being scraped into Prometheus
- logs are queryable in Loki
- traces are queryable in Tempo
- OpenTelemetry collectors are forwarding telemetry successfully

## Component Guides

- [Prometheus](monitoring-prometheus.md)
- [Loki](monitoring-loki.md)
- [Tempo](monitoring-tempo.md)
- [Grafana](monitoring-grafana.md)
- [OpenTelemetry](monitoring-opentelemetry.md)
- [OpenStack Exporter](openstack-exporter.md)
- [Pushgateway](prometheus-pushgateway.md)
