# Deploy PostgreSQL

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/postgresql/` path in the Vault

## Create secrets in the vault:

### Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=postgresql
```

### List the existing secrets from `osh/postgresql/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/postgresql
```

### Create the secrets

- Postgresql-identity-admin:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/postgresql postgresql-identity-admin password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Postgresql-db-admin:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/postgresql postgresql-db-admin password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Postgresql-db-exporter:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/postgresql postgresql-db-exporter password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Postgresql-db-audit:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/postgresql postgresql-db-audit password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/postgresql
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/postgresql postgresql-identity-admin
```

## Install PostgreSQL

- Ensure that the `vault-ca-secret` Kubernetes Secret exists in the OpenStack namespace containing the Vault CA certificate:

``` shell
kubectl get secret vault-ca-secret -o yaml -n openstack
```

- If it is absent, create one using the following command:

``` shell
kubectl create secret generic vault-ca-secret \
    --from-literal=ca.crt="$(kubectl get secret vault-tls-secret \
    -o jsonpath='{.data.ca\.crt}' -n vault | base64 -d -)" -n openstack
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the postgresql installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/postgresql/base/vault
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Deploy PostgreSQL

!!! tip

    Consider the PVC size you will need for the environment you're deploying in. Make adjustments as needed near `storage.[pvc|archive_pvc].size` and `volume.backup.size` to your helm overrides.

``` shell
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install postgresql ./postgresql \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/helm-configs/postgresql/postgresql-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.postgresql.password="$(kubectl --namespace openstack get secret postgresql-identity-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.exporter.password="$(kubectl --namespace openstack get secret postgresql-db-exporter -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.audit.password="$(kubectl --namespace openstack get secret postgresql-db-audit -o jsonpath='{.data.password}' | base64 -d)"
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.
