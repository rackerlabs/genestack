#!/bin/bash
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/ansible/playbooks || exit 1
ansible-playbook host-setup.yml
cd /opt/genestack/submodules/kubespray || exit 1
ansible-playbook cluster.yml
