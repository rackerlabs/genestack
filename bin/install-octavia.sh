#!/bin/bash
pushd /opt/genestack/submodules/openstack-helm || exit
    helm upgrade --install octavia ./octavia \
        --namespace=openstack \
        --timeout 120m \
        -f /etc/genestack/helm-configs/octavia/octavia-helm-overrides.yaml \
        --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.identity.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-admin -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
        --set endpoints.oslo_db.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_messaging.auth.octavia.password="$(kubectl --namespace openstack get secret octavia-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
        --set endpoints.oslo_cache.auth.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set conf.octavia.keystone_authtoken.memcache_secret_key="$(kubectl --namespace openstack get secret os-memcached -o jsonpath='{.data.memcache_secret_key}' | base64 -d)" \
        --set conf.octavia.database.slave_connection="mysql+pymysql://octavia:$(kubectl --namespace openstack get secret octavia-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/octavia" \
        --set conf.octavia.certificates.ca_private_key_passphrase="$(kubectl --namespace openstack get secret octavia-certificates -o jsonpath='{.data.password}' | base64 -d)" \
        --set conf.octavia.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
        --set conf.octavia.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args octavia/overlay "$@"
popd || exit
