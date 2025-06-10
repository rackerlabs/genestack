# Deploy Horizon

OpenStack Horizon is the web-based dashboard for the OpenStack ecosystem, providing users with a graphical interface to manage and interact with OpenStack services. Horizon simplifies the management of cloud resources by offering an intuitive and user-friendly platform where users can launch instances, manage storage, configure networks, and monitor the overall health of their cloud environment. It serves as the central point of interaction for administrators and users alike, providing visibility and control over the entire cloud infrastructure. In this document, we will detail the deployment of OpenStack Horizon using Genestack. By leveraging Genestack, the deployment of Horizon is made more efficient, ensuring that users have seamless access to a robust and responsive interface for managing their private and public cloud environments.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic horizon-secret-key \
                --type Opaque \
                --from-literal=username="horizon" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic horizon-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

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
