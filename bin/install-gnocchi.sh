#!/bin/bash
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install gnocchi ./gnocchi \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/base-helm-configs/gnocchi/gnocchi-helm-overrides.yaml \
    --set conf.ceph.admin_keyring="$(kubectl get secret --namespace rook-ceph rook-ceph-admin-keyring -o jsonpath='{.data.keyring}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-pgsql-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/base-kustomize/kustomize.sh \
    --post-renderer-args gnocchi/base
