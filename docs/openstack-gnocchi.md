# Deploy Gnocchi

## Create Secrets

``` shell
kubectl --namespace openstack create secret generic gnocchi-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic gnocchi-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic gnocchi-pgsql-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

## Create ceph-etc configmap

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

## Verify the ceph-etc configmap is sane

Below is an example of what you're looking for to verify the configmap was
created as expected - a CSV of the mon hosts, colon seperated with default
mon port, 6789.

``` shell
(genestack) root@openstack-flex-launcher:/opt/genestack# kubectl get configmap -n openstack ceph-etc -o "jsonpath={.data['ceph\.conf']}"
[global]
mon_host = 172.31.3.7:6789,172.31.1.112:6789,172.31.0.46:6789
```

## Run the package deployment

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
