#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/placement"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/placement/placement-helm-overrides.yaml"

pushd /opt/genestack/submodules/openstack-helm || exit 1

HELM_CMD="helm upgrade --install placement ./placement \
    --namespace=openstack \
    --timeout 120m"

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

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.placement.password=\"\$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.placement.password=\"\$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.nova_api.password=\"\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set conf.placement.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.placement.placement_database.slave_connection=\"mysql+pymysql://placement:\$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/placement\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args placement/overlay $*"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"

popd || exit 1
