---
hide:
  - footer
---

# TopoLVM - In Cluster

[TopoLVM](https://github.com/topolvm/topolvm) is a capacity aware storage provisioner which can make use of physical volumes.

The following steps are one way to set it up, however, consult the [documentation](https://github.com/topolvm/topolvm/blob/main/docs/getting-started.md) for a full breakdown of everything possible with TopoLVM.

## Create the target volume group on your hosts

TopoLVM requires access to a volume group on the physical host to work, which means we need to set up a volume group on our hosts. By default, TopoLVM will use the controllers as storage hosts. The genestack Helm solution sets the general storage volume group to `vg-general`. This value can be changed within Helm overrides file found at `/opt/genestack/base-helm-configs/topolvm/helm-topolvm-overrides.yaml`.

!!! example "Simple example showing how to create the needed volume group"

    ``` shell
    # NOTE sdX is a placeholder for a physical drive or partition.
    pvcreate /dev/sdX
    vgcreate vg-general /dev/sdX
    ```

Once the volume group is on your storage nodes, the node is ready for use.

### Deploy the TopoLVM Provisioner

!!! example "Run the topolvm deployment Script bin/install-topolvm.sh"

    ``` shell
    --8<-- "bin/install-topolvm.sh"
    ```
