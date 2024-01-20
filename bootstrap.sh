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

source scripts/lib/functions.sh

# Which config to bootstrap
test -f "${GENESTACK_CONFIG}/product" 2>/dev/null && export GENESTACK_PRODUCT=$(head -n1 ${GENESTACK_CONFIG}/product)
export GENESTACK_PRODUCT=${GENESTACK_PRODUCT:-openstack-enterprise}

set -e

success "Environment variables:"
env |egrep '^(SUDO|RPC_|ANSIBLE_|GENESTACK_|K8S|CONTAINER_|OPENSTACK_|OSH_)' | sort -u

success "Installing base packages (git):"
apt update

DEBIAN_FRONTEND=noninteractive \
  apt-get -o "Dpkg::Options::=--force-confdef" \
          -o "Dpkg::Options::=--force-confold" \
          -qy install make git python3-pip python3-venv jq make 2>&1 > ~/genestack-base-package-install.log


if [ $? -gt 1 ]; then
  error "Check for ansible errors at ~/genestack-base-package-install.log"
else
  success "Local base OS packages installed"
fi

# Install project dependencies
success "Installing genestack dependencies"
test -L $GENESTACK_CONFIG 2>&1 || mkdir -p $GENESTACK_CONFIG

# Set config
test -f $GENESTACK_CONFIG/provider || echo $K8S_PROVIDER > $GENESTACK_CONFIG/provider
test -f $GENESTACK_CONFIG/product || echo $GENESTACK_PRODUCT > $GENESTACK_CONFIG/product
mkdir -p $GENESTACK_CONFIG/inventory/group_vars $GENESTACK_CONFIG/inventory/credentials

# Copy default k8s config
test -d $GENESTACK_PRODUCT || error "Product Config $GENESTACK_PRODUCT does not exist here"
if [ $(find $GENESTACK_CONFIG/inventory -name *.yml 2>/dev/null |wc -l) -eq 0 ]; then
  cp -r ${GENESTACK_PRODUCT}/* ${GENESTACK_CONFIG}/inventory
fi

# Prepare Ansible
python3 -m venv ~/.venvs/genestack
~/.venvs/genestack/bin/pip install pip --upgrade
source ~/.venvs/genestack/bin/activate && success "Switched to venv ~/.venvs/genestack"

pip install -r /opt/genestack/requirements.txt && success "Installed ansible package"

ansible-playbook scripts/get-ansible-collection-requirements.yml \
  -e collection_file="${ANSIBLE_COLLECTION_FILE}" -e user_collection_file="${USER_COLLECTION_FILE}"

source  /opt/genestack/scripts/genestack.rc
success "Environment sourced per /opt/genestack/scripts/genestack.rc"

message "OpenStack Release: ${OPENSTACK_RELEASE}"
message "Target OS Distro: ${CONTAINER_DISTRO_NAME}:${CONTAINER_DISTRO_VERSION}"
message "Deploy Mulinode: ${OSH_DEPLOY_MULTINODE}"

echo
