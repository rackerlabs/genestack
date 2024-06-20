# Deploy Keystone

[![asciicast](https://asciinema.org/a/629802.svg)](https://asciinema.org/a/629802)

## Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic keystone-rabbitmq-password \
        --type Opaque \
        --from-literal=username="keystone" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-credential-keys \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

## Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.keystone.database.slave_connection="mysql+pymysql://keystone:$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/keystone" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args keystone/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

!!! note

    The image used here allows the system to run with RXT global authentication federation. The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /opt/genestack/manifests/utils/utils-openstack-client-admin.yaml
```

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack user list
```
