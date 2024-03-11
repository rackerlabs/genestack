![Genestack Logo](assets/images/genestack-cropped-small.png){ align=left : style="filter:drop-shadow(#3c3c3c 0.5rem 0.5rem 10px);" }

# What is Genestack?

Genestack is a complete operations and deployment ecosystem for Kubernetes and OpenStack. The purpose is of
this project is to allow hobbyists, operators, and cloud service providers the ability to build, scale, and
leverage Open-Infrastructure in new and exciting ways.

Genestack’s inner workings are a blend dark magic — crafted with [Kustomize](https://kustomize.io) and
[Helm](https://helm.sh). It’s like cooking with cloud. Want to spice things up? Tweak the
`kustomization.yaml` files or add those extra 'toppings' using Helm's style overrides. However, the
platform is ready to go with batteries included.

Genestack is making use of some homegrown solutions, community operators, and OpenStack-Helm. Everything
in Genestack comes together to form cloud in a new and exciting way; all built with opensource solutions
to manage cloud infrastructure in the way you need it.


## Getting Started

Before you can do anything we need to get the code. Because we've sold our soul to the submodule devil, you're going to need to recursively clone the repo into your location.

!!! info

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
