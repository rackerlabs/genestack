# Quick Start Guide

Before you can do anything we need to get the code. Because we've sold our soul to the submodule devil, you're going to need to recursively clone the repo into your location.

> Throughout the all our documentation and examples the genestack code base will be assumed to be in `/opt`.

``` shell
git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
```

## Basic Setup

The basic setup requires ansible, ansible collection and helm installed to install Kubernetes and OpenStack Helm:

The environment variable `GENESTACK_PRODUCT` is used to bootstrap specific configurations and alters playbook handling.
It is persisted at /etc/genestack/product` for subsequent executions, it only has to be used once.

``` shell
GENESTACK_PRODUCT=openstack-enterprise
#GENESTACK_PRODUCT=openstack-flex

/opt/genestack/bootstrap.sh
```

Once the bootstrap is completed the default Kubernetes provider will be configured inside `/etc/genestack/provider`

The ansible inventory is expected at `/etc/genestack/inventory`

## Prepare hosts for installation

``` shell
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/ansible/playbooks

ansible-playbook host-setup.yml
```

## Installing Kubernetes

Currently only the k8s provider kubespray is supported and included as submodule into the code base.
A default inventory file for kubespray is provided at `/etc/genestack/inventory` and must be modified.
Existing OpenStack Ansible inventory can be converted using the `/opt/genestack/scripts/convert_osa_inventory.py`
script which provides a `hosts.yml`

Once the inventory is updated and configuration altered (networking etc), the Kubernetes cluster can be initialized with

``` shell
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/submodules/kubespray

ansible-playbook cluster.yml
```
