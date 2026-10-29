# Deploy Genestack Observability on an Overseer

## Overview

`genestack-observability` contains the monitoring-specific Helm configuration,
Kustomize configuration, alerting and recording rules, and the service
installation implementations used by Genestack observability deployments.

The repository is installed on a Genestack overseer at:

```text
/opt/genestack-observability
```

The primary Genestack checkout remains at:

```text
/opt/genestack
```

The design intentionally separates **orchestration** from **service
implementation**:

```text
Genestack
  /opt/genestack/bin/
    bootstrap-observability.sh
    install-observability.sh
    loki-sync-rules.sh
        |
        | orchestrates
        v
genestack-observability
  /opt/genestack-observability/bin/
    install-kube-prometheus-stack.sh
    install-prometheus-pushgateway.sh
    install-barbican-exporter.sh
    install-openstack-exporter.sh
    install-opentelemetry-kube-stack.sh
    install-tempo.sh
    install-loki.sh
    install-grafana.sh
    install-prometheus-rules.sh
    install-lokitool.sh
    setup-monitoring-rgw-storage.sh
```

`install-observability.sh` and `loki-sync-rules.sh` may be shipped in both
repositories so operators have stable entrypoints from Genestack while the
observability repository remains independently usable.

The actual service installers remain owned by `genestack-observability`.

## Prerequisites

The overseer is expected to already have a working Genestack environment,
including:

```text
/opt/genestack
/opt/genestack/base-helm-configs
/opt/genestack/base-kustomize
/etc/genestack
```

The normal Genestack administrative tooling such as `kubectl`, `helm`, `yq`,
`jq`, `curl`, and Git should already be available.

The account performing the bootstrap must be able to clone:

```text
git@github.com:rackerlabs/genestack-observability.git
```

## Repository layout

The relevant observability layout is:

```text
/opt/genestack-observability/
├── alerts/
│   ├── prometheus-alerts/
│   ├── recording/
│   └── loki-alerts/
├── bin/
│   ├── bootstrap-observability.sh
│   ├── install-observability.sh
│   ├── install-barbican-exporter.sh
│   ├── install-grafana.sh
│   ├── install-kube-prometheus-stack.sh
│   ├── install-loki.sh
│   ├── install-lokitool.sh
│   ├── install-openstack-exporter.sh
│   ├── install-opentelemetry-kube-stack.sh
│   ├── install-prometheus-pushgateway.sh
│   ├── install-prometheus-rules.sh
│   ├── install-tempo.sh
│   ├── loki-sync-rules.sh
│   ├── monitoring-common.sh
│   ├── observability-components.yaml
│   ├── setup-monitoring-rgw-storage.sh
│   └── yamlparse.py
├── helm-configs/
├── kustomize/
└── versions/
    └── lokitool
```

The following are orchestration or support files, not observability services:

```text
bootstrap-observability.sh
install-observability.sh
install-lokitool.sh
loki-sync-rules.sh
monitoring-common.sh
yamlparse.py
observability-components.yaml
```

`setup-monitoring-rgw-storage.sh` is modeled as an installable prerequisite
operation named `monitoring-rgw-storage`.

All scripts should use:

```bash
GENESTACK_OBSERVABILITY_DIR="${GENESTACK_OBSERVABILITY_DIR:-/opt/genestack-observability}"
```

and must not depend on the caller changing directories first.

## Genestack integration

The observability Helm configuration is linked into:

```text
/opt/genestack/base-helm-configs/observability
```

The observability Kustomize configuration is linked into:

```text
/opt/genestack/base-kustomize/observability
```

The resulting paths are:

```text
/opt/genestack/base-helm-configs/observability
  -> /opt/genestack-observability/helm-configs

/opt/genestack/base-kustomize/observability
  -> /opt/genestack-observability/kustomize
```

The bootstrap script refuses to replace an existing non-symlink path at either
target.


## Secret handling

Monitoring-specific secrets are created and reconciled by the service installers and the shared `monitoring-common.sh` helpers.

For example, the Grafana installer ensures `grafana-db`, the OpenTelemetry installer ensures the monitoring database and messaging credentials it consumes, and the OpenStack exporter workflow ensures its Keystone authentication secret.


## Component enablement

Observability component selection follows the same style as Genestack's
component configuration: each component is enabled or disabled with a boolean.

The repository default lives at:

```text
/opt/genestack-observability/bin/observability-components.yaml
```

The site configuration lives at:

```text
/etc/genestack/observability-components.yaml
```

The default component set is:

```yaml
---
components:
  monitoring-rgw-storage: true
  kube-prometheus-stack: true
  prometheus-pushgateway: true
  barbican-exporter: true
  openstack-exporter: true
  openstack-metrics-exporter: true
  tempo: true
  loki: true
  opentelemetry-kube-stack: true
  grafana: true
  prometheus-rules: true
  loki-rules: true

install_order:
  - monitoring-rgw-storage
  - kube-prometheus-stack
  - prometheus-pushgateway
  - barbican-exporter
  - openstack-exporter
  - openstack-metrics-exporter
  - tempo
  - loki
  - opentelemetry-kube-stack
  - grafana
  - prometheus-rules
  - loki-rules
```

The explicit install order is intentional. It avoids depending on YAML map
ordering and gives initial deployments a deterministic dependency sequence.

For example, a cluster that should run Prometheus without Loki can use:

```yaml
---
components:
  monitoring-rgw-storage: false
  kube-prometheus-stack: true
  prometheus-pushgateway: true
  barbican-exporter: true
  openstack-exporter: true
  openstack-metrics-exporter: true
  tempo: false
  loki: false
  opentelemetry-kube-stack: true
  grafana: true
  prometheus-rules: true
  loki-rules: false

install_order:
  - monitoring-rgw-storage
  - kube-prometheus-stack
  - prometheus-pushgateway
  - barbican-exporter
  - openstack-exporter
  - openstack-metrics-exporter
  - tempo
  - loki
  - opentelemetry-kube-stack
  - grafana
  - prometheus-rules
  - loki-rules
```

## Component-to-script mapping

The unified installer maps components to implementations in
`genestack-observability`:

| Component | Implementation |
|---|---|
| `monitoring-rgw-storage` | `bin/setup-monitoring-rgw-storage.sh` |
| `kube-prometheus-stack` | `bin/install-kube-prometheus-stack.sh` |
| `prometheus-pushgateway` | `bin/install-prometheus-pushgateway.sh` |
| `barbican-exporter` | `bin/install-barbican-exporter.sh` |
| `openstack-exporter` | `bin/install-openstack-exporter.sh` |
| `openstack-metrics-exporter` | `bin/install-openstack-metrics-exporter.sh` |
| `tempo` | `bin/install-tempo.sh` |
| `loki` | `bin/install-loki.sh` |
| `opentelemetry-kube-stack` | `bin/install-opentelemetry-kube-stack.sh` |
| `grafana` | `bin/install-grafana.sh` |
| `prometheus-rules` | `bin/install-prometheus-rules.sh` |
| `loki-rules` | `bin/loki-sync-rules.sh` |

`install-lokitool.sh` is a dependency installer and is not represented as a
service component.

## Bootstrap

When `bootstrap-observability.sh` is shipped with Genestack, the canonical
first-run command is:

```bash
/opt/genestack/bin/bootstrap-observability.sh
```

The bootstrap:

1. verifies the expected Genestack paths;
2. clones or updates `genestack-observability`;
3. initializes, synchronizes, and updates repository submodules;
4. creates the Helm and Kustomize symlinks;
5. seeds `/etc/genestack/observability-components.yaml` on first bootstrap;
6. invokes the unified observability installer.

The clone URL is:

```text
git@github.com:rackerlabs/genestack-observability.git
```

The repository uses Git submodules. Bootstrap clones recursively with parallel
submodule checkout:

```bash
git clone \
  --recurse-submodules \
  -j4 \
  git@github.com:rackerlabs/genestack-observability.git \
  /opt/genestack-observability
```

For an existing checkout, bootstrap performs:

```bash
git -C /opt/genestack-observability pull --ff-only

git -C /opt/genestack-observability submodule sync --recursive

git -C /opt/genestack-observability submodule update \
  --init \
  --recursive \
  -j4
```

`submodule sync --recursive` keeps local submodule URLs aligned with `.gitmodules`
before the recursive update.

If the observability repository has already been cloned, the same bootstrap
implementation can also be invoked from:

```bash
/opt/genestack-observability/bin/bootstrap-observability.sh
```

To configure without installing services:

```bash
/opt/genestack/bin/bootstrap-observability.sh --no-install
```

To avoid pulling updates to an existing observability checkout:

```bash
/opt/genestack/bin/bootstrap-observability.sh --no-update
```

## Unified installation

The canonical Genestack entrypoint is:

```bash
/opt/genestack/bin/install-observability.sh
```

The equivalent observability-repository entrypoint is:

```bash
/opt/genestack-observability/bin/install-observability.sh
```

Both copies should use the same implementation.

With no component arguments, the installer installs all components enabled in
`observability-components.yaml` using the configured `install_order`:

```bash
/opt/genestack/bin/install-observability.sh
```

Individual components can also be installed explicitly by name:

```bash
/opt/genestack/bin/install-observability.sh loki
```

Multiple components can be requested in one invocation and are installed in
the order supplied:

```bash
/opt/genestack/bin/install-observability.sh   kube-prometheus-stack   prometheus-rules
```

Other examples:

```bash
/opt/genestack/bin/install-observability.sh grafana

/opt/genestack/bin/install-observability.sh   tempo   loki   loki-rules
```

An explicitly named component is installed even if its boolean value is
`false` in the component configuration. This makes targeted repair, testing,
and upgrade operations possible without temporarily editing the site
configuration.

List known components and their configured enabled state with:

```bash
/opt/genestack/bin/install-observability.sh --list
```

Display usage information with:

```bash
/opt/genestack/bin/install-observability.sh --help
```

Regardless of which copy is executed, **all actual service installers are
resolved from**:

```text
/opt/genestack-observability/bin
```

For example, running:

```bash
/opt/genestack/bin/install-observability.sh
```

still invokes:

```text
/opt/genestack-observability/bin/install-loki.sh
/opt/genestack-observability/bin/install-grafana.sh
/opt/genestack-observability/bin/install-tempo.sh
...
```

This preserves a clean ownership boundary between the projects.

The unified installer reads component configuration in this order:

1. `OBSERVABILITY_COMPONENTS_FILE`, when explicitly set;
2. `/etc/genestack/observability-components.yaml`;
3. `/opt/genestack-observability/bin/observability-components.yaml`.

A temporary component configuration can therefore be tested with:

```bash
OBSERVABILITY_COMPONENTS_FILE=/tmp/observability-components.yaml \
  /opt/genestack/bin/install-observability.sh
```

## lokitool

Loki rule synchronization requires the standalone `lokitool` client on the
overseer.

It is not an enabled service and Loki itself does not run on the overseer.

The desired version is pinned at:

```text
/opt/genestack-observability/versions/lokitool
```

For example:

```text
3.6.4
```

When `loki-rules` is enabled, `install-observability.sh` checks for
`lokitool`. If it is absent, it invokes:

```text
/opt/genestack-observability/bin/install-lokitool.sh
```

before synchronizing rules.

## Prometheus rules

Prometheus alerting rules live at:

```text
/opt/genestack-observability/alerts/prometheus-alerts
```

Recording rules live at:

```text
/opt/genestack-observability/alerts/recording
```

Both are deployed by:

```text
/opt/genestack-observability/bin/install-prometheus-rules.sh
```

as native `PrometheusRule` resources.

The previous generated `alerting_rules.yaml` workflow is not required by the
new deployment model.

## Loki rules

Loki rules live at:

```text
/opt/genestack-observability/alerts/loki-alerts
```

Each file contains an explicit ruler namespace:

```yaml
namespace: genestack-octavia-health-manager

groups:
  - name: octavia-health-manager-alerts
    rules:
      ...
```

The shared orchestration script is:

```text
loki-sync-rules.sh
```

It may be shipped in both:

```text
/opt/genestack/bin/loki-sync-rules.sh
/opt/genestack-observability/bin/loki-sync-rules.sh
```

The rule source remains owned by the observability repository.

The script discovers the regional Loki address from:

```text
monitoring/internal-loki-gateway-route
```

and limits Ruler reconciliation to namespaces matching:

```text
^genestack-
```

No regional hostname, Service IP, NodePort, or port-forward needs to be
hardcoded into Genestack.

## Updating observability

After the initial bootstrap:

```bash
git -C /opt/genestack-observability pull --ff-only

git -C /opt/genestack-observability submodule sync --recursive

git -C /opt/genestack-observability submodule update \
  --init \
  --recursive \
  -j4
```

Review the site configuration:

```bash
cat /etc/genestack/observability-components.yaml
```

Then reconcile all enabled services:

```bash
/opt/genestack/bin/install-observability.sh
```

Individual observability implementations can still be invoked directly when
needed:

```bash
/opt/genestack-observability/bin/install-loki.sh
/opt/genestack-observability/bin/install-grafana.sh
/opt/genestack-observability/bin/install-opentelemetry-kube-stack.sh
```

## Verification

Verify repository integration:

```bash
readlink -f /opt/genestack/base-helm-configs/observability
readlink -f /opt/genestack/base-kustomize/observability
```

Expected:

```text
/opt/genestack-observability/helm-configs
/opt/genestack-observability/kustomize
```

Review enabled components:

```bash
yq eval '.components' /etc/genestack/observability-components.yaml
```

Review monitoring Helm releases:

```bash
helm list -n monitoring
```

Verify custom Prometheus rules:

```bash
kubectl -n monitoring get prometheusrules \
  -l app.kubernetes.io/name=genestack-prometheus-rules
```

Verify Loki rule tooling when `loki-rules` is enabled:

```bash
lokitool --version
```

## Ownership summary

```text
Genestack
  Shared operator-facing orchestration entrypoints.

genestack-observability
  Actual service installers.
  Helm configuration.
  Kustomize configuration.
  Prometheus alerting rules.
  Prometheus recording rules.
  Loki rules.
  Pinned tool versions.

/etc/genestack
  Site-specific enabled-component configuration.

/opt/genestack/base-helm-configs/observability
/opt/genestack/base-kustomize/observability
  Stable integration paths into genestack-observability.
```

