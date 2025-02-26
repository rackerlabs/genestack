# Deploy Barbican

OpenStack Barbican is the dedicated security service within the OpenStack ecosystem, focused on the secure storage, management, and provisioning of sensitive data such as encryption keys, certificates, and passwords. Barbican plays a crucial role in enhancing the security posture of cloud environments by providing a centralized and controlled repository for cryptographic secrets, ensuring that sensitive information is protected and accessible only to authorized services and users. It integrates seamlessly with other OpenStack services to offer encryption and secure key management capabilities, which are essential for maintaining data confidentiality and integrity. In this document, we will explore the deployment of OpenStack Barbican using Genestack. With Genestack, the deployment of Barbican is optimized, ensuring that cloud infrastructures are equipped with strong and scalable security measures for managing critical secrets.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic barbican-rabbitmq-password \
                --type Opaque \
                --from-literal=username="barbican" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic barbican-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic barbican-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Setup Barbican Overrides

When deploying barbican, it is important to provide the necessary configuration values to ensure that the service is properly
configured and integrated with other OpenStack services. The `/etc/genestack/helm-configs/barbican/barbican-helm-overrides.yaml`
file contains the necessary configuration values for Barbican, including database connection details, RabbitMQ credentials, and other
service-specific settings. By providing these values, you can customize the deployment of Barbican to meet your specific requirements
and ensure that the service operates correctly within your OpenStack environment.

!!! tip "Set the `host_href` value"

    The `host_href` value should be set to the public endpoint of the Barbican service. This value is used by other OpenStack services and public consumers to communicate with Barbican and should be accessible from all OpenStack services.

    ``` yaml
    conf:
      barbican:
        DEFAULT:
          host_href: "https://barbican.your.domain.tld"
    ```

## Run the package deployment

!!! example "Run the Barbican deployment Script `bin/install-barbican.sh`"

    ``` shell
    --8<-- "bin/install-barbican.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.
