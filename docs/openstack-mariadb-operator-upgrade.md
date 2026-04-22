# :material-database-arrow-up: MariaDB Operator Upgrade Runbook

Unified procedure for upgrading the MariaDB Operator Helm chart through the
required progressive upgrade path. Sequential upgrades are mandatory due to
CRD evolution and changes in replication and backup behaviour across versions.

!!! abstract "Upgrade Path"

    ```
    0.36.0 → 0.37.1 → 0.38.1 → 25.8.4 → 25.10.4 → 26.3.0
    ```

!!! danger "Never Delete CRDs"
    Never delete CRDs during the upgrade — doing so will delete the
    MariaDB database pods. Uninstalling the operator Helm release alone does **not**
    cause DB downtime.

---

## :material-check-decagram: Prerequisites

### Check current installed versions

```bash
helm list -A | grep mariadb
helm status mariadb-operator -n mariadb-system
helm status mariadb-operator-crds -n mariadb-system
```

### Update Helm repo and list available chart versions

```bash
helm repo update mariadb-operator
helm search repo mariadb-operator/mariadb-operator --versions | head -20
```

---

## :material-clipboard-check: Pre-Upgrade Checks

!!! info "Repeat Before Every Step"
    Run these checks before **every** upgrade step in the path.

### 1. Retrieve MariaDB root password

```bash
export MARIADB_ROOT_PASSWORD=$(kubectl get secret mariadb -n openstack \
  -o jsonpath='{.data.root-password}' | base64 -d)
```

### 2. Create full database backup

Identify the primary pod first, then run the backup from it:

```bash
PRIMARY_POD=$(kubectl get mariadb mariadb-cluster -n openstack -o jsonpath="{.status.currentPrimary}")
echo "Primary pod: $PRIMARY_POD"
```

```bash
kubectl exec -i "$PRIMARY_POD" -n openstack -- mariadb-dump \
  -u root -p"$MARIADB_ROOT_PASSWORD" \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers > mariadb-cluster-full-backup-$(date +%Y%m%d-%H%M).sql
```

Verify the backup:

```bash
ls -lh mariadb-cluster-full-backup-*.sql | tail -1
```

### 3. Check database sizes

```sql
kubectl exec -it "$PRIMARY_POD" -n openstack -- mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "
SELECT
  table_schema AS 'Database',
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB'
FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY table_schema
ORDER BY Size_MB DESC;"
```

### 4. Verify cluster health

Determine your cluster topology and run the appropriate checks:

=== "Galera Cluster"

    ```sql
    kubectl exec -it "$PRIMARY_POD" -n openstack -- mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "
    SHOW STATUS LIKE 'wsrep_cluster_size';
    SHOW STATUS LIKE 'wsrep_cluster_status';
    SHOW STATUS LIKE 'wsrep_ready';"
    ```

    !!! success "Expected Values"
        | Variable | Expected |
        |----------|----------|
        | `wsrep_cluster_size` | `3` |
        | `wsrep_cluster_status` | `Primary` |
        | `wsrep_ready` | `ON` |

=== "Primary/Replica (Replication)"

    Check the primary:

    ```bash
    kubectl get mariadb mariadb-cluster -n openstack -o jsonpath="{.status.currentPrimary}"
    ```

    Check replication status on each replica:

    ```sql
    kubectl exec -it mariadb-cluster-1 -n openstack -- mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "
    SHOW REPLICA STATUS\G"
    ```

    !!! success "Expected Values"
        | Variable | Expected |
        |----------|----------|
        | `Slave_IO_Running` | `Yes` |
        | `Slave_SQL_Running` | `Yes` |
        | `Seconds_Behind_Master` | `0` |

!!! tip "How to identify your topology"
    Check the MariaDB CR spec:

    ```bash
    kubectl get mariadb mariadb-cluster -n openstack -o jsonpath="{.spec.galera.enabled}"
    ```

    - Returns `true` → Galera cluster
    - Returns empty/false → Primary/Replica (replication)

### 5. Verify cluster and pod status

```bash
kubectl get mariadb -n openstack
kubectl get pods -l app.kubernetes.io/name=mariadb -n openstack
kubectl get mariadb -n openstack -o yaml | grep -B1 autoFailover  #Read "Disclaimer" below
kubectl get crd | grep mariadb
```

!!! info "Disclaimer"
    Only present on versions >= 25.10.4

### 6. Verify current operator, webhook, and MariaDB image versions

=== "Operator Image"

    ```bash
    kubectl get pods -n mariadb-system -o wide

    kubectl get pods \
        $(kubectl get pods \
        -l app.kubernetes.io/name=mariadb-operator \
        -n mariadb-system \
        -o jsonpath='{.items[0].metadata.name}') \
        -n mariadb-system \
        -o jsonpath="{..image}" | tr -s '[:space:]' '\n' | sort -u
    ```

=== "Webhook Image"

    ```bash
    kubectl get pods \
        $(kubectl get pods \
        -l app.kubernetes.io/name=mariadb-operator-webhook \
        -n mariadb-system \
        -o jsonpath='{.items[0].metadata.name}') \
        -n mariadb-system \
        -o jsonpath="{..image}" | tr -s '[:space:]' '\n' | sort -u
    ```

=== "MariaDB Image"

    ```bash
    kubectl get pods "$PRIMARY_POD" \
        -n openstack \
        -o jsonpath="{..image}" \
        | tr -s '[:space:]' '\n' | sort -u
    ```

---

## :material-repeat: Per-Version Upgrade Procedure

Repeat this procedure for each version in the upgrade path. Version-specific
notes are listed in the [next section](#version-specific-notes).


### :material-airplane-takeoff: Preflight: Update MariaDB image and enable `autoUpdateDataPlane`

Update the MariaDB image in `/opt/genestack/base-kustomize/mariadb-cluster/base/mariadb-replication.yaml`
to match the version compatible with the operator chart version being deployed.
With every release update you must update this image **before** upgrading the
mariadb-cluster (Galera or Replication).

For replication clusters, treat this file as the canonical MariaDB baseline. In
addition to the image tag, preserve the crash-safe replication settings
(`binlog_format=ROW`, `innodb_flush_log_at_trx_commit=1`, `sync_binlog=1`) and
the compatibility defaults (`character-set-server=utf8mb3`,
`collation-server=utf8mb3_general_ci`) required for Alembic migrations against
older OpenStack tables.

??? info "Finding the compatible MariaDB image"
    Check the `config.mariadbImage` value in the upstream chart's `values.yaml` at the
    corresponding tag:

    ```
    https://github.com/mariadb-operator/mariadb-operator/blob/v<VERSION>/deploy/charts/mariadb-operator/values.yaml
    ```

    For example, for chart version **25.8.4**:

    ```
    https://github.com/mariadb-operator/mariadb-operator/blob/v25.8.4/deploy/charts/mariadb-operator/values.yaml
    ```

    shows `mariadbImage: docker-registry1.mariadb.com/library/mariadb:11.8.2`.

Update the image in the base manifest. Below is an example while upgrading to `25.8.4` compliant mariadb image:

```yaml title="mariadb-replication.yaml"
spec:
  image: docker-registry1.mariadb.com/library/mariadb:11.8.2
```

Then set `autoUpdateDataPlane: true` using one of the following methods:

=== "Kustomize Overlay (Recommended)"

    Edit `/etc/genestack/kustomize/mariadb-cluster/overlay/kustomization.yaml`:

    ```yaml title="kustomization.yaml"
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
      - ../galera

    patches:
      - target:
          kind: MariaDB
          name: mariadb-cluster
          namespace: openstack
        patch: |-
          - op: replace
            path: /spec/updateStrategy/autoUpdateDataPlane
            value: true
    ```

=== "Base Manifest"

    Edit `/etc/genestack/kustomize/mariadb-cluster/base/mariadb-replication.yaml`:

    ```yaml title="mariadb-replication.yaml"
    spec:
      updateStrategy:
        autoUpdateDataPlane: true
    ```

!!! note "Why autoUpdateDataPlane?"
    Enabling `autoUpdateDataPlane` uses a **ReplicasFirstPrimaryLast** strategy instead of
    **RollingUpdate**. This applies to both cluster topologies:

    - **Galera**: Updates replica nodes first, then the primary. Avoids breaking the
      quorum by ensuring a majority of nodes remain available during the rollout.
    - **Primary/Replica**: Updates replicas first, then the primary. Prevents write
      downtime and data inconsistency by keeping the primary running until all
      replicas are updated and healthy.

    In both cases, updating the primary first risks downtime and data inconsistency.

Apply the changes:

```bash
kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
```

### :material-arrow-down-bold: Step 1: Scale down operator and remove webhooks

```bash
kubectl scale deployment mariadb-operator -n mariadb-system --replicas=0
kubectl scale deployment mariadb-operator-webhook -n mariadb-system --replicas=0
kubectl delete validatingwebhookconfiguration mariadb-operator-webhook
kubectl delete mutatingwebhookconfiguration mariadb-operator-webhook 2>/dev/null || true
```

### :material-pencil: Step 2: Update chart version

Edit `/etc/genestack/helm-chart-versions.yaml`:

```yaml title="helm-chart-versions.yaml"
mariadb-operator: <TARGET_VERSION>
```

Confirm the version has been set:

```bash
grep mariadb-operator /etc/genestack/helm-chart-versions.yaml
```

### :material-swap-horizontal: Step 3: Uninstall and reinstall operator

```bash
helm uninstall mariadb-operator -n mariadb-system
/opt/genestack/bin/install-mariadb-operator.sh
```

### :material-check-circle: Step 4: Verify deployment

```bash
helm list -A | grep mariadb
kubectl get pods -n mariadb-system -o wide
kubectl get pods <new-operator-pod> -n mariadb-system \
  -o jsonpath="{..image}" | tr -s '[:space:]' '\n' | sort -u
```

### :material-stethoscope: Step 5: Post-upgrade validation

```bash
kubectl get pods -n openstack | grep mariadb
kubectl get mariadb -n openstack
```

Run the [cluster health checks from the pre-upgrade section](#4-verify-cluster-health) again.

### :material-toggle-switch-off: Step 6: Disable autoUpdateDataPlane

Set `autoUpdateDataPlane: false` as per the [preflight section](#preflight-update-mariadb-image-and-enable-autoupdatedataplane) and re-apply:

```bash
kubectl --namespace openstack apply -k /etc/genestack/kustomize/mariadb-cluster/overlay
```

### :material-toggle-switch-off: Step 7: Run the migration (Replication clusters only)

!!! warning "Replication Migration — Primary/Replica clusters only"
    This step is only required for **Primary/Replica (replication)** clusters.
    If you are running a **Galera** cluster, skip this step.

    After the operator upgrade, you must run the replication migration script
    to reset and re-establish replication on each replica pod.

The script automatically identifies the primary pod (skips it) and processes only the replicas.
For each replica it:

- [x] Runs `STOP SLAVE` and `RESET SLAVE ALL` via `kubectl exec`
- [x] Deletes the pod so it gets recreated
- [x] Waits for it to come back ready
- [x] Verifies replication is working again

Set the required environment variables:

```bash
export MARIADB_NAME=mariadb-cluster
export MARIADB_NAMESPACE=openstack
export MARIADB_ROOT_PASSWORD=$(kubectl get secret mariadb -n openstack \
  -o jsonpath='{.data.root-password}' | base64 -d)
```

Save the script to a file (e.g. `/tmp/migrate-replication.sh`):

??? example "migrate-replication.sh (click to expand)"

    ```bash title="migrate-replication.sh"
    #!/bin/bash

    set -eo pipefail

    if [[ -z "$MARIADB_NAME" || -z "$MARIADB_NAMESPACE" || -z "$MARIADB_ROOT_PASSWORD" ]]; then
      echo "Error: MARIADB_NAME, MARIADB_NAMESPACE and MARIADB_ROOT_PASSWORD env vars must be set."
      exit 1
    fi

    function exec_sql {
      local pod=$1
      local sql=$2
      kubectl exec -n "$MARIADB_NAMESPACE" "$pod" -- mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "$sql"
    }

    function wait_for_ready_replication {
      local pod=$1
      local timeout=300  # 5 minutes
      local interval=10  # Check every 10 seconds
      local elapsed=0

      echo "Waiting for ready replication on $pod..."

      while [[ $elapsed -lt $timeout ]]; do
          local status
          status=$(exec_sql "$pod" "SHOW REPLICA STATUS\G" | tee /tmp/replication_status_$pod_$MARIADB_NAMESPACE.txt)

          if grep -q "Slave_IO_Running: Yes" /tmp/replication_status_$pod_$MARIADB_NAMESPACE.txt && \
             grep -q "Slave_SQL_Running: Yes" /tmp/replication_status_$pod_$MARIADB_NAMESPACE.txt; then
            echo "Replication is ready on $pod."
            return 0
          fi

          echo "Replication not ready on $pod. Retrying in $interval seconds..."
          sleep $interval
          ((elapsed+=interval))
      done

      echo "Error: Replication did not become ready on $pod within 5 minutes."
      exit 1
    }

    echo "Migrating replication on $MARIADB_NAME instance..."

    PODS=$(kubectl get pods -n "$MARIADB_NAMESPACE" \
      -l app.kubernetes.io/instance=$MARIADB_NAME \
      -o jsonpath="{.items[*].metadata.name}")
    PRIMARY_POD=$(kubectl get mariadb "$MARIADB_NAME" -n "$MARIADB_NAMESPACE" \
      -o jsonpath="{.status.currentPrimary}")

    for POD in $PODS; do
      if [[ "$POD" == "$PRIMARY_POD" ]]; then
          printf "\nSkipping primary pod: $POD\n"
          continue
      fi
      printf "\nProcessing replica pod: $POD\n"

      echo "Resetting replication on $POD..."
      exec_sql "$POD" "STOP SLAVE 'mariadb-operator';"
      exec_sql "$POD" "RESET SLAVE 'mariadb-operator' ALL;"

      echo "Deleting pod $POD..."
      kubectl delete pod "$POD" -n "$MARIADB_NAMESPACE"

      echo "Waiting for pod $POD to become ready..."
      kubectl wait --for=condition=Ready pod/"$POD" -n "$MARIADB_NAMESPACE" --timeout=5m
      echo "Pod $POD is ready."

      wait_for_ready_replication "$POD"
    done

    echo "Replication migration completed successfully on $MARIADB_NAME instance."
    ```

Make it executable and run:

```bash
chmod +x /tmp/migrate-replication.sh
/tmp/migrate-replication.sh
```

??? tip "Stuck replication threads"
    If stuck replication threads are observed, identify and kill them:

    ```bash
    kubectl exec -it mariadb-cluster-1 -n openstack -- mariadb \
      -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW PROCESSLIST;"
    kubectl exec -it mariadb-cluster-1 -n openstack -- mariadb \
      -u root -p"$MARIADB_ROOT_PASSWORD" -e "KILL <thread_id>;"
    ```
---

## :material-tag-text: Version-Specific Notes

### 0.37.1

Skip 0.37.0

!!! note "References"
    - [Release 0.37.1](https://github.com/mariadb-operator/mariadb-operator/releases/tag/0.37.1)
    - [Upgrade Guide 0.37.1](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/releases/UPGRADE_0.37.1.md)

Follow the [standard procedure](#per-version-upgrade-procedure) above. No special steps required.

### 0.38.1

Skip 0.38.0

!!! note "References"
    - [Release 0.38.1](https://github.com/mariadb-operator/mariadb-operator/releases/tag/0.38.1)
    - [Upgrade Guide 0.38.0](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/releases/UPGRADE_0.38.0.md)
    - [Upgrade Guide 0.38.1](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/releases/UPGRADE_0.38.1.md)

### 25.8.4

Skip 25.08.0

!!! note "References"
    - [Release 25.8.1](https://github.com/mariadb-operator/mariadb-operator/releases/tag/25.8.1)
    - [Upgrade Guide 25.08.0](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/releases/UPGRADE_25.08.0.md)
    - [Upgrade Guide 25.8.1](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/releases/UPGRADE_25.8.1.md)

!!! warning "Patch-by-patch upgrade is NOT required for 25.8.x"
    You do not need to step through each patch releases in between 25.8.x - using the above standard procedure:

    ```
    25.8.1 → 25.8.2 → 25.8.3 → 25.8.4
    ```
    
    If you are migrating from `0.38.1`, check the `helm search repo mariadb-operator/mariadb-operator --versions` output:

    ```
    mariadb-operator/mariadb-operator     	25.8.4       	25.8.4     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	25.8.3       	25.8.3     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	25.8.2       	25.8.2     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	25.8.1       	25.8.1     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	25.08.0      	25.08.0    	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	0.38.1       	0.38.1     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	0.38.0       	0.38.0     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	0.37.1       	0.37.1     	Run and operate MariaDB in a cloud native way
    mariadb-operator/mariadb-operator     	0.37.0       	0.37.0     	Run and operate MariaDB in a cloud native way
    ```

    and you can directly jump from `0.38.1 → 25.8.4`

!!! warning "Kubernetes version compatibility"
    Confirm Kubernetes version compatibility against the upstream chart metadata
    before performing the `0.38.1 -> 25.8.4` hop. Do not assume a fixed
    minimum cluster version from this runbook alone.

??? bug "Known Issue: Webhook cert validation loop"
    If operator pods are stuck logging:

    ```json
    {"level":"info","ts":...,"logger":"setup","msg":"Validating certs"}
    ```

    Check the certificate:

    ```bash
    kubectl get certificate -n mariadb-system
    ```

    If you see `Existing private key is not up to date for spec: [spec.privateKey.algorithm]`,
    fix by deleting the secret and webhook deployment:

    ```bash
    kubectl delete secret mariadb-operator-webhook-cert -n mariadb-system
    kubectl delete deployment mariadb-operator-webhook -n mariadb-system
    ```

    Then re-run the install script to recreate them.

### 25.10.4

Skip 25.10.0, You do not need to step through each patch releases in between 25.8.x - using the above standard procedure.

!!! warning "Patch-by-patch upgrade is NOT required for 25.10.x"
    You do not need to step through each patch releases in between 25.8.x - using the above standard procedure:

    ```
    25.10.1 → 25.10.2 → 25.10.3 → 25.10.4
    ```

For `25.10.4`, Follow the [standard procedure](#per-version-upgrade-procedure). 
No special steps required beyond the standard preflight and upgrade.

### 26.3.0

!!! note "References"
    - [Release 26.3.0](https://github.com/mariadb-operator/mariadb-operator/releases/tag/26.3.0)

!!! danger "Replication config change carried into 26.3.0"
    In the `25.x` replication line, `syncBinlog` changed from **boolean** to
    **integer**. This affects **Primary/Replica (replication)** clusters.
    Galera clusters without `replication` in their spec are not affected.

    If the existing MariaDB CR still stores `syncBinlog: true`, the newer
    webhook can reject updates during the `25.10.4 -> 26.3.0` hop. Remove the
    webhook before patching:

    ```bash
    kubectl delete validatingwebhookconfiguration mariadb-operator-webhook
    kubectl -n openstack patch mariadb mariadb-cluster --type merge \
      -p '{"spec":{"replication":{"syncBinlog":1}}}'
    ```

    Then re-run the install script to restore the webhook.

!!! danger "Breaking Change: Image configuration format"
    Review the `26.3.0` Helm values schema carefully before upgrading.
    Several image sections now use structured `repository` + `tag` values.

    === "Old Format"

        ```yaml
        config:
          mariadbImageName: repo/image
        ```

    === "New Format"

        ```yaml
        config:
          mariadbImage:
            repository: repo/image
            tag: <version>
        ```

    Ensure `/etc/genestack/helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml`
    matches the `26.3.0` schema for `maxscaleImage`, `exporterImage`, and
    `exporterMaxscaleImage` before upgrading. Do not assume that every legacy
    image-related key disappears; compare the full overrides file against the
    target chart schema.

!!! info "New CRD"
    A new CRD is added with this version: `pointintimerecoveries.k8s.mariadb.com`

---

## :material-wrench: Troubleshooting

### Webhook blocks patches due to old stored values

If the webhook rejects changes because the existing resource in etcd has
old-format values (e.g. `syncBinlog: true`), temporarily remove the webhook:

```bash
kubectl scale deployment mariadb-operator -n mariadb-system --replicas=0
kubectl scale deployment mariadb-operator-webhook -n mariadb-system --replicas=0
kubectl delete validatingwebhookconfiguration mariadb-operator-webhook
kubectl delete mutatingwebhookconfiguration mariadb-operator-webhook 2>/dev/null || true
```

Apply the fix, then re-run the install script to restore everything.

### Webhook cert validation loop

If operator pods are stuck in a `Validating certs` loop, delete the webhook
cert secret and deployment, then re-run the install script:

```bash
kubectl delete secret mariadb-operator-webhook-cert -n mariadb-system
kubectl delete deployment mariadb-operator-webhook -n mariadb-system
/opt/genestack/bin/install-mariadb-operator.sh
```
