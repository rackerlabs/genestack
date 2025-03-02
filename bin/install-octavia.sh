#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/octavia"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/octavia/octavia-helm-overrides.yaml"

HELM_CMD="helm upgrade --install octavia openstack-helm/octavia --version 2024.2.30+13651f45-628a320c \
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
HELM_CMD+=" --set endpoints.identity.auth.octavia.password=\"\$(kubectl --namespace openstack get secret octavia-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.admin.password=\"\$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_db.auth.octavia.password=\"\$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.octavia.password=\"\$(kubectl --namespace openstack get secret octavia-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.octavia.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.octavia.database.slave_connection=\"mysql+pymysql://octavia:\$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/octavia\""
HELM_CMD+=" --set conf.octavia.certificates.ca_private_key_passphrase=\"\$(kubectl --namespace openstack get secret octavia-certificates -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set conf.octavia.ovn.ovn_nb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""
HELM_CMD+=" --set conf.octavia.ovn.ovn_sb_connection=\"tcp:\$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args octavia/overlay $*"

helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm repo update

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"
