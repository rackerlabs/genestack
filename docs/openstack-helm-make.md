# OpenStack Helm

## Install Helm

While `helm` should already be installed with the **host-setup** playbook, you will need to install helm manually on nodes. There are lots of ways to install helm, check the upstream [docs](https://helm.sh/docs/intro/install/) to learn more about installing helm.

## Run `make` for our helm components

``` shell
cd /opt/genestack/submodules/openstack-helm &&
make all

cd /opt/genestack/submodules/openstack-helm-infra &&
make all
```
