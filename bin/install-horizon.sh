#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm
    helm upgrade --install horizon ./horizon \
        --namespace=openstack \
        --timeout 120m \
        -f /etc/genestack/helm-configs/horizon/horizon-helm-overrides.yaml \
        --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set conf.horizon.local_settings.config.horizon_secret_key="$(kubectl --namespace openstack get secret horizon-secret-key -o jsonpath='{.data.root-password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.horizon.password="$(kubectl --namespace openstack get secret horizon-db-password -o jsonpath='{.data.password}' | base64 -d)" \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args horizon/base $@
popd
