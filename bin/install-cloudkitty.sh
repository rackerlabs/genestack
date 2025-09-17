#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/cloudkitty"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/cloudkitty/cloudkitty-helm-overrides.yaml"

# Read cloudkitty version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract cloudkitty version using grep and sed
CLOUDKITTY_VERSION=$(grep 'cloudkitty:' "$VERSION_FILE" | sed 's/.*cloudkitty: *//')

if [ -z "$CLOUDKITTY_VERSION" ]; then
    echo "Error: Could not extract cloudkitty version from $VERSION_FILE"
    exit 1
fi

#HELM_CMD="helm upgrade --install cloudkitty openstack-helm/cloudkitty --version ${CLOUDKITTY_VERSION} \
#    --namespace=openstack \
#    --timeout 10m"

HELM_CMD="helm upgrade --install cloudkitty /opt/openstack-helm/cloudkitty \
	 --namespace=openstack \
	 --timeout 10m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.cloudkitty.password=\"\$(kubectl --namespace openstack get secret cloudkitty-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.cloudkitty.password=\"\$(kubectl --namespace openstack get secret cloudkitty-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.cloudkitty.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.cloudkitty.database.slave_connection=\"mysql+pymysql://cloudkitty:\$(kubectl --namespace openstack get secret cloudkitty-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/cloudkitty\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.cloudkitty.password=\"\$(kubectl --namespace openstack get secret cloudkitty-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args cloudkitty/overlay"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
