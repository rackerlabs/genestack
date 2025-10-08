#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/zaqar"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/zaqar/zaqar-helm-overrides.yaml"

# Read zaqar version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract zaqar version using grep and sed
ZAQAR_VERSION=$(grep 'zaqar:' "$VERSION_FILE" | sed 's/.*zaqar: *//')

if [ -z "$ZAQAR_VERSION" ]; then
    echo "Error: Could not extract zaqar version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install zaqar openstack-helm/zaqar --version ${ZAQAR_VERSION} \
    --namespace=openstack \
    --timeout 120m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

# Append YAML files from the directories
for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.zaqar.password=\"$(kubectl --namespace openstack get secret zaqar-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.test.password=\"$(kubectl --namespace openstack get secret zaqar-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.zaqar.password=\"$(kubectl --namespace openstack get secret zaqar-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.zaqar.password=\"$(kubectl --namespace openstack get secret zaqar-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.zaqar.keystone_authtoken.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.zaqar.signed_url.secret_key=\"$(kubectl --namespace openstack get secret zaqar-signed-url-secret-key -o jsonpath='{.data.zaqar_signed_url_secret_key}' | base64 -d)\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args zaqar/overlay"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
