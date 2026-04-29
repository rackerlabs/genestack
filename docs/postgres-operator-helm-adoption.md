# Bringing Postgres Operator Under Helm Control

This guide provides step-by-step instructions for migrating the postgres-operator from a manually deployed state to Helm-managed control in Genestack.

## Verify What Helm Would Do

Before making any changes to the cluster, it's important to understand exactly what Helm will apply and how it differs from the current state. This verification uses kubectl and dyff to compare manifests without modifying anything.

### Step 1: Recreate the Effective Manifests Helm Would Apply

On the overseer node in the target environment:

1. Navigate to the Genestack directory:

```bash
cd /opt/genestack
```

2. Optionally, confirm the postgres-operator version that will be used:

```bash
cat /etc/genestack/helm-chart-versions.yaml | grep postgres-operator
```

3. Set up the Helm repository and discover the chart configuration:

```bash
# Set variables matching the install script
SERVICE_NAME=postgres-operator
SERVICE_NAMESPACE=postgres-system
HELM_REPO_NAME=postgres-operator-charts
HELM_REPO_URL=https://opensource.zalando.com/postgres-operator/charts/postgres-operator

# Add the repository (if not already added)
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
helm repo update

# Extract the service version from the chart versions file
SERVICE_VERSION=$(grep "^[[:space:]]*${SERVICE_NAME}:" /etc/genestack/helm-chart-versions.yaml \
                  | sed "s/.*${SERVICE_NAME}: *//")
```

4. Build the Helm values arguments from configuration files:

```bash
HELM_VALUES_ARGS=()
for f in /opt/genestack/base-helm-configs/postgres-operator/*.yaml; do
  [ -f "$f" ] && HELM_VALUES_ARGS+=( -f "$f" )
done
for f in /etc/genestack/helm-configs/postgres-operator/*.yaml; do
  [ -f "$f" ] && HELM_VALUES_ARGS+=( -f "$f" )
done
```

5. Render the manifests to a file (no changes applied to cluster):

```bash
helm template postgres-operator \
  "${HELM_REPO_NAME}/${SERVICE_NAME}" \
  --version "$SERVICE_VERSION" \
  --namespace "$SERVICE_NAMESPACE" \
  "${HELM_VALUES_ARGS[@]}" \
  > /tmp/postgres-operator-rendered.yaml
```

### Step 2: Capture Current Live State

Export the current resources running in the cluster:

```bash
# Current deployment
kubectl get deployment postgres-operator -n postgres-system -o yaml \
  > /tmp/postgres-operator-live-deploy.yaml

# Current Custom Resource Definition
kubectl get crd postgresqls.acid.zalan.do -o yaml \
  > /tmp/postgres-operator-live-crd.yaml
```

If the postgres-operator has associated ConfigMaps, ServiceAccounts, or RBAC resources, export those as well:

```bash
# List and optionally export ConfigMaps
kubectl get cm -n postgres-system | grep postgres-operator

# List and optionally export ServiceAccounts
kubectl get sa -n postgres-system | grep postgres-operator

# List and optionally export Roles and RoleBindings
kubectl get role,rolebinding -n postgres-system | grep postgres-operator

# List and optionally export ClusterRoles and ClusterRoleBindings
kubectl get clusterrole,clusterrolebinding | grep postgres-operator

# Export any of the above with:
# kubectl get <kind> <name> -o yaml > /tmp/<resource>.yaml
```

### Step 3: Use dyff to Compare

With both the rendered Helm manifests and live cluster state captured, use dyff to see differences without modifying the cluster.

#### Direct Object-to-Object Comparison

```bash
dyff between \
  <(cat /tmp/postgres-operator-live-deploy.yaml) \
  <(cat /tmp/postgres-operator-rendered.yaml) \
  --omit-header

dyff between \
  <(cat /tmp/postgres-operator-live-crd.yaml) \
  <(cat /tmp/postgres-operator-rendered.yaml) \
  --omit-header
```

### Step 4: Simulate Adoption Annotations

To see what changes would occur after Helm adoption annotations are added (without actually applying them):

1. Create simulated copies:

```bash
cp /tmp/postgres-operator-live-deploy.yaml /tmp/postgres-operator-sim-deploy.yaml
cp /tmp/postgres-operator-live-crd.yaml /tmp/postgres-operator-sim-crd.yaml
```

2. Add Helm ownership annotations to the simulated deployment:

```bash
cat /tmp/postgres-operator-sim-deploy.yaml | yq '
  .metadata.annotations["meta.helm.sh/release-name"] = "postgres-operator" |
  .metadata.annotations["meta.helm.sh/release-namespace"] = "postgres-system"
' > /tmp/postgres-operator-sim-deploy-annotated.yaml
```

3. Add Helm ownership annotations and labels to the simulated CRD:

```bash
cat /tmp/postgres-operator-sim-crd.yaml | yq '
  .metadata.annotations["meta.helm.sh/release-name"] = "postgres-operator" |
  .metadata.annotations["meta.helm.sh/release-namespace"] = "postgres-system" |
  .metadata.labels["app.kubernetes.io/managed-by"] = "Helm"
' > /tmp/postgres-operator-sim-crd-annotated.yaml
```

4. Compare the simulated adopted state against the live captured chart(s):

```bash
dyff between \
  <(cat /tmp/postgres-operator-live-deploy.yaml) \
  <(cat /tmp/postgres-operator-sim-deploy-annotated.yaml) \
  --omit-header

dyff between \
  <(cat /tmp/postgres-operator-live-crd.yaml) \
  <(cat /tmp/postgres-operator-sim-crd-annotated.yaml) \
  --omit-header
```

This shows exactly how the cluster state will differ after adoption without making changes.

## Pre-Deployment Checks

Before making any changes, verify the health of both the postgres-operator and the underlying PostgreSQL database.

### Check Operator Health

Verify that the postgres-operator deployment is running properly:

```bash
kubectl get pods -n postgres-system | grep postgres-operator
kubectl logs deployment/postgres-operator -n postgres-system | tail -n 50
```

## Backup Postgres Database

Creating a backup before making significant changes is critical for disaster recovery.

### Identify the Master Pod

Find which pod holds the master role in the postgres cluster:

```bash
kubectl get pods -n openstack -l cluster-name=postgres-cluster,spilo-role=master
```

### Create the Backup

Replace `<master-pod>` with the name of the master pod identified above:

```bash
kubectl exec -n openstack -t <master-pod> -- pg_dumpall -U postgres > ~/backup_<master-pod>.sql

# Move the backup to the backups directory
sudo mv ~/backup_<master-pod>.sql /var/backups/cluster_<master-pod>_$(date +%F).sql
```

### Verify Backup Integrity

Confirm the backup contains actual data:

```bash
# Check for COPY statements indicating data presence
grep -m 5 "COPY" /var/backups/cluster_<master-pod>_*.sql
```

The output should show lines starting with `COPY ... FROM stdin;` indicating data is present.

### Check for Completion Marker

PostgreSQL dumps should end with a completion marker. Verify it's present:

```bash
sudo tail -n 5 /var/backups/cluster_<master-pod>_*.sql
```

Look for the line: `PostgreSQL database cluster dump complete`

!!! warning
    If this line is missing, the dump may have been interrupted and the backup may be incomplete.

## Apply Adoption Annotations

Once verification and backups are complete, annotate the postgres-operator resources to mark them as Helm-managed.

### Annotate the Deployment

```bash
kubectl annotate deployment postgres-operator -n postgres-system \
  meta.helm.sh/release-name=postgres-operator \
  --overwrite

kubectl annotate deployment postgres-operator -n postgres-system \
  meta.helm.sh/release-namespace=postgres-system \
  --overwrite
```

### Annotate and Label the CRD

```bash
kubectl annotate crd postgresqls.acid.zalan.do \
  meta.helm.sh/release-name=postgres-operator \
  --overwrite

kubectl annotate crd postgresqls.acid.zalan.do \
  meta.helm.sh/release-namespace=postgres-system \
  --overwrite

kubectl label crd postgresqls.acid.zalan.do \
  app.kubernetes.io/managed-by=Helm \
  --overwrite
```

### Run the Helm Adoption

Execute the Genestack postgres-operator installation script to perform the actual Helm adoption:

```bash
/opt/genestack/bin/install-postgres-operator.sh
```

This command executes a `helm upgrade --install` using the current chart version and overrides, and creates the Helm Release Secret needed for Helm to manage the resource.

## Post-Adoption Verification

After the adoption is complete, verify that Helm now has control and the operator is still functioning correctly.

### Verify Helm Visibility

Confirm Helm recognizes the postgres-operator release:

```bash
helm list -A --all | { read -r header; printf '%s\n' "$header"; grep postgres-operator; }
```

### Check Operator and Database Health

Verify the operator and cluster are still functioning:

```bash
# Check operator pod status
kubectl get pods -n postgres-system | grep postgres-operator

# Check recent operator logs
kubectl logs deployment/postgres-operator -n postgres-system | tail -n 100
```

## Rollback Considerations

If issues arise after adoption, rollback procedures are available at both the Helm and database levels.

### Helm-Level Rollback

If there are problems at the Helm level:

```bash
# Remove the Helm release
helm uninstall postgres-operator

# Manually reapply the previously exported YAML
kubectl apply -f /tmp/postgres-operator-live-deploy.yaml
kubectl apply -f /tmp/postgres-operator-live-crd.yaml
```

### Database-Level Rollback

If the database is corrupted or data is lost, restore from the backup created earlier (see [Restore Postgres Database](#restore-postgres-database)).

## Restore Postgres Database

If the PostgreSQL database becomes corrupted or requires restoration from backup, follow these steps.

### Identify the Master Pod

Find the current master pod:

```bash
kubectl get pods -n openstack -l cluster-name=postgres-cluster,spilo-role=master
```

### Stream Backup into the Database

Replace `<master-pod>` with the name of the master pod:

```bash
cat /var/backups/cluster_<master-pod>_*.sql | kubectl exec -i -n openstack <master-pod> -- psql -U postgres
```

### Handle Expected Errors

When restoring a pg_dumpall to an existing cluster, you may encounter expected errors:

- **"role already exists"**: Normal if users (roles) are already present in the cluster.
- **"database already exists"**: Expected if the cluster is actively running.

These messages do not indicate restoration failure.

### Verify the Restoration

After restoration completes, verify the data is present:

1. Enter the pod:

```bash
kubectl exec -it -n openstack <master-pod> -- psql -U postgres
```

2. List databases:

```sql
\l
```

3. Connect to your specific database (example: gnocchi):

```sql
\c gnocchi
```

4. Check for tables:

```sql
\dt
```

If tables and data are visible, the restoration was successful.

### Clean Restore (Optional)

If you need to perform a clean restore by removing existing data first:

1. Connect to the pod and drop the database:

```bash
kubectl exec -it -n openstack <master-pod> -- psql -U postgres -c "DROP DATABASE <db name>;"
```

2. Run the restore command:

```bash
cat /var/backups/cluster_<master-pod>_*.sql | kubectl exec -i -n openstack <master-pod> -- psql -U postgres
```

This completely replaces the database with the backed-up version.
