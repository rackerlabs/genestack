#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm-infra || exit
    helm upgrade --install gnocchi ./gnocchi \
        --namespace=openstack \
        --timeout 10m \
        -f /opt/genestack/base-helm-configs/gnocchi/gnocchi-helm-overrides.yaml \
        -f /etc/genestack/helm-configs/gnocchi/gnocchi-helm-overrides.yaml \
        --set conf.ceph.admin_keyring="$(kubectl get secret --namespace rook-ceph rook-ceph-admin-keyring -o jsonpath='{.data.keyring}' | base64 -d)" \
        --set conf.gnocchi.keystone_authtoken.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.identity.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-db-password -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_db_postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgres.postgres-cluster.credentials.postgresql.acid.zalan.do -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_db_postgresql.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-pgsql-password -o jsonpath='{.data.password}' | base64 -d)" \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args gnocchi/overlay "$@"
popd || exit
