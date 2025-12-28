# Deploy Horizon

OpenStack Horizon is the web-based dashboard for the OpenStack ecosystem, providing users with a graphical interface to manage and interact with OpenStack services. Horizon simplifies the management of cloud resources by offering an intuitive and user-friendly platform where users can launch instances, manage storage, configure networks, and monitor the overall health of their cloud environment. It serves as the central point of interaction for administrators and users alike, providing visibility and control over the entire cloud infrastructure. In this document, we will detail the deployment of OpenStack Horizon using Genestack. By leveraging Genestack, the deployment of Horizon is made more efficient, ensuring that users have seamless access to a robust and responsive interface for managing their private and public cloud environments.

## Create secrets

!!! note "Secret generation has been moved to the install-horizon.sh script"

## Run the package deployment

!!! example "Run the Horizon deployment Script `/opt/genestack/bin/install-horizon.sh`"

    ``` shell
    --8<-- "bin/install-horizon.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Demo

[![asciicast](https://asciinema.org/a/629815.svg)](https://asciinema.org/a/629815)
