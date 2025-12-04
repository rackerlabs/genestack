#!/usr/bin/env bash

set -e

function gitRepoVersion() {
    # Returns the current git branch name, tag, or commit hash
    echo "$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match 2>/dev/null || git rev-parse HEAD)"
}

echo "This script will help you upgrade your Kubernetes cluster managed by Kubespray."

# Ask the user for the target Kubernetes version
read -p "Enter the target Kubernetes version number (e.g., 1.34.0): " VERSION_NUMBER

# Confirm the version number with the user
echo "You have entered Kubernetes version number: ${VERSION_NUMBER}"

echo "Your current setup is as follows:"
# Show checkout version of Genestack and the branch being used
pushd /opt/genestack &>/dev/null
    echo "[+] Current Genestack version: $(gitRepoVersion) (SHA:$(git rev-parse HEAD))"
popd &>/dev/null

pushd /opt/genestack/submodules/kubespray &>/dev/null
    echo "[+] Current Kubespray version: $(gitRepoVersion) (SHA:$(git rev-parse HEAD))"
popd &>/dev/null

read -p "Is all of this correct? If yes type \`DOTHETHINGNOW\`: " CONFIRMATION

if [[ "$CONFIRMATION" != "DOTHETHINGNOW" ]]; then
    echo "Aborting. Please run the script again and enter the correct version number and confirmation."
    exit 1
fi

set -v

# Load Genestack environment variables
. /opt/genestack/scripts/genestack.rc

# Navigate to the Kubespray directory and perform the upgrade
pushd /opt/genestack/submodules/kubespray &>/dev/null
    echo "Gathering cluster facts"
    ansible-playbook playbooks/facts.yml --become

    echo "Upgrading cluster to Kubernetes version ${VERSION_NUMBER}"
    ansible-playbook upgrade-cluster.yml --become -e kube_version${VERSION_NUMBER} --limit "kube_control_plane:etcd"

    echo "Upgrading worker nodes to Kubernetes version ${VERSION_NUMBER}"
    ansible-playbook upgrade-cluster.yml --become -e kube_version${VERSION_NUMBER} --limit "!kube_control_plane:!etcd"
popd &>/dev/null

echo "Kubernetes cluster upgrade to version ${VERSION_NUMBER} completed successfully."

if command -v yq &>/dev/null; then
    echo "Updating Kubernetes version in inventory files"
    yq -i ".kube_version = \"${VERSION_NUMBER}\"" /etc/genestack/inventory/group_vars/k8s_cluster/k8s-cluster.yml
else
    echo "yq command not found. Please install yq to update inventory files."
    echo "update the Kubernetes version in /etc/genestack/inventory/group_vars/k8s_cluster/k8s-cluster.yml manually to complete the upgrade."
fi
