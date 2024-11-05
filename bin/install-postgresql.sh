#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm-infra || exit
helm upgrade --install postgresql ./postgresql \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/base-helm-configs/postgresql/postgresql-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.postgresql.password="$(kubectl --namespace openstack get secret postgresql-identity-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.exporter.password="$(kubectl --namespace openstack get secret postgresql-db-exporter -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.audit.password="$(kubectl --namespace openstack get secret postgresql-db-audit -o jsonpath='{.data.password}' | base64 -d)"
popd || exit
