#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/nova"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/nova/nova-helm-overrides.yaml"

HELM_CMD="helm upgrade --install nova openstack-helm/nova --version 2024.2.555+13651f45-628a320c \
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

HELM_CMD+=" --set conf.nova.neutron.metadata_proxy_shared_secret=\"\$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.neutron.password=\"\$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.ironic.password=\"\$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.placement.password=\"\$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.cinder.password=\"\$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db_api.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db_api.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db_cell0.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db_cell0.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.nova.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.nova.database.slave_connection=\"mysql+pymysql://nova:\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova\""
HELM_CMD+=" --set conf.nova.api_database.slave_connection=\"mysql+pymysql://nova:\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova_api\""
HELM_CMD+=" --set conf.nova.cell0_database.slave_connection=\"mysql+pymysql://nova:\$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova_cell0\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set network.ssh.public_key=\"\$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.public_key}' | base64 -d)\"\$'\n'"
HELM_CMD+=" --set network.ssh.private_key=\"\$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.private_key}' | base64 -d)\"\$'\n'"

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args nova/overlay $*"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
