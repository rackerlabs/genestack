# Genestack Observability Alerting and Recording Rules

## Purpose

This document defines how custom Prometheus alerting rules, Prometheus recording rules, and Loki alerting rules are stored and deployed from the `genestack-observability` repository.

The goal is to keep individual rule files as the source of truth and avoid combining them into large generated rule files before deployment.

---

## Repository layout

```text
genestack-observability/
├── alerts/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   │   ├── _helpers.tpl
│   │   └── prometheus-rules.yaml
│   │
│   ├── prometheus-alerts/
│   │   └── <category>/
│   │       └── <alert>.yaml
│   │
│   ├── recording/
│   │   └── <category>/
│   │       └── <recording-rule>.yaml
│   │
│   └── loki-alerts/
│       └── <category>/
│           └── <alert>.yaml
│
├── bin/
│   ├── install-prometheus-rules.sh
│   ├── install-lokitool.sh
│   └── loki-sync-rules.sh
│
└── versions/
    └── lokitool
```

---

# Prometheus rules

Prometheus alerting and recording rules are deployed as native `PrometheusRule` Kubernetes resources.

They are managed separately from the `kube-prometheus-stack` Helm release.

This removes the previous workflow:

```text
individual rule files
    -> combine
    -> alerting_rules.yaml
    -> additionalPrometheusRulesMap
    -> kube-prometheus-stack Helm release
```

The new workflow is:

```text
alerts/prometheus-alerts/**/*.yaml
alerts/recording/**/*.yaml
        |
        v
genestack-prometheus-rules Helm chart
        |
        v
PrometheusRule CRDs
        |
        v
Prometheus Operator
        |
        v
Prometheus
```

## Existing source format

Version one intentionally keeps the existing Genestack rule format unchanged.

Example alert:

```yaml
additionalPrometheusRulesMap:
  node-cpu-high-usage:
    groups:
      - name: node-cpu-high-usage
        rules:
          - alert: node-cpu-high-usage-warning
            expr: |
              100 * (
                1 -
                avg by(instance, k8s_node_name) (
                  rate(node_cpu_seconds_total{
                    job="node-exporter",
                    mode="idle"
                  }[5m])
                )
              ) > 90
            for: 5m
            labels:
              severity: warning
              group_name: node-cpu-high-usage
              node_hostname: '{{ $labels.k8s_node_name }}'
            annotations:
              summary: High CPU usage.
```

Example recording rule:

```yaml
additionalPrometheusRulesMap:
  instance-devicenode-disk-io-time-secondsrate5m:
    groups:
      - name: node-exporter-rules
        rules:
          - expr: |
              rate(
                node_disk_io_time_seconds_total{
                  job="node-exporter",
                  device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"
                }[5m]
              )
            record: instance_device:node_disk_io_time_seconds:rate5m
```

Both are converted into `PrometheusRule` resources by the rules Helm chart.

## Rules Helm chart

The Helm chart lives at:

```text
/opt/genestack-observability/alerts
```

and owns both:

```text
alerts/prometheus-alerts/
alerts/recording/
```

Suggested chart identity:

```yaml
apiVersion: v2
name: genestack-prometheus-rules
description: Genestack Prometheus alerting and recording rules
type: application
version: 0.1.0
```

The rules release should use:

```text
Helm release: prometheus-rules
Namespace: monitoring
```

## Rule selection

The generated `PrometheusRule` resources should initially retain the label expected by the existing `kube-prometheus-stack` Prometheus selector:

```yaml
metadata:
  labels:
    release: kube-prometheus-stack
```

Additional labels should distinguish Genestack-managed rule resources:

```yaml
app.kubernetes.io/name: genestack-prometheus-rules
app.kubernetes.io/instance: prometheus-rules
genestack.io/rule-type: alerting
```

or:

```yaml
genestack.io/rule-type: recording
```

## Collision-safe resource names

Prometheus rule map keys can collide across files.

Generated Kubernetes resource names must therefore be deterministic and collision-safe.

Use:

```text
rule type + rule key + deterministic hash(source path + rule key + rule type)
```

For example:

```text
alert-node-health-a13d21c54e
record-node-health-e94110a327
```

This allows duplicate map keys in separate files without creating conflicting `PrometheusRule` object names.

## Install script

Rules should be installed independently of `kube-prometheus-stack`:

```bash
GENESTACK_OBSERVABILITY_DIR="${GENESTACK_OBSERVABILITY_DIR:-/opt/genestack-observability}"

helm upgrade --install prometheus-rules \
  "${GENESTACK_OBSERVABILITY_DIR}/alerts" \
  --namespace monitoring \
  --create-namespace \
  --wait
```

The `kube-prometheus-stack` installer should no longer:

- combine rule files;
- load a generated `alerting_rules.yaml`;
- append generated rule files with additional `-f` arguments;
- own custom Genestack alerting or recording rules.

---

# Loki rules

Loki alert rules are managed differently from Prometheus rules.

They are stored directly in Loki's native ruler file format and synchronized to the Loki Ruler API with `lokitool`.

No Helm chart, ConfigMap, merge file, staging directory, or prepare step is required.

The workflow is:

```text
alerts/loki-alerts/**/*.yaml
        |
        v
loki-sync-rules.sh
        |
        v
Loki Gateway / Ruler API
        |
        v
Loki Ruler
        |
        v
Swift ruler storage
```

## Loki source format

Each Loki rule file must contain an explicit namespace.

Example:

```yaml
namespace: genestack-octavia-health-manager

groups:
  - name: octavia-health-manager-alerts
    interval: 1m
    rules:
      - alert: OctaviaHealthManagerStaleAmphoraDetected
        expr: |
          sum by (cluster, host) (
            count_over_time(
              {container=~"octavia-health-manager"}
              |= "Stale amphora's id is:"
              [5m]
            )
          ) > 0
        for: 2m
        labels:
          severity: warning
          service: octavia
          component: health-manager
        annotations:
          summary: Octavia stale amphora detected
```

## Loki namespace convention

Every file must have a unique Loki ruler namespace:

```text
genestack-<logical-name>
```

Examples:

```text
genestack-octavia-health-manager
genestack-neutron-errors
genestack-nova-compute-errors
```

This namespace is a Loki Ruler namespace. It is unrelated to the Kubernetes namespace `monitoring`.

The `genestack-` prefix defines ownership so synchronization can safely be limited to rules managed by this repository.

## Loki tenant

For single-tenant Loki:

```bash
LOKI_TENANT_ID="${LOKI_TENANT_ID:-fake}"
```

## Loki endpoint discovery

The sync script should not contain a regional Loki hostname.

It discovers the regional hostname from:

```text
HTTPRoute:
  namespace: monitoring
  name: internal-loki-gateway-route
```

Example route:

```yaml
kind: HTTPRoute
metadata:
  name: internal-loki-gateway-route
  namespace: monitoring
spec:
  hostnames:
    - loki-gateway.dev.dfw.ohthree.com
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: flex-rax-gateway
      namespace: rackspace
      sectionName: loki-http
```

The sync script also inspects the referenced Gateway listener to determine whether the discovered endpoint should use HTTP or HTTPS.

This avoids:

- regional configuration in the repository;
- depending on the Loki NodePort;
- `kubectl port-forward`;
- direct access to Kubernetes Service IPs.

An explicitly supplied `LOKI_ADDRESS` should override discovery.

## Loki synchronization ownership

Synchronization must be constrained to:

```bash
LOKI_NAMESPACES_REGEX="${LOKI_NAMESPACES_REGEX:-^genestack-}"
```

Example:

```bash
lokitool rules diff \
  --rule-dirs="${LOKI_RULE_DIR}" \
  --namespaces-regex="${LOKI_NAMESPACES_REGEX}" \
  --verbose

lokitool rules sync \
  --rule-dirs="${LOKI_RULE_DIR}" \
  --namespaces-regex="${LOKI_NAMESPACES_REGEX}"
```

Do not run an unrestricted sync against a Ruler containing namespaces managed outside this repository.

## lokitool

`lokitool` is a standalone administrative binary and does not require Loki to be installed on the overseer.

Pin its version in:

```text
versions/lokitool
```

For Loki 3.6.4:

```text
3.6.4
```

The overseer-side install tooling should install only the `lokitool` binary into a standard executable path such as:

```text
/usr/local/bin/lokitool
```

It should remain independent of `install-loki.sh`.

## Loki ruler requirements

The deployed Loki environment must provide:

- Ruler enabled;
- Ruler API enabled;
- Alertmanager URL configured;
- object-backed ruler storage;
- Swift ruler storage retained in the current Genestack deployment;
- Loki Gateway route capable of reaching `/loki/api/v1/rules`.

Do not switch ruler storage to local filesystem storage for this workflow.

---

# Recommended deployment order

```text
1. install/update kube-prometheus-stack
2. install/update Prometheus alerting + recording rules
3. install/update Loki
4. synchronize Loki ruler rules
```

This can eventually be orchestrated by a higher-level observability deployment script while retaining the individual scripts for troubleshooting and targeted updates.

---

# Future cleanup

After the initial migration is stable, Prometheus source rules can optionally be converted from:

```yaml
additionalPrometheusRulesMap:
  some-rule:
    groups:
```

to native rule files:

```yaml
groups:
```

This is not required for version one and should be treated as a separate cleanup from the deployment migration.
