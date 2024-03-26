# Deploy Glance

[![asciicast](https://asciinema.org/a/629806.svg)](https://asciinema.org/a/629806)

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/glance/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=glance
```

### List the existing secrets from `osh/glance/`

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/glance
```

### Create the secrets

- Glance RabbitMQ Username and Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/heat/glance-rabbitmq-password username=glance

kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv patch -mount=osh/glance glance-rabbitmq-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

- Glance Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/glance glance-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

- Glance Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/glance glance-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/glance
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/glance  glance-admin
```

!!! info

    Before running the Glance deployment you should configure the backend which is defined in the `helm-configs/glance/glance-helm-overrides.yaml` file. The default is a making the assumption we're running with Ceph deployed by Rook so the backend is configured to be cephfs with multi-attach functionality. While this works great, you should consider all of the available storage backends and make the right decision for your environment.

## Install Glance

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

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Glance installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/glance/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Deploy Glance helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/glance/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb-root-password -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args glance/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

!!! note

    The defaults disable `storage_init` because we're using **pvc** as the image backend type. In production this should be changed to swift.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack image list
```
