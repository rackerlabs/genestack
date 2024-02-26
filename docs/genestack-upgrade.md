Running a genestack upgrade is fairly simple and consists of mainly updating the `git` checkout and then running through the needed `helm` charts to deploy updated applications.

## Updating the Genestack

Change to the genestack directory.

``` shell
cd /opt/genestack
```

Fetch the latest checkout from your remote.

``` shell
git fetch origin
git rebase origin/main
```

> You may want to checkout a specific SHA or tag when running a stable environment.

Update the submodules.

``` shell
git pull --recurse-submodules
```

## Updating the genestack applications

An update is generally the same as an install. Many of the Genestack applications are governed by operators which include lifecycle management.

* When needing to run an upgrade for the infrastructure operators, consult the operator documentation to validate the steps required.
* When needing to run an upgrade for the OpenStack components, simply re-run the `helm` charts as documented in the Genestack installation process.
