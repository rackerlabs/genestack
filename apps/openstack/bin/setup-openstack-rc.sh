#!/usr/bin/env bash
set -e

function installYq() {
    export VERSION=v4.2.0
    export BINARY=yq_linux_amd64
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -q -O - | tar xz && mv ${BINARY} /usr/local/bin/yq
}

if ! yq --version 2> /dev/null; then
  echo "yq is not installed. Attempting to install yq"
  installYq
fi

USER_NAME="$(whoami)"
USER_PATH="$(getent passwd ${USER_NAME} | awk -F':' '{print $6}')"
CONFIG_PATH="${USER_PATH}/.config/openstack"
CONFIG_FILE="${CONFIG_PATH}/genestack-clouds.yaml"

mkdir -p "${CONFIG_PATH}"

cat > "${CONFIG_FILE}" <<EOF
cache:
  auth: true
  expiration_time: 3600
clouds:
  default:
    auth:
      auth_url: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)
      project_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_NAME}' | base64 -d)
      tenant_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
      project_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_DOMAIN_NAME}' | base64 -d)
      username: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USERNAME}' | base64 -d)
      password: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)
      user_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
    region_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_REGION_NAME}' | base64 -d)
    interface: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_INTERFACE}' | base64 -d)
    identity_api_version: "3"
EOF

if [ -f "${CONFIG_PATH}/clouds.yaml" ]; then
    /usr/local/bin/yq eval-all 'select(filename == "'"${CONFIG_PATH}/clouds.yaml"'") * select(filename == "'"${CONFIG_FILE}"'")' \
    "${CONFIG_FILE}" \
    "${CONFIG_PATH}/clouds.yaml" | tee "${CONFIG_PATH}/clouds.yaml.tmp"
    mv "${CONFIG_PATH}/clouds.yaml.tmp" "${CONFIG_PATH}/clouds.yaml"
    rm "${CONFIG_FILE}"
else
    mv "${CONFIG_FILE}" "${CONFIG_PATH}/clouds.yaml"
fi

chown -R "${USER_NAME}:${USER_NAME}" "${CONFIG_PATH}"
