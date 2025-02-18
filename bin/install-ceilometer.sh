#!/bin/bash

GLOBAL_OVERRIDES_DIR="/etc/genestack/helm-configs/global_overrides"
SERVICE_CONFIG_DIR="/etc/genestack/helm-configs/ceilometer"
BASE_OVERRIDES="/opt/genestack/base-helm-configs/ceilometer/ceilometer-helm-overrides.yaml"

pushd /opt/genestack/submodules/openstack-helm || exit 1

HELM_CMD="helm upgrade --install ceilometer ./ceilometer \
    --namespace=openstack \
    --timeout 10m"

HELM_CMD+=" -f ${BASE_OVERRIDES}"

# Append any additional YAML override files from the specified directories
for dir in "$GLOBAL_OVERRIDES_DIR" "$SERVICE_CONFIG_DIR"; do
    if compgen -G "${dir}/*.yaml" > /dev/null; then
        for yaml_file in "${dir}"/*.yaml; do
            HELM_CMD+=" -f ${yaml_file}"
        done
    fi
done

HELM_CMD+=" --set endpoints.identity.auth.admin.password=\"\$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.ceilometer.password=\"\$(kubectl --namespace openstack get secret ceilometer-keystone-admin-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.identity.auth.test.password=\"\$(kubectl --namespace openstack get secret ceilometer-keystone-test-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.username=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.admin.password=\"\$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_messaging.auth.ceilometer.password=\"\$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)\""
HELM_CMD+=" --set endpoints.oslo_cache.auth.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""
HELM_CMD+=" --set conf.ceilometer.keystone_authtoken.memcache_secret_key=\"\$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)\""

HELM_CMD+=" --set conf.ceilometer.oslo_messaging.transport_url=\"rabbit://ceilometer:\$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer\""

HELM_CMD+=" --set conf.ceilometer.notification.messaging_urls.values=\"{\
rabbit://ceilometer:\$(kubectl --namespace openstack get secret ceilometer-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/ceilometer,\
rabbit://cinder:\$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/cinder,\
rabbit://glance:\$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/glance,\
rabbit://heat:\$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/heat,\
rabbit://keystone:\$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/keystone,\
rabbit://neutron:\$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/neutron,\
rabbit://nova:\$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)@rabbitmq.openstack.svc.cluster.local:5672/nova}\""

HELM_CMD+=" --post-renderer /etc/genestack/kustomize/kustomize.sh"
HELM_CMD+=" --post-renderer-args ceilometer/overlay $*"

echo "Executing Helm command:"
echo "${HELM_CMD}"
eval "${HELM_CMD}"

popd || exit 1
