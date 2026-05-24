#!/bin/bash

set -xe

cd /tmp

REGION=$1

generate_password() {
    < /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32}
}

trove_ssh_public_key=$(ssh-keygen -qt ed25519 -N '' -C "trove_ssh" -f trove_ssh_key && cat trove_ssh_key.pub)
trove_ssh_private_key=$(cat trove_ssh_key)
trove_rabbitmq_password=$(generate_password 64)
trove_db_password=$(generate_password 32)
trove_admin_password=$(generate_password 32)

OUTPUT_FILE="/tmp/trove_secrets.yml"

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
  name: trove-rabbitmq-password
  namespace: openstack
type: Opaque
data:
  username: $(echo -n "trove" | base64)
  password: $(echo -n $trove_rabbitmq_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: trove-db-password
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $trove_db_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: trove-admin
  namespace: openstack
type: Opaque
data:
  password: $(echo -n $trove_admin_password | base64 -w0)
---
apiVersion: v1
kind: Secret
metadata:
  name: trove-ssh
  namespace: openstack
  annotations:
    meta.helm.sh/release-name: trove
    meta.helm.sh/release-namespace: openstack
  labels:
    app.kubernetes.io/managed-by: Helm
type: Opaque
data:
  public-key: $(echo $trove_ssh_public_key | base64 -w0)
  private-key: $(echo "$trove_ssh_private_key" | base64 -w0)
EOF

# Clean up SSH key files
rm -f trove_ssh_key trove_ssh_key.pub
chmod 0640 ${OUTPUT_FILE}
