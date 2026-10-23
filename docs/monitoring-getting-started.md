# Getting Started with Genestack Monitoring

This guide covers the standard workflow for bootstrapping and installing Genestack's observability stack.

The stack includes Prometheus for metrics and alerting, Loki for logs, Tempo for traces, Grafana for dashboards, OpenTelemetry for collection, and optional exporters and Pushgateway. The unified installer installs the components enabled in its component configuration.

For component-specific configuration, see the guides linked at the end of this page.

## Prerequisites

Before starting, make sure:

- Genestack host bootstrap is complete and `kubectl` points at the target cluster.
- `helm`, `git`, and `yq` v4 are installed and available on the bootstrap host.
- `/opt/genestack` and the `/etc/genestack` site override repository are present.
- Your site-specific Helm overrides, credentials, and storage settings are ready before installing the components that need them.

The observability repository is cloned to `/opt/genestack-observability` by default. Its default URL is `https://github.com/rackerlabs/genestack-observability.git`.

## Configure site overrides before installing

Keep site-specific configuration in `/etc/genestack`; canonical component configuration lives in `genestack-observability`.

The observability paths are:

- Helm overrides: `/etc/genestack/helm-configs/observability/<component>/`
- Kustomize overlay: `/etc/genestack/kustomize/observability/<component>/overlay/`
- Canonical Helm configuration: `/opt/genestack-observability/helm-configs/<component>/`
- Canonical Kustomize base: `/opt/genestack-observability/kustomize/<component>/base/`

The bootstrap creates or updates these consolidated links:

- `/opt/genestack/base-helm-configs/observability` → `/opt/genestack-observability/helm-configs`
- `/opt/genestack/base-kustomize/observability` → `/opt/genestack-observability/kustomize`

In normal mode, bootstrap does not copy Helm component configuration into `/etc/genestack` or create missing site service directories and overlays. The site override repository should already contain the component directories and overlays your deployment needs. Bootstrap reconciles each existing service's `base` link to the canonical base in `/opt/genestack-observability`. **Kustomize bases are never copied into `/etc/genestack`; they are symlinks in both normal and lab mode.**

Before installation, review the component defaults and create the necessary site overrides. For example, the default Loki configuration is a single-binary, filesystem-backed setup suitable for labs and initial validation. For object storage, start from one of the examples under `/opt/genestack-observability/helm-configs/loki/` and put the required site-specific values in `/etc/genestack/helm-configs/observability/loki/`.

If you want bootstrap to prepare a fresh, disposable lab, use `--lab-only`. This mode seeds missing Helm component configs and creates missing Kustomize service directories and overlays. It still links Kustomize bases; it never copies them. Existing site configurations are preserved rather than overwritten.

## Bootstrap and install

Run the following on the Genestack control/overseer host:

```shell
/opt/genestack/bin/bootstrap-observability.sh
```

By default, the bootstrap:

1. Clones `genestack-observability` if it is not present, or fast-forward updates the existing checkout.
2. Creates or repairs the consolidated Helm and Kustomize symlinks under `/opt/genestack`.
3. Cleans up eligible stale component directories left behind in the Genestack checkout and migrates legacy Kustomize base links under `/etc/genestack`.
4. Prepares observability Gateway API routes when route management is enabled.
5. Runs the unified installer, which installs components enabled in the component configuration.

The default component configuration is `/opt/genestack-observability/bin/observability-components.yaml`. If `/etc/genestack/observability-components.yaml` exists, it takes precedence. Review that file to see which components are enabled and their install order.

Useful bootstrap options:

```shell
# Configure links/routes but do not install components yet
/opt/genestack/bin/bootstrap-observability.sh --no-install

# Skip updating an existing observability checkout
/opt/genestack/bin/bootstrap-observability.sh --no-update

# Skip Gateway API route seeding/application
/opt/genestack/bin/bootstrap-observability.sh --no-routes

# Seed missing service configs/overlays for a disposable lab only
/opt/genestack/bin/bootstrap-observability.sh --lab-only

# Override the clone URL for a new checkout
/opt/genestack/bin/bootstrap-observability.sh --repo https://github.com/rackerlabs/genestack-observability.git
```

You can also set `GENESTACK_OBSERVABILITY_REPO` to override the clone URL. When the checkout already exists, bootstrap updates its configured Git remote; changing the clone URL does not automatically replace that remote.

## Install or rerun individual components

The unified installer reads the enabled components and install order from the component configuration:

```shell
# Show configured components and whether each is enabled
/opt/genestack/bin/install-observability.sh --list

# Install all enabled components
/opt/genestack/bin/install-observability.sh

# Install selected components only
/opt/genestack/bin/install-observability.sh loki grafana
```

The bootstrap prefers `/opt/genestack/bin/install-observability.sh`. It uses `/opt/genestack-observability/bin/install-observability.sh` only if the Genestack copy is absent. A component requested explicitly is run even if it is marked disabled in the component configuration.

Loki rule synchronization is best-effort in the unified installer: if the Ruler endpoint or rule store is unavailable, it logs a warning and continues with the remaining components. Ensure your Loki rule-storage configuration supports the rule-management method you intend to use.

## Verify the installation

Check pods and monitoring resources:

```shell
kubectl -n monitoring get pods
kubectl -n monitoring get servicemonitors,podmonitors,opentelemetrycollectors
```

Check Prometheus readiness:

```shell
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

In another terminal, open `http://127.0.0.1:9090/-/ready`.

Check Loki readiness:

```shell
kubectl -n monitoring port-forward svc/loki-gateway 3100:80
```

In another terminal, run `curl http://127.0.0.1:3100/ready`.

Check Tempo readiness:

```shell
kubectl -n monitoring port-forward svc/tempo 3200:3200
```

In another terminal, run `curl http://127.0.0.1:3200/ready`.

For Grafana, verify the pods are ready and confirm that the Prometheus, Loki, Tempo, and Alertmanager data sources are healthy in the UI. Finally, confirm that metrics are being scraped, logs are queryable, traces are available if Tempo is enabled, and OpenTelemetry collectors are forwarding telemetry.

## Component guides

- [Prometheus](monitoring-prometheus.md)
- [Loki](monitoring-loki.md)
- [Tempo](monitoring-tempo.md)
- [Grafana](monitoring-grafana.md)
- [OpenTelemetry](monitoring-opentelemetry.md)
- [OpenStack Exporter](openstack-exporter.md)
- [Pushgateway](prometheus-pushgateway.md)

