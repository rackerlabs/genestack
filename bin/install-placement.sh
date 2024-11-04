#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm || exit
  helm upgrade --install placement ./placement --namespace=openstack \
    --namespace=openstack \
      --timeout 120m \
      -f /etc/genestack/helm-configs/placement/placement-helm-overrides.yaml \
      --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
      --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
      --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
      --set conf.placement.keystone_authtoken.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
      --set conf.placement.placement_database.slave_connection="mysql+pymysql://placement:$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/placement" \
      --post-renderer /etc/genestack/kustomize/kustomize.sh \
      --post-renderer-args placement/base "$@"
popd || exit
