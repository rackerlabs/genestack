#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/neutron"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/neutron/neutron-helm-overrides.yaml"

HELM_CMD="helm upgrade --install neutron openstack-helm/neutron --version 2024.2.529+13651f45-628a320c \
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

HELM_CMD+=" --set conf.metadata_agent.DEFAULT.metadata_proxy_shared_secret=\"\$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set conf.ovn_metadata_agent.DEFAULT.metadata_proxy_shared_secret=\"\$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.neutron.password=\"\$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.nova.password=\"\$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.placement.password=\"\$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.designate.password=\"\$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.ironic.password=\"\$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.neutron.password=\"\$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.neutron.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.neutron.database.slave_connection=\"mysql+pymysql://neutron:\$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/neutron\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.neutron.password=\"\$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set conf.neutron.ovn.ovn_nb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""
HELM_CMD+=" --set conf.neutron.ovn.ovn_sb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""
HELM_CMD+=" --set conf.plugins.ml2_conf.ovn.ovn_nb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""
HELM_CMD+=" --set conf.plugins.ml2_conf.ovn.ovn_sb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args neutron/overlay $*"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
