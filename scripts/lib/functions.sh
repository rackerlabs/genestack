#!/usr/bin/env bash

# Copyright 2024-Present, Rackspace Technology, Inc.
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

# Globals
source /opt/genestack/scripts/genestack.rc

export SUDO_CMD=""
sudo -l |grep -q NOPASSWD && SUDO_CMD="/usr/bin/sudo -n "

test -f ~/.rackspace/datacenter && export RAX_DC="$(cat ~/.rackspace/datacenter |tr '[:upper:]' '[:lower:]')"
test -f /etc/openstack_deploy/openstack_inventory.json && export RPC_CONFIG_IN_PLACE=true || export RPC_CONFIG_IN_PLACE=false


 # Global functions
function success {
  echo -e "\n\n\x1B[32m>> $1\x1B[39m"
}

function error {
  >&2 echo -e "\n\n\x1B[31m>> $1\x1B[39m"
  exit 1
}

function message {
  echo -n -e "\n\x1B[32m$1\x1B[39m"
}
