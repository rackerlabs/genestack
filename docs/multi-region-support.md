# Supporting multiple regions with Genestack

Genestack is fairly simple to get started with by just pulling down the code and following the basic set-up documentation with the base config files but there are instances where your deployment may get a bit more complicated.
Genestack provides a reasonably sane set of base configs with default values that configure infrastructure and openstack services utilizing `helm` and `kustomize` and this works great for a simple lab setup or even a single production region.
When it comes to supporting many regions with various different values across them a single set of configs just won't suffice.

Below we'll discuss one way to better structure, version and maintain a multi-region genestack deployment.

## Overview

Firstly, we'll note that genestack is currently setup to run `helm` and `kustomize` commands from the `base-helm-configs` and `base-kustomize` directories.
These base config directories provide a sane set of defaults that can be easily applied to a lab type setup for testing purposes. Using the `aio-example-openstack-overrides.yaml` file as an additional argument to the `helm` commands you can easily adjust the values needed.
If deploying a single region for a more production like environment we can take advantage of the `prod-aio-example-openstack-overrides.yaml` file which allows us to override the various configs with production or otherwise custom values that meets the needs of our deployment.

These examples allow us to adjust and override the default `helm` values for a single deployment, or potentially multiple deployments that have identical requirements but this doesn't help us with multiple deployments that have various differences that we'd like to maintain, track and update easily.

With that in mind we'll discuss a suggested workflow to help resolve those concerns.

## Multi-region workflow

For this example workflow we'll work under the assumption that we have two regions with differing configs that we want to maintain and version control. The two regions in this example will be named as `sjc` and `dfw`.
Keep in mind that this could also apply to staging or dev environments where we'd use something like `sjc` and `sjc-staging`, but for this example we'll treat it as two different regions.

So, up to this point we've followed the documentation and cloned the genestack repo which was placed in `/opt/genestack` and our primary genestack config directory is found in `/etc/genestack`. The config directory, `/etc/genestack` is primarily where
our inventory and bootstrap type configs are found. We will make use of `/etc/genstack` for our regional overrides as well.

For this workflow we want to utilize a git repo to store our changes and custom configs. We also want to clearly define regional specific directories within the repo that will contain everything from the custom inventory to our helm config overrides.
The structure may look something like:

!!! example
    ```
    ├── my-genestack-configs
    │  ├── region1
    │  │  ├── inventory
    │  │  │  ├── inventory.yaml
    │  │  ├── helm-configs
    │  │  │  ├── nova
    │  │  │  │  ├── region1-custom-nova-helm-overrides.yaml
    │  ├── region2
    │  │  ├── inventory
    │  │  │  ├── -inventory.yaml
    │  │  ├── helm-configs
    │  │  │  ├── nova
    │  │  │  │  ├── region2-custom-nova-helm-overrides.yaml
    └── .gitignore
    ```

The above example is just that and is kept short just to give an idea of what we'll be working with. You may have many additional openstack services you need to override and may decided to adjust the structure in your own way as needed.

The inventory noted above is what's used to deploy genestack infrastructure and bootstrapping and is also specific to the region so we'll want to maitain that in a similar fashion to our custom helm configs.
For our needs here we can copy the example found in `/opt/genestack/ansible/inventory/inventory.yaml.example`.

#### Create a repo

If you have yet to do so, create a github repository, we'll call it `my-genestack-configs` for this example. We are creating a repo in order to better maintain and version control our custom changes.

See [Create a repo](https://docs.github.com/en/repositories/creating-and-managing-repositories/quickstart-for-repositories) for more information.

!!! tip
    You may opt to not create a repo and simply keep it local but the directory structure and workflow will be the same for this example

With the repo created and cloned to somewhere like `/opt/my-genestack-configs` we can then create the directory structure as noted above and add our custom helm overrides.

#### Creating custom overrides

We're going to keep the examples very simple but just about everything found in the base-helm-configs can be overriden as you see fit.
For our example we just want to override the cpu_allocation as they are different between the two regions.

Create the override files within the respective structure as noted above with the contents of:

!!! example "region1-custom-nova-helm-overrides.yaml"
    ```
    conf:
      nova:
        DEFAULT:
          cpu_allocation_ratio: 8.0
    ```

!!! example "region2-custom-nova-helm-overrides.yaml"
    ```
    conf:
      nova:
        DEFAULT:
          cpu_allocation_ratio: 4.0
    ```

We now have the directory structure and override files needed so now we can run our helm upgrades!

#### Symlink our repo

Before we run the helm commands we'd like to make things a bit cleaner and also compatible with ansible/kubespray bootstrapping and infrastructure installation.
To do that, we'll simply symlink our regional named directory that we created above to `/etc/genestack`.

For the rest of the workflow example we'll be working with the `sjc` environment. The same instructions would apply for the different regions.

!!! example "symlink the repo"
    ``` shell
    ln -s /opt/my-genestack-configs/region1 /etc/genestack
    ```

This will make our `/etc/genestack` directory look like:

!!! example "/etc/genestack/"
    ```
    ├── inventory
    │  │  ├── inventory.yaml
    ├── helm-configs
    │  ├── nova
    │  │  ├── region1-custom-nova-helm-overrides.yaml
    ```

#### Running helm

These instructions apply to all the openstack services, we are focusing on nova here. In our deployment guide we can find [compute kit installation](openstack-compute-kit.md).

Everything there will be reused, especially if we haven't set things up prior, the difference for this multi-region workflow example is that we'll be adding an additional override file to the command.

Looking at [Deploy Nova](openstack-compute-kit.md) in the compute kit installation documentation we see the `helm upgrade` command. You'll notice it has a single `-f` flag pointing to our `base-helm-configs` at `-f /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml`.
We're going to simply add another `-f` flag below that one to include our overrides. Helm will see this and apply the values in order in the arguments. In otherwords, the second `-f` flag will override anything provided in the first.

So, our helm command that we'll run against sjc will now look like:

``` shell
/opt/genestack/bin/install-nova.sh -f /etc/genestack/helm-configs/nova/region1-nova-helm-overrides.yaml
```

Like mentioned above the only difference here is the additional flag to include our custom override and that's it, we can now version custom changes while maintaining upstream parity across many regions and/or staging envorinments!

## Wrap-up

This is a simple example workflow to handle multi-region deployments and may not work for every case please adjust anything in this example as you see fit and keep on stacking!
