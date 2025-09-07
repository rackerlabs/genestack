#!/bin/bash

#GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
GLOBAL_OVERRIDES="/etc/genestack/helm-configs/global_overrides/endpoints.yaml"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/blazar"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/blazar/blazar-helm-overrides.yaml"

HELM_CMD="helm upgrade --install blazar openstack-helm/blazar \
    --namespace=openstack \
    --timeout 120m"

HELM_CMD+=" -f ${BASE_OVERRIDES} -f ${GLOBAL_OVERRIDES=}"

# Append YAML files from the directories
#for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
for dir in "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.blazar.password=\"$(kubectl --namespace openstack get secret blazar-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.service.password=\"$(kubectl --namespace openstack get secret blazar-keystone-service-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.test.password=\"$(kubectl --namespace openstack get secret blazar-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.blazar.password=\"$(kubectl --namespace openstack get secret blazar-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.blazar.password=\"$(kubectl --namespace openstack get secret blazar-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.blazar.keystone_authtoken.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
#HELM_CMD+=" --set conf.blazar.physical_host_plugin.blazar_password=\"$(kubectl --namespace openstack get secret blazar-keystone-service-password -o jsonpath='{.data.password}' | base64 -d)\""


HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args blazar/overlay"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"