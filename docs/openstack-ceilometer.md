# Deploy Ceilometer

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/ceilometer/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=ceilometer
```

### List the existing secrets from `osh/ceilometer/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/ceilometer
```

### Create the secrets

- Ceilometer-keystone-admin-password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/ceilometer/ceilometer-keystone-admin-password password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Ceilometer-keystone-test-password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/ceilometer ceilometer-keystone-test-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Ceilometer-rabbitmq-password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/ceilometer ceilometer-rabbitmq-password  \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/ceilometer
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/ceilometer  ceilometer-keystone-admin-password
```

## Install Ceilometer

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

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Ceilometer installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/ceilometer/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

### Deploy Ceilometer helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm
helm upgrade --install ceilometer ./ceilometer \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/helm-configs/ceilometer/ceilometer-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ceilometer.password="$(kubectl --namespace openstack get secret ceilometer-keystone-admin-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.test.password="$(kubectl --namespace openstack get secret ceilometer-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.username="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.ceilometer.password="$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.ceilometer.oslo_messaging_notifications.transport_url="\
rabbit://ceilometer:$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer"\
    --set conf.ceilometer.notification.messaging_urls.values="{\
rabbit://ceilometer:$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer,\
rabbit://cinder:$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/cinder,\
rabbit://glance:$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/glance,\
rabbit://heat:$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/heat,\
rabbit://keystone:$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/keystone,\
rabbit://neutron:$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/neutron,\
rabbit://nova:$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/nova}"
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

## Verify Ceilometer Workers

As there is no Ceilometer API, we will do a quick validation against the
Gnocchi API via a series of `openstack metric` commands to confirm that
Ceilometer workers are ingesting metric and event data then persisting them
storage.

### Verify metric resource types exist

The Ceilomter db-sync job will create the various resource types in Gnocchi.
Without them, metrics can't be stored, so let's verify they exist. The
output should include named resource types and some attributes for resources
like `instance`, `instance_disk`, `network`, `volume`, etc.

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource-type list
```

### Verify metric resources

Confirm that resources are populating in Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource list
```

### Verify metrics

Confirm that metrics can be retrieved from Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric list
```
