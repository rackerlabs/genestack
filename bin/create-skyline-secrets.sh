#!/bin/bash
# shellcheck disable=SC2086

usage() {
    echo "Usage: $0 [--region <region [RegionOne]>"
    exit 1
}

region="RegionOne"

# Parse command-line arguments
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

# Generate random password function
generate_password() {
    < /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32}
}

OUTPUT_FILE="/etc/genestack/kubesecrets.yaml"
SKYLINE_SECRETS_FILE="/etc/genestack/skylinesecrets.yaml"

# Check if skylinesecrets.yaml already exists
if [[ -f ${SKYLINE_SECRETS_FILE} ]]; then
    echo "Error: ${SKYLINE_SECRETS_FILE} already exists."
    echo "       Skyline secrets have already been generated."
    echo "       If you want to regenerate skyline secrets, please delete ${SKYLINE_SECRETS_FILE} first."
    echo "       WARNING: This will generate NEW passwords and break existing Skyline installations!"
    exit 1
fi

# Check if kubesecrets.yaml exists
if [[ ! -f ${OUTPUT_FILE} ]]; then
    echo "Error: ${OUTPUT_FILE} does not exist."
    echo "       Please run create-secrets.sh first to generate the base secrets file."
    exit 1
fi

# Generate Skyline passwords
echo "Generating new Skyline secrets..."
skyline_service_password=$(generate_password 32)
skyline_db_password=$(generate_password 32)
skyline_secret_key_password=$(generate_password 32)

# Create the Skyline secrets YAML content
SKYLINE_SECRET_CONTENT="---
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
  prometheus_endpoint: $(echo -n "http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090" | base64 -w0)"

# Write to skylinesecrets.yaml
echo "$SKYLINE_SECRET_CONTENT" > ${SKYLINE_SECRETS_FILE}
chmod 0640 ${SKYLINE_SECRETS_FILE}
echo "Created ${SKYLINE_SECRETS_FILE}"

# Check if skyline section already exists in kubesecrets.yaml
if grep -q "name: skyline-apiserver-secrets" ${OUTPUT_FILE}; then
    echo "Warning: skyline-apiserver-secrets already exists in ${OUTPUT_FILE}"
    echo "         This suggests skylinesecrets.yaml was previously generated."
    echo "         Aborting to prevent duplicate entries."
    exit 1
fi

# Append to kubesecrets.yaml
echo "$SKYLINE_SECRET_CONTENT" >> $OUTPUT_FILE

echo "Skyline secret appended to ${OUTPUT_FILE}"
echo ""
echo "✓ Successfully created ${SKYLINE_SECRETS_FILE}"
echo "✓ Successfully appended skyline secret to ${OUTPUT_FILE}"
echo ""
echo "IMPORTANT: Keep ${SKYLINE_SECRETS_FILE} safe!"
echo "           It will be used to preserve skyline secret when regenerating ${OUTPUT_FILE}"
