#!/usr/bin/env bash

# Copyright 2024, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
export LC_ALL=C.UTF-8
mkdir -p ~/.venvs

BASEDIR="$(dirname "$0")"
cd "${BASEDIR}" || error "Could not change to ${BASEDIR}"

source scripts/lib/functions.sh

if [[ -z "${GENESTACK_PRODUCT}" ]]; then
  exit 99
fi

# Which config to bootstrap
if test -f "${GENESTACK_CONFIG}/product" 2>/dev/null; then
  GENESTACK_PRODUCT=$(head -n1 "${GENESTACK_CONFIG}/product")
  export GENESTACK_PRODUCT
fi

set -e

success "Environment variables:"
env | grep -E '^(SUDO|RPC_|ANSIBLE_|GENESTACK_|K8S|CONTAINER_|OPENSTACK_|OSH_)' | sort -u

success "Installing base packages (git):"
apt update

DEBIAN_FRONTEND=noninteractive \
  apt-get -o "Dpkg::Options::=--force-confdef" \
          -o "Dpkg::Options::=--force-confold" \
          -qy install make git python3-pip python3-venv jq make > ~/genestack-base-package-install.log 2>&1


if [ $? -gt 1 ]; then
  error "Check for ansible errors at ~/genestack-base-package-install.log"
else
  success "Local base OS packages installed"
fi

# Install project dependencies
success "Installing genestack dependencies"
test -L "$GENESTACK_CONFIG" 2>&1 || mkdir -p "${GENESTACK_CONFIG}"

# Set config
test -f "$GENESTACK_CONFIG/provider" || echo "${K8S_PROVIDER}" > "${GENESTACK_CONFIG}"/provider
test -f "$GENESTACK_CONFIG/product" || echo "${GENESTACK_PRODUCT}" > "${GENESTACK_CONFIG}"/product
mkdir -p "$GENESTACK_CONFIG/inventory/group_vars" "${GENESTACK_CONFIG}"/inventory/credentials

# Copy default k8s config
test -d "ansible/inventory/${GENESTACK_PRODUCT}" || error "Product Config ${GENESTACK_PRODUCT} does not exist here"
PRODUCT_DIR="ansible/inventory/${GENESTACK_PRODUCT}"
# shellcheck disable=SC2086
if [ "$(find ${GENESTACK_CONFIG}/inventory -name \*.yaml -o -name \*.yml 2>/dev/null |wc -l)" -eq 0 ]; then
  cp -r "${PRODUCT_DIR}"/* "${GENESTACK_CONFIG}/inventory"
fi

# Copy gateway-api exmaple configs
test -d "$GENESTACK_CONFIG/gateway-api" || cp -a "${BASEDIR}/etc/gateway-api" "$GENESTACK_CONFIG"/

# Create venv and prepare Ansible
python3 -m venv ~/.venvs/genestack
~/.venvs/genestack/bin/pip install pip --upgrade
# shellcheck disable=SC1090
source ~/.venvs/genestack/bin/activate && success "Switched to venv ~/.venvs/genestack"
pip install -r "${BASEDIR}/requirements.txt" && success "Installed ansible package"
ansible-playbook "${BASEDIR}/scripts/get-ansible-collection-requirements.yml" \
  -e collections_file="${ANSIBLE_COLLECTION_FILE}" \
  -e user_collections_file="${USER_COLLECTION_FILE}"

source  "${BASEDIR}/scripts/genestack.rc"
success "Environment sourced per ${BASEDIR}/scripts/genestack.rc"

message "OpenStack Release: ${OPENSTACK_RELEASE}"
message "Target OS Distro: ${CONTAINER_DISTRO_NAME}:${CONTAINER_DISTRO_VERSION}"
message "Deploy Mulinode: ${OSH_DEPLOY_MULTINODE}"

echo
