#!/bin/bash
# shellcheck disable=SC2086

usage() {
    echo "Usage: $0 [--region <region> default: RegionOne]"
    exit 1
}

region="RegionOne"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            usage
            ;;
        -h)
            usage
            ;;
        --region)
            region="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
done

# Check if the region argument is provided
if [ -z "$region" ]; then
    usage
fi

generate_password() {
    < /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32}
}

mariadb_root_password=$(generate_password 32)
mariadb_password=$(generate_password 32)
keystone_rabbitmq_password=$(generate_password 64)
keystone_db_password=$(generate_password 32)
keystone_admin_password=$(generate_password 32)
keystone_credential_keys_password=$(generate_password 32)
glance_rabbitmq_password=$(generate_password 64)
glance_db_password=$(generate_password 32)
glance_admin_password=$(generate_password 32)
heat_rabbitmq_password=$(generate_password 64)
heat_db_password=$(generate_password 32)
heat_admin_password=$(generate_password 32)
heat_trustee_password=$(generate_password 32)
heat_stack_user_password=$(generate_password 32)
cinder_rabbitmq_password=$(generate_password 64)
cinder_db_password=$(generate_password 32)
cinder_admin_password=$(generate_password 32)
metadata_shared_secret_password=$(generate_password 32)
placement_db_password=$(generate_password 32)
placement_admin_password=$(generate_password 32)
nova_db_password=$(generate_password 32)
nova_admin_password=$(generate_password 32)
nova_rabbitmq_password=$(generate_password 64)
nova_ssh_public_key=$(ssh-keygen -qt ed25519 -N '' -C "nova_ssh" -f nova_ssh_key && cat nova_ssh_key.pub)
nova_ssh_private_key=$(cat nova_ssh_key)
ironic_admin_password=$(generate_password 32)
designate_admin_password=$(generate_password 32)
neutron_rabbitmq_password=$(generate_password 64)
neutron_db_password=$(generate_password 32)
neutron_admin_password=$(generate_password 32)
horizon_secret_key_password=$(generate_password 64)
horizon_db_password=$(generate_password 32)
skyline_service_password=$(generate_password 32)
skyline_db_password=$(generate_password 32)
skyline_secret_key_password=$(generate_password 32)
octavia_rabbitmq_password=$(generate_password 64)
octavia_db_password=$(generate_password 32)
octavia_admin_password=$(generate_password 32)
octavia_certificates_password=$(generate_password 32)
barbican_rabbitmq_password=$(generate_password 64)
barbican_db_password=$(generate_password 32)
barbican_admin_password=$(generate_password 32)
magnum_rabbitmq_password=$(generate_password 64)
magnum_db_password=$(generate_password 32)
magnum_admin_password=$(generate_password 32)
postgresql_identity_admin_password=$(generate_password 32)
postgresql_db_admin_password=$(generate_password 32)
postgresql_db_exporter_password=$(generate_password 32)
postgresql_db_audit_password=$(generate_password 32)
gnocchi_admin_password=$(generate_password 32)
gnocchi_db_password=$(generate_password 32)
gnocchi_pgsql_password=$(generate_password 32)
ceilometer_keystone_admin_password=$(generate_password 32)
ceilometer_keystone_test_password=$(generate_password 32)
ceilometer_rabbitmq_password=$(generate_password 32)
memcached_shared_secret=$(generate_password 32)
grafana_secret=$(generate_password 32)
grafana_root_secret=$(generate_password 32)

OUTPUT_FILE="/etc/genestack/kubesecrets.yaml"

cat <<EOF > $OUTPUT_FILE
---
apiVersion: v1
kind: Secret
metadata:
  name: mariadb
  namespace: openstack
type: Opaque
data:
  root-password: $(echo -n $mariadb_root_password | base64 -w0)
  password: $(echo -n $mariadb_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: keystone-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "keystone" | base64)
  password: $(echo -n $keystone_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: keystone-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $keystone_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: keystone-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $keystone_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: keystone-credential-keys
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $keystone_credential_keys_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: glance-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "glance" | base64)
  password: $(echo -n $glance_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: glance-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $glance_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: glance-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $glance_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: heat-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "heat" | base64)
  password: $(echo -n $heat_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: heat-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $heat_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: heat-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $heat_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: heat-trustee
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $heat_trustee_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: heat-stack-user
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $heat_stack_user_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: cinder-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "cinder" | base64)
  password: $(echo -n $cinder_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: cinder-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $cinder_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: cinder-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $cinder_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: metadata-shared-secret
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $metadata_shared_secret_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: placement-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $placement_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: placement-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $placement_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: nova-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $nova_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: nova-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $nova_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: nova-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "nova" | base64)
  password: $(echo -n $nova_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: nova-ssh-keypair
  namespace: openstack
type: Opaque
data:
  public_key: $(echo -n $nova_ssh_public_key | base64 -w0)
  private_key: $(echo -n $nova_ssh_private_key | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: ironic-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $ironic_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: designate-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $designate_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "neutron" | base64)
  password: $(echo -n $neutron_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $neutron_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $neutron_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: horizon-secrete-key
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "horizon" | base64)
  password: $(echo -n $horizon_secret_key_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: horizon-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $horizon_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: skyline-apiserver-secrets
  namespace: openstack
type: Opaque
data:
  service-username: $(echo -n "skyline" | base64)
  service-password: $(echo -n $skyline_service_password | base64 -w0)
  service-domain: $(echo -n "service" | base64)
  service-project: $(echo -n "service" | base64)
  service-project-domain: $(echo -n "service" | base64)
  db-endpoint: $(echo -n "mariadb-cluster-primary.openstack.svc.cluster.local" | base64 -w0)
  db-name: $(echo -n "skyline" | base64)
  db-username: $(echo -n "skyline" | base64)
  db-password: $(echo -n $skyline_db_password | base64 -w0)
  secret-key: $(echo -n $skyline_secret_key_password | base64 -w0)
  keystone-endpoint: $(echo -n "http://keystone-api.openstack.svc.cluster.local:5000/v3" | base64 -w0)
  keystone-username: $(echo -n "skyline" | base64)
  default-region: $(echo -n "$region" | base64)
  prometheus_basic_auth_password: $(echo -n "" | base64)
  prometheus_basic_auth_user: $(echo -n "" | base64)
  prometheus_enable_basic_auth: $(echo -n "false" | base64)
  prometheus_endpoint: $(echo -n "http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090" | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: octavia-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "octavia" | base64)
  password: $(echo -n $octavia_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: octavia-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $octavia_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: octavia-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $octavia_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: octavia-certificates
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $octavia_certificates_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: barbican-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "barbican" | base64)
  password: $(echo -n $barbican_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: barbican-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $barbican_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: barbican-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $barbican_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: magnum-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "magnum" | base64)
  password: $(echo -n $magnum_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: magnum-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $magnum_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: magnum-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $magnum_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-identity-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $postgresql_identity_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-db-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $postgresql_db_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-db-exporter
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $postgresql_db_exporter_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-db-audit
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $postgresql_db_audit_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: gnocchi-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $gnocchi_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: gnocchi-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $gnocchi_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: gnocchi-pgsql-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $gnocchi_pgsql_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: ceilometer-keystone-admin-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $ceilometer_keystone_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: ceilometer-keystone-test-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $ceilometer_keystone_test_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: ceilometer-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "ceilometer" | base64)
  password: $(echo -n $ceilometer_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: os-memcached
  namespace: openstack
type: Opaque
data:
  memcache_secret_key: $(echo -n $memcached_shared_secret | base64 -w0)
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: grafana
    name: grafana
  name: grafana
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-db
  namespace: grafana
type: Opaque
data:
  password: $(echo -n $grafana_secret | base64 -w0)
  root-password: $(echo -n $grafana_root_secret | base64 -w0)
  username: $(echo -n grafana | base64 -w0)
EOF

rm nova_ssh_key nova_ssh_key.pub
chmod 0640 ${OUTPUT_FILE}
echo "Secrets YAML file created as ${OUTPUT_FILE}"
