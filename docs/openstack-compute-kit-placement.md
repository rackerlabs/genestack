# Deploy Placement

!!! example "Run the Placement deployment Script `/opt/genestack/bin/install-placement.sh`"

    ``` shell
    --8<-- "bin/install-placement.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.
