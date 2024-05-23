# Quick Start Guide

Before you can do anything we need to get the code. Because we've sold our soul to the submodule devil, you're going to need to recursively clone the repo into your location.

!!! note

    Throughout the all our documentation and examples the genestack code base will be assumed to be in `/opt`.

``` shell
git clone --recurse-submodules -j4 https://github.com/rackerlabs/genestack /opt/genestack
```

## Basic Setup

The basic setup requires ansible, ansible collection and helm installed to install Kubernetes and OpenStack Helm:

The environment variable `GENESTACK_PRODUCT` is used to bootstrap specific configurations and alters playbook handling.
It is persisted at /etc/genestack/product` for subsequent executions, it only has to be used once.

``` shell
export GENESTACK_PRODUCT=openstack-enterprise
#GENESTACK_PRODUCT=openstack-flex

/opt/genestack/bootstrap.sh
```

!!! tip

    If running this command with `sudo`, be sure to run with `-E`. `sudo -E /opt/genestack/bootstrap.sh`. This will ensure your active environment is passed into the bootstrap command.

Once the bootstrap is completed the default Kubernetes provider will be configured inside `/etc/genestack/provider`

The ansible inventory is expected at `/etc/genestack/inventory`
