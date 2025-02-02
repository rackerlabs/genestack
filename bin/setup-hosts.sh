#!/bin/bash
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/ansible/playbooks
ansible-playbook host-setup.yml
cd /opt/genestack/submodules/kubespray
ansible-playbook cluster.yml
