# Deploy PostgreSQL

## Create Secrets
!!! info

    This step is not needed if you ran the create-secrets.sh script located in /opt/genestack/bin

``` shell
kubectl --namespace openstack create secret generic postgresql-identity-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-exporter \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-audit \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

## Run the package deployment

!!! tip

    Consider the PVC size you will need for the environment you're deploying in. Make adjustments as needed near `storage.[pvc|archive_pvc].size` and `volume.backup.size` to your helm overrides.

``` shell
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install postgresql ./postgresql \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /etc/genestack/helm-configs/postgresql/postgresql-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.postgresql.password="$(kubectl --namespace openstack get secret postgresql-identity-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.exporter.password="$(kubectl --namespace openstack get secret postgresql-db-exporter -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.audit.password="$(kubectl --namespace openstack get secret postgresql-db-audit -o jsonpath='{.data.password}' | base64 -d)"
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.
