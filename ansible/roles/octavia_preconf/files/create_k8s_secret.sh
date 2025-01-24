#!/bin/bash

# obtain the values for cert and keys
# from the ansible tasks; these will
# then be used to create the secret

set -xe

SERVER_CA=$1
SERVER_CA_KEY=$2
CLIENT_CA=$3
CLIENT_KEY_CERT=$4

function encod_base64()
{
  local file_path=$1
  # shellcheck disable=SC2002
  cat "$file_path" | base64 -w0 | tr -d '\n'
}

cat <<EOF> /tmp/k8s_secret.yml
---
apiVersion: v1
kind: Secret
metadata:
  name: octavia-certs
  namespace: openstack
type: Opaque
data:
  server_ca.cert.pem: $(encod_base64 "$SERVER_CA")
  server_ca.key.pem: $(encod_base64 "$SERVER_CA_KEY")
  client_ca.cert.pem: $(encod_base64 "$CLIENT_CA")
  client.key-and-cert.pem: $(encod_base64 "$CLIENT_KEY_CERT")
EOF
