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
test -f "$GENESTACK_CONFIG/provider" || echo "${K8S_PROVIDER}" > "${GENESTACK_CONFIG}/provider"
mkdir -p "$GENESTACK_CONFIG/inventory/group_vars" "${GENESTACK_CONFIG}/inventory/credentials"

# Copy default k8s config
PRODUCT_DIR="ansible/inventory/genestack"
if [ "$(find "${GENESTACK_CONFIG}/inventory" -name \*.yaml -o -name \*.yml 2>/dev/null | wc -l)" -eq 0 ]; then
  cp -r "${PRODUCT_DIR}"/* "${GENESTACK_CONFIG}/inventory"
fi

# Copy gateway-api example configs
test -d "$GENESTACK_CONFIG/gateway-api" || cp -a "${BASEDIR}/etc/gateway-api" "$GENESTACK_CONFIG"/

# Create venv and prepare Ansible
python3 -m venv "${HOME}/.venvs/genestack"
"${HOME}/.venvs/genestack/bin/pip" install pip --upgrade
source "${HOME}/.venvs/genestack/bin/activate" && success "Switched to venv ~/.venvs/genestack"
pip install -r "${BASEDIR}/requirements.txt" && success "Installed ansible package"
ansible-playbook "${BASEDIR}/scripts/get-ansible-collection-requirements.yml" \
  -e collections_file="${ANSIBLE_COLLECTION_FILE}" \
  -e user_collections_file="${USER_COLLECTION_FILE}"

source  "${BASEDIR}/scripts/genestack.rc"
success "Environment sourced per ${BASEDIR}/scripts/genestack.rc"

message "OpenStack Release: ${OPENSTACK_RELEASE}"
message "Target OS Distro: ${CONTAINER_DISTRO_NAME}:${CONTAINER_DISTRO_VERSION}"
message "Deploy Mulinode: ${OSH_DEPLOY_MULTINODE}"

# Ensure /etc/genestack exists
mkdir -p /etc/genestack

# Ensure each service from /opt/genestack/base-kustomize
# exists in /etc/genestack/kustomize and symlink
# all the sub-directories
base_source_dir="/opt/genestack/base-kustomize"
base_target_dir="/etc/genestack/kustomize"

for service in "$base_source_dir"/*; do
  service_name=$(basename "$service")
  if [ -d "$service" ]; then
    # Check if the service has subdirectories
    if [ "$(find "$service" -mindepth 1 -type d | wc -l)" -eq 0 ]; then
      # If no subdirectories, symlink the service directly under the target dir
      if [ ! -L "$base_target_dir/$service_name" ]; then
        ln -s "$service" "$base_target_dir/$service_name"
        success "Created symlink for $service_name directly under $base_target_dir"
      else
        message "Symlink for $service_name already exists directly under $base_target_dir"
      fi
    else
      if [ -d "$base_target_dir/$service_name" ]; then
        message "$base_target_dir/$service_name already exists"
      else
        message "Creating $base_target_dir/$service_name"
        mkdir -p "$base_target_dir/$service_name"
      fi
      for item in "$service"/*; do
        item_name=$(basename "$item")
        if [ ! -L "$base_target_dir/$service_name/$item_name" ]; then
          ln -s "$item" "$base_target_dir/$service_name/$item_name"
          success "Created symlink for $service_name/$item_name"
        else
          message "Symlink for $service_name/$item_name already exists"
        fi
      done
    fi
  else
    message "$service_name is not a directory, skipping..."
  fi
done

# Symlink /opt/genestack/base-kustomize/kustomize.sh to
# /etc/genestack/kustomize/kustomize.sh
ln -sf $base_source_dir/kustomize.sh $base_target_dir/kustomize.sh

# Ensure kustomization.yaml exists in each
# service base/overlay directory
# Directory paths
overlay_target_dir="/etc/genestack/kustomize"

kustomization_content="apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
"

for service in "$overlay_target_dir"/*; do
  if [ -d "$service" ] && [ -d "$service/base" ]; then
    overlay_path="${service}/overlay"

    if [ ! -d "$overlay_path" ]; then
      mkdir -p "$overlay_path"
      success "Creating overlay path $overlay_path"
    fi

    if [ ! -f "$overlay_path/kustomization.yaml" ]; then
      echo "$kustomization_content" > "$overlay_path/kustomization.yaml"
      success "Created overlay and kustomization.yaml for $(basename "$service")"
    else
      message "kustomization.yaml already exists for $(basename "$service"), skipping..."
    fi
  else
    message "No base directory for $(basename "$service"), skipping..."
  fi
done

#!/bin/bash

if [ ! -d "/etc/genestack/helm-configs" ]; then
  mkdir -p /etc/genestack/helm-configs
  success "Created /etc/genestack/helm-configs"
else
  message "/etc/genestack/helm-configs already exists, skipping creation."
fi

for src_dir in /opt/genestack/base-helm-configs/*; do
  if [ -d "$src_dir" ]; then
    dir_name=$(basename "$src_dir")
    dest_dir="/etc/genestack/helm-configs/$dir_name"
    if [ ! -d "$dest_dir" ]; then
      mkdir -p "$dest_dir"
      success "Created $dest_dir"
    else
      message "$dest_dir already exists, skipping creation."
    fi
  fi
done

if [ ! -d "/etc/genestack/helm-configs/global_overrides" ]; then
  mkdir -p /etc/genestack/helm-configs/global_overrides
  echo "Created /etc/genestack/helm-configs/global_overrides"
else
  echo "/etc/genestack/helm-configs/global_overrides already exists, skipping creation."
fi

# Copy manifests if it does not already exist
if [ ! -d "/etc/genestack/manifests" ]; then
  cp -r /opt/genestack/manifests /etc/genestack/
  success "Copied manifests to /etc/genestack/"
else
  message "manifests already exists in /etc/genestack, skipping copy."
fi

echo
