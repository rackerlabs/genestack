#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/cinder"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/cinder/cinder-helm-overrides.yaml"

pushd /opt/genestack/submodules/openstack-helm || exit 1

HELM_CMD="helm upgrade --install cinder ./cinder \
    --namespace=openstack \
    --timeout 120m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.cinder.password=\"\$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.cinder.password=\"\$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.cinder.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.cinder.database.slave_connection=\"mysql+pymysql://cinder:\$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/cinder\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.cinder.password=\"\$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args cinder/overlay $*"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"

popd || exit 1
