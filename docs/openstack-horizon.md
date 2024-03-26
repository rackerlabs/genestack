# Deploy Horizon

[![asciicast](https://asciinema.org/a/629815.svg)](https://asciinema.org/a/629815)

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/horizon/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=horizon
```

### List the existing secrets from `osh/horizon/`

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/horizon
```

### Create the secrets

- Horizon-secrete-key Username and Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/horizon/horizon-secrete-key username=horizon

kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv patch -mount=osh/horizon horizon-secrete-key \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

- Horizon Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/horizon horizon-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/horizon
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/horizon horizon-secrete-key
```

## Install Horizon

- Ensure that the `vault-ca-secret` Kubernetes Secret exists in the OpenStack namespace containing the Vault CA certificate:

```shell
kubectl get secret vault-ca-secret -o yaml -n openstack
```

- If it is absent, create one using the following command:

``` shell
kubectl create secret generic vault-ca-secret \
    --from-literal=ca.crt="$(kubectl get secret vault-tls-secret \
    -o jsonpath='{.data.ca\.crt}' -n vault | base64 -d -)" -n openstack
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Horizon installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/horizon/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Deploy Horizon helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install horizon ./horizon \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/horizon/horizon-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.horizon.local_settings.config.horizon_secret_key="$(kubectl --namespace openstack get secret horizon-secrete-key -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.horizon.password="$(kubectl --namespace openstack get secret horizon-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args horizon/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.
