# Deploy Glance

[![asciicast](https://asciinema.org/a/629806.svg)](https://asciinema.org/a/629806)

## Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic glance-rabbitmq-password \
        --type Opaque \
        --from-literal=username="glance" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic glance-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic glance-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

!!! info

    Before running the Glance deployment you should configure the backend which is defined in the `helm-configs/glance/glance-helm-overrides.yaml` file. The default is a making the assumption we're running with Ceph deployed by Rook so the backend is configured to be cephfs with multi-attach functionality. While this works great, you should consider all of the available storage backends and make the right decision for your environment.

## Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/glance/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.glance.database.slave_connection="mysql+pymysql://glance:$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-galera-secondary.openstack.svc.cluster.local:3306/glance" \
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
