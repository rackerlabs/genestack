# Deploy Gnocchi

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/gnocchi/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=gnocchi
```

### List the existing secrets from `osh/gnocchi/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/gnocchi
```

### Create the secrets

- Gnocchi Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/gnocchi gnocchi-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Gnocchi Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/gnocchi gnocchi-admin  \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Gnocchi-pgsql Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/gnocchi gnocchi-pgsql-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/ghocchi
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/ghocchi  gnocchi-admin
```

## Install Gnocchi

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

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Gnocchi installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/gnocchi/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Create ceph-etc configmap

While the below example should work fine for most environments, depending
on the use case it may be necessary to provide additional client configuration
options for ceph. The below simply creates the expected `ceph-etc`
ConfigMap with the ceph.conf needed by Gnocchi to establish a connection
to the mon host(s) via the rados client.

``` shell
kubectl apply -n openstack -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-etc
  namespace: openstack
data:
  ceph.conf: |
    [global]
    mon_host = $(for pod in $(kubectl get pods -n rook-ceph | grep rook-ceph-mon | awk '{print $1}'); do \
    	echo -n "$(kubectl get pod $pod -n rook-ceph -o go-template --template='{{.status.podIP}}'):6789,"; done \
    	| sed 's/,$//')
EOF
```

### Verify the ceph-etc configmap is sane

Below is an example of what you're looking for to verify the configmap was
created as expected - a CSV of the mon hosts, colon seperated with default
mon port, 6789.

``` shell
(genestack) root@openstack-flex-launcher:/opt/genestack# kubectl get configmap -n openstack ceph-etc -o "jsonpath={.data['ceph\.conf']}"
[global]
mon_host = 172.31.3.7:6789,172.31.1.112:6789,172.31.0.46:6789
```

### Deploy Gnocchi helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install gnocchi ./gnocchi \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/helm-configs/gnocchi/gnocchi-helm-overrides.yaml \
    --set conf.ceph.admin_keyring="$(kubectl get secret --namespace rook-ceph rook-ceph-admin-keyring -o jsonpath='{.data.keyring}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-pgsql-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args gnocchi/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

## Validate the metric endpoint

### Pip install gnocchiclient and python-ceilometerclient

``` shell
kubectl exec -it openstack-admin-client -n openstack -- /var/lib/openstack/bin/pip install python-ceilometerclient gnocchiclient
```

### Verify metric list functionality

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric list
```
