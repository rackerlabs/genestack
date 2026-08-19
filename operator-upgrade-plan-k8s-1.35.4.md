# Operator Upgrade Plan for Kubernetes 1.35.4

## Overview

This plan covers upgrading all Helm-managed operators/charts from their current versions (release-2026.1.0 baseline) to current supported versions under Kubernetes 1.35.4 with kubespray v2.31.0.

## Key Decisions

- **Upgrade approach**: Full upgrade to latest supported versions (not conservative)
- **High-risk charts**: Direct to latest (no staging/intermediate versions)
- **OpenStack service charts**: No changes (out of scope per user decision)
- **CI validation**: All changes validated via `helm template` in CI before merge

## Kubernetes Context

- **Base Kubernetes**: 1.35.4 (pinned in `ansible/inventory/genestack/group_vars/k8s_cluster/k8s-cluster.yml:20`)
- **Kubespray**: v2.31.0 (submodules/kubespray)
- **CAPI template**: `ansible/roles/capi_cluster/templates/capi-cluster-vars.yml.j2` currently has `kube_version: 1.35.1` — should be updated to `1.35.4`

## Charts to Upgrade

### 16 Charts to Upgrade (3 No-Change)

| Chart | Current | Target | Chart Major Bump? | Risk |
|---|---|---|---|---|
| **kube-ovn** | v1.15.4 | v1.16.2 | Yes (1.15→1.16) | **High** |
| **cert-manager** | v1.19.5 | v1.20.3 | Yes (1.19→1.20) | Medium |
| **envoyproxy-gateway** | v1.7.0 | v1.9.0 | Yes (1.7→1.9) | Medium |
| **metallb** | v0.15.2 | v0.16.1 | Yes (0.15→0.16) | Medium |
| **longhorn** | 1.11.1 | 1.11.3 | No (patch) | Low |
| **grafana** | 10.1.0 | 10.5.15 | App: 11→12 | Medium |
| **kube-prometheus-stack** | 78.3.0 | 88.5.0 | Yes (78→88) | **High** |
| **loki** | 6.52.0 | 7.3.0 | Yes (6→7) | **High** |
| **prometheus-pushgateway** | 3.4.2 | 3.8.0 | No (minor) | Low |
| **mariadb-operator** | 26.3.0 | 26.6.0 | No (minor) | Low |
| **postgres-operator** | 1.15.1 | 2.0.1 | Yes (1→2) | **High** |
| **redis-operator** | 0.24.0 | 0.25.0 | No (minor) | Low |
| **redis-sentinel** | 0.16.12 | 0.16.13 | No (patch) | Low |
| **sealed-secrets** | 2.17.4 | 2.5.19 | Version scheme change | Medium |
| **topolvm** | 16.1.1 | 17.1.0 | Yes (16→17) | Medium |
| **opentelemetry-kube-stack** | 0.13.1 | 0.20.2 | Yes (0.13→0.20) | **High** |
| **redis-replication** | 0.17.0 | 0.17.0 | No | No change |
| **tempo** | 1.24.4 | 1.24.4 | No | No change |

---

## Upgrade Execution Order

### Phase 1: Infrastructure Core (CNI, LB, Storage, TLS)
1. **kube-ovn** (v1.15.4 → v1.16.2) — CNI foundation. Update image tag in overrides.
2. **metallb** (v0.15.2 → v0.16.1) — Load balancer. New IPAttached CRD.
3. **longhorn** (1.11.1 → 1.11.3) — Storage, safe patch.
4. **cert-manager** (v1.19.5 → v1.20.3) — TLS certificates. Uses existing cmctl upgrade gate.

### Phase 2: Databases
5. **mariadb-operator** (26.3.0 → 26.6.0) — Follow existing 26.x pattern from `maintenance-mariadb-operator-galera-25.10.4-to-26.3.0.txt`
6. **postgres-operator** (1.15.1 → 2.0.1) — **Highest risk**. Follow upstream `docs/migrate.md`. CRD field renames + ConfigMap HA migration.
7. **redis-operator** (0.24.0 → 0.25.0) + **redis-sentinel** (0.16.12 → 0.16.13)

### Phase 3: Observability Stack
8. **kube-prometheus-stack** (78.3.0 → 88.5.0) — Prometheus CRD v1→v2 migration. Clear/update image tags in overrides.
9. **loki** (6.52.0 → 7.3.0) — Major chart version (6→7).
10. **opentelemetry-kube-stack** (0.13.1 → 0.20.2) — 7-version jump. Collector config and CRD changes.
11. **grafana** (10.1.0 → 10.5.15) — App version 11→12. Update image tag in overrides.
12. **prometheus-pushgateway** (3.4.2 → 3.8.0) — Minor bumps within 3.x.

### Phase 4: Secrets Management
13. **sealed-secrets** (2.17.4 → 2.5.19) — Version scheme change. Verify existing SealedSecrets still decrypt.

### Phase 5: Storage (if applicable)
14. **topolvm** (16.1.1 → 17.1.0) — Major chart version. App version → v0.41.0.

---

## Files to Modify

### Primary (1 file)
1. **`helm-chart-versions.yaml`** — Update all 16 chart version values

### Override Files (5 files)
2. **`base-helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml`** — `line 12`: `tag: v1.15.4` → `tag: v1.16.2`
3. **`base-helm-configs/grafana/grafana-helm-overrides.yaml`** — `line 22`: `tag: "12.2.0"` → `tag: "12.3.1"` (or clear to use chart default)
4. **`base-helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml`** — `line 3`: `x-chart-version: "26.3.0"` → `x-chart-version: "26.6.0"`
5. **`base-helm-configs/kube-prometheus-stack/kube-prometheus-stack-helm-overrides.yaml`** — Update image tags for prometheus (v0.34.0→), alertmanager (v2.49.1→), operator (v0.26.0→) or clear to use chart defaults
6. **`base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-overrides.yaml`** — `line 11`: `tag: v1.34.1` → `tag: v1.35.0` (cleanupJob kubectl image)

### CAPI Template (1 file)
7. **`ansible/roles/capi_cluster/templates/capi-cluster-vars.yml.j2`** — `kube_version: 1.35.1` → `kube_version: 1.35.4`

### CI Workflow Files (6 new, 1 already exists for redis-sentinel)
New workflows following the existing `helm-cert-manager.yaml` pattern:
- `.github/workflows/helm-grafana.yaml`
- `.github/workflows/helm-envoy-gateway.yaml`
- `.github/workflows/helm-longhorn.yaml`
- `.github/workflows/helm-metallb.yaml`
- `.github/workflows/helm-postgres-operator.yaml`
- `.github/workflows/helm-redis-operator.yaml`
- `.github/workflows/helm-sealed-secrets.yaml`

### Maintenance Runbooks (14 new)
All in `maintenances/` directory, following `maintenance-component-template.txt` format:
1. `maintenance-kube-ovn-v1.15.4-to-v1.16.2.txt`
2. `maintenance-metallb-v0.15.2-to-v0.16.1.txt`
3. `maintenance-cert-manager-v1.19.5-to-v1.20.3.txt`
4. `maintenance-envoyproxy-gateway-v1.7.0-to-v1.9.0.txt`
5. `maintenance-kube-prometheus-stack-78.3.0-to-88.5.0.txt`
6. `maintenance-loki-6.52.0-to-7.3.0.txt`
7. `maintenance-opentelemetry-kube-stack-0.13.1-to-0.20.2.txt`
8. `maintenance-grafana-10.1.0-to-10.5.15.txt`
9. `maintenance-postgres-operator-1.15.1-to-2.0.1.txt`
10. `maintenance-mariadb-operator-26.3.0-to-26.6.0.txt`
11. `maintenance-redis-operator-0.24.0-to-0.25.0.txt`
12. `maintenance-redis-sentinel-0.16.12-to-0.16.13.txt`
13. `maintenance-sealed-secrets-2.17.4-to-2.5.19.txt`
14. `maintenance-topolvm-16.1.1-to-17.1.0.txt`

### Documentation Updates
15. `docs/product-matrix-2026.2.0.md` — regenerate from new helm-chart-versions.yaml
16. `docs/release-2026.2.0.md` — add chart upgrade notes

---

## High-Risk Upgrade Details

### postgres-operator (1.15.1 → 2.0.1) — MOST RISKY

**Changes requiring migration steps** (from upstream `docs/migrate.md`):
1. **CRD field renames** — find and fix all PostgreSQL manifests:
   - `init_containers` → `initContainers`
   - `pod_priority_class_name` → `podPriorityClassName`
   - `replicaLoadBalancer` → `enableReplicaLoadBalancer`
   - `useLoadBalancer` → `enableMasterLoadBalancer`
2. **Password encryption** — defaults from `md5` to `scram-sha-256`; verify client driver compatibility
3. **K8s Endpoints deprecation** — must switch to ConfigMap-based HA:
   - Set `kubernetes_use_configmaps: true` in PostgreSQL manifests
   - Scale to single primary before migration (avoid split-brain)
   - Delete orphaned endpoints after migration
4. **Default Spilo image** changes to `spilo-18:4.1-p2` (from spilo-17)
5. **Must NOT delete CRDs** during operator uninstall (would delete clusters)

**Runbook key steps** (from existing mariadb-operator maintenance pattern):
- Scale down operator + remove webhooks before uninstall
- Uninstall old, install new, reapply cluster manifest
- Verify `pointintimerecoveries.k8s.mariadb.com` CRD exists
- Rollback: revert version, keep CRDs in place

### kube-prometheus-stack (78.3.0 → 88.5.0) — HIGH RISK

**Changes requiring migration steps**:
1. **Prometheus CRD migration** — Operator v0.93.x uses CRD v2 stored versions
2. **App version jump** — Prometheus 2.x → 3.x (check PVC compatibility)
3. **Image tags** — Update or clear in `base-helm-configs/kube-prometheus-stack/kube-prometheus-stack-helm-overrides.yaml`:
   - `prometheus.prometheusSpec.image.tag: v0.34.0`
   - `alertmanager.alertmanagerSpec.image.tag: v2.49.1`
   - `prometheusOperator.image.tag: v0.26.0`
4. **CRD installation** — May need `kubectl apply -f crds.yaml` if Helm skips them

### opentelemetry-kube-stack (0.13.1 → 0.20.2) — HIGH RISK

**Changes requiring migration steps** (7 minor version jumps):
1. **Collector CRD v1→v2** schema migration
2. **Collector config** — significant changes between v0.115 and v0.154 (app versions)
3. **Cleanup image** — `cleanupJob.image.tag: v1.34.1` in overrides (line 11)
4. **Existing pattern**: `maintenance-observability-stack-upgrade.txt` shows uninstall/reinstall approach

### loki (6.52.0 → 7.3.0) — HIGH RISK

**Changes requiring migration steps**:
1. **Major chart version** (6→7) — may have CRD/values schema changes
2. **App version** — Loki 3.6.7 → 3.6.12 (minor app version, should be safe for PVCs)

---

## CI Validation

### Existing Pattern
All CI workflows (`.github/workflows/helm-*.yaml`) use:
1. `get-chart-version` action to read from `helm-chart-versions.yaml`
2. `helm template` to render the chart with overrides
3. Upload rendered output as artifact

**31 charts already have CI workflows** — no changes needed for those.

### Charts Needing New CI Workflows
6 charts need new workflow files:
- grafana, envoyproxy-gateway, longhorn, metallb, postgres-operator, redis-operator, sealed-secrets

Each workflow follows the exact same pattern as `helm-cert-manager.yaml`:
```yaml
on:
  pull_request:
    paths:
      - base-helm-configs/<chart>/**
      - base-kustomize/<chart>/**
      - helm-chart-versions.yaml
      - .github/workflows/helm-<chart>.yaml
```

### Local Validation
```bash
# Example for kube-prometheus-stack:
helm template prometheus prometheus-community/kube-prometheus-stack \
  --version 88.5.0 \
  -f base-helm-configs/kube-prometheus-stack/kube-prometheus-stack-helm-overrides.yaml \
  --create-namespace --namespace=monitoring \
  --post-renderer base-kustomize/kustomize.sh \
  --post-renderer-args kube-prometheus-stack/base > /tmp/rendered.yaml
```

---

## Prep Script for Each Maintenance

Every maintenance runbook should include this prep section:

```bash
# Create working directory
export MAINT_DIR=/home/ubuntu/<chart>-<from>-to-<to>-maint
mkdir -p "$MAINT_DIR"

# Backup state
kubectl get crd -o yaml > "$MAINT_DIR/crds-all.yaml"
kubectl get all -A -o yaml > "$MAINT_DIR/all-runtime.yaml"
helm list -A > "$MAINT_DIR/helm-list.txt"
helm get values <release> -n <ns> > "$MAINT_DIR/helm-values.yaml"

# Verify health before upgrade
kubectl get nodes
kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" {print}'
```

---

## Rollback Procedures

Each maintenance runbook includes a rollback section following this pattern:

**For chart-only rollbacks**:
```bash
# Revert version in helm-chart-versions.yaml
helm -n <namespace> rollback <release> <revision>
```

**For postgres-operator (special)**:
```bash
# Do NOT revert CRDs — revert only the operator
helm -n postgres-system uninstall postgres-operator
helm install postgres-operator zalando/postgres-operator --version 1.15.1 -n postgres-system
```

**For kube-ovn (CNI)**:
```bash
# Revert version and image tag
helm -n kube-system rollback kube-ovn <revision>
# Restart CNI pods:
kubectl -n kube-system delete pod -l app=kube-ovn
```

---

## Open Items for Implementation

1. Verify `kube_version: 1.35.1` in `capi-cluster-vars.yml.j2` — should match the cluster's 1.35.4
2. Decide whether to clear image tags to chart defaults or explicitly pin new versions in override files
3. The `envoyproxy-gateway` install script uses `oci://docker.io/envoyproxy` — verify the chart name is `gateway-helm` and version `v1.9.0` is available via `helm pull`
4. Check if `base-helm-configs/longhorn/longhorn-helm-overrides.yaml` needs any changes for 1.11.3
5. Verify `base-helm-configs/sealed-secrets/helm-sealed-secrets-overrides.yaml` exists for the new Bitnami chart version
