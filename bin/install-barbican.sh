#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm || exit
    helm upgrade --install barbican ./barbican \
        --namespace=openstack \
        --timeout 120m \
        -f /etc/genestack/helm-configs/barbican/barbican-helm-overrides.yaml \
        --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.identity.auth.barbican.password="$(kubectl --namespace openstack get secret barbican-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.barbican.password="$(kubectl --namespace openstack get secret barbican-db-password -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_messaging.auth.barbican.password="$(kubectl --namespace openstack get secret barbican-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set conf.barbican.keystone_authtoken.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args barbican/base "$@"
popd || exit
