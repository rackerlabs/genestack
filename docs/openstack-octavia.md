# Deploy Octavia

[![asciicast](https://asciinema.org/a/629814.svg)](https://asciinema.org/a/629814)

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/octavia/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=octavia
```

### List the existing secrets from `osh/octavia/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/octavia
```

### Create the secrets

- Octavia RabbitMQ Username and Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/octavia/octavia-rabbitmq-password username=octavia

kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv patch -mount=osh/octavia octavia-rabbitmq-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

- Octavia Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/octavia octavia-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Octavia Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/octavia octavia-admin  \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Octavia-certificates Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/octavia octavia-certificates  \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/octavia
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/octavia  octavia-admin
```

## Install Octavia

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

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Octavia installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/octavia/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Deploy Octavia helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install octavia ./octavia \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/octavia/octavia-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.octavia.certificates.ca_private_key_passphrase="$(kubectl --namespace openstack get secret octavia-certificates -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.octavia.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.octavia.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args octavia/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

Now validate functionality
