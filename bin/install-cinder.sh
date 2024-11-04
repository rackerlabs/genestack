#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm
  helm upgrade --install cinder ./cinder \
    --namespace=openstack \
      --timeout 120m \
      -f /etc/genestack/helm-configs/cinder/cinder-helm-overrides.yaml \
      --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
      --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
      --set conf.cinder.keystone_authtoken.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
      --set conf.cinder.database.slave_connection="mysql+pymysql://cinder:$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/cinder" \
      --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
      --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
      --post-renderer /etc/genestack/kustomize/kustomize.sh \
      --post-renderer-args cinder/base $@
popd
