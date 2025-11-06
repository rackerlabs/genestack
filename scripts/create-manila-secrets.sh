#!/bin/bash
# shellcheck disable=SC2086

usage() {
    echo "Usage: $0 [--region <region [RegionOne]>"
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

manila_ssh_public_key=$(ssh-keygen -qt ed25519 -N '' -C "manila_ssh" -f manila_ssh_key && cat manila_ssh_key.pub)
manila_ssh_private_key=$(cat manila_ssh_key)
manila_rabbitmq_password=$(generate_password 64)
manila_db_password=$(generate_password 32)
manila_admin_password=$(generate_password 32)

OUTPUT_FILE="/etc/genestack/manila-kubesecrets.yaml"

if [[ -f ${OUTPUT_FILE} ]]; then
    echo "Error: ${OUTPUT_FILE} already exists. Please remove it before running this script."
    echo "       This will replace an existing file and will lead to mass rotation, which is"
    echo "       likely not what you want to do. If you really want to break your system, please"
    echo "       make sure you know what you're doing."
    exit 99
fi

cat <<EOF > $OUTPUT_FILE
---
apiVersion: v1
kind: Secret
metadata:
  name: manila-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "manila" | base64)
  password: $(echo -n $manila_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: manila-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $manila_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: manila-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $manila_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: manila-service-keypair
  namespace: openstack
type: Opaque
data:
  public_key: $(echo -n $manila_ssh_public_key | base64 -w0)
  private_key: $(echo -n "$manila_ssh_private_key" | base64 -w0)
EOF

rm -f manila_ssh_key manila_ssh_key.pub
chmod 0640 ${OUTPUT_FILE}
echo "Secrets YAML file created as ${OUTPUT_FILE}"
