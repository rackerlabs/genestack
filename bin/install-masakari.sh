#!/bin/bash
GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/masakari"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/masakari/masakari-helm-overrides.yaml"

# Read masakari version from helm-chart-versions.yaml
VERSION_FILE="/etc/genestack/helm-chart-versions.yaml"
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: helm-chart-versions.yaml not found at $VERSION_FILE"
    exit 1
fi

# Extract masakari version using grep and sed
MASAKARI_VERSION=$(grep 'masakari:' "$VERSION_FILE" | sed 's/.*masakari: *//')

if [ -z "$MASAKARI_VERSION" ]; then
    echo "Error: Could not extract masakari version from $VERSION_FILE"
    exit 1
fi

HELM_CMD="helm upgrade --install masakari openstack-helm/masakari --version ${MASAKARI_VERSION} \
    --namespace=openstack \
    --timeout 10m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
  if compgen -G "${dir}/*.yaml" > /dev/null; then
    for yaml_file in "${dir}"/*.yaml; do
      # Avoid re-adding the base override file if it appears in the service directory
      if [ "${yaml_file}" != "${BASE_OVERRIDES}" ]; then
        HELM_CMD+=" -f ${yaml_file}"
      fi
    done
  fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.masakari.password=\"$(kubectl --namespace openstack get secret masakari-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.masakari.password=\"$(kubectl --namespace openstack get secret masakari-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.masakari.keystone_authtoken.memcache_secret_key=\"$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.masakari.password=\"$(kubectl --namespace openstack get secret masakari-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args masakari/overlay"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

HELM_CMD+=" $@"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
