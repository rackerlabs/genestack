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
BASEDIR=${BASEDIR:-/opt/genestack}
source ${BASEDIR}/scripts/genestack.rc

export SUDO_CMD=""
sudo -l |grep -q NOPASSWD && SUDO_CMD="/usr/bin/sudo -n "

test -f ~/.rackspace/datacenter && export RAX_DC="$(cat ~/.rackspace/datacenter |tr '[:upper:]' '[:lower:]')"
test -f /etc/openstack_deploy/openstack_inventory.json && export RPC_CONFIG_IN_PLACE=true || export RPC_CONFIG_IN_PLACE=false

# Global functions

wait_for_dnf_locks() {
    local max_retries=180  # Maximum retries for dnf commands
    local retry_delay=10 # Delay between retries in seconds

    for i in $(seq 1 $max_retries); do
        if sudo dnf clean all && sudo dnf makecache; then
            echo "dnf locks released. Proceeding."
            return 0 # Indicate success
        else
            echo "dnf still locked. Retrying in $retry_delay seconds..."
            sleep $retry_delay
        fi
    done

    echo "Error: Timed out after $max_retries retries waiting for dnf to become available." >&2
    return 1 # Indicate failure
}

wait_for_apt_locks() {
    local max_wait_time=180  # Maximum time to wait in seconds
    local elapsed_time=0

    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do

        if (( elapsed_time >= max_wait_time )); then
            echo "Error: Timed out waiting for apt locks to release." >&2
            return 1 # Indicate failure
        fi

        echo "Waiting for apt locks to release..."
        sleep 5  # Wait for 5 seconds before checking again
        elapsed_time=$((elapsed_time + 5))
    done
    echo "apt locks released. Proceeding."
    return 0 # Indicate success
}

wait_for_package_manager_locks() {
    # Check if apt or dnf is the package manager
    if command -v apt-get &>/dev/null; then
        echo "Detected apt package manager."
        wait_for_apt_locks
        return $?
    elif command -v dnf &>/dev/null; then
        echo "Detected dnf package manager."
        wait_for_dnf_locks
        return $?
    else
        echo "Error: Neither apt nor dnf package manager found." >&2
        return 1
    fi
}

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
