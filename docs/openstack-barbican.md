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

!!! note "Epoxy (2026.1) / OpenStack 2025.1"

    Barbican is validated here against the OpenStack `2025.1` stream.
    This update does not include direct changes to `barbican-helm-overrides.yaml`.

!!! tip "Set the `host_href` value"

    The `host_href` value should be set to the public endpoint of the Barbican service. This value is used by other OpenStack services and public consumers to communicate with Barbican and should be accessible from all OpenStack services.

    ``` yaml
    conf:
      barbican:
        DEFAULT:
          host_href: "https://barbican.your.domain.tld"
    ```

## Run the package deployment

!!! example "Run the Barbican deployment Script `/opt/genestack/bin/install-barbican.sh`"

    ``` shell
    --8<-- "bin/install-barbican.sh"
    ```

!!! note

    For Epoxy validation, DB credentials are injected at install time from Kubernetes secrets in
    `bin/install-barbican.sh` (for example `endpoints.oslo_db.auth.admin.password` and
    `endpoints.oslo_db.auth.barbican.password`).

!!! tip

    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Simple crypto master KEK

Barbican's `simple_crypto` plugin wraps every project key with a master key-encryption-key (KEK). Since Gazpacho there is
no built-in default: if no KEK is rendered into `barbican.conf`, `barbican-api` fails to start with `SimpleCrypto KEK is
undefined`. Genestack keeps the KEK in the `barbican-simple-crypto-kek` Kubernetes Secret, which `create-secrets.sh`
generates on a new deployment and `install-barbican.sh` injects on every deploy together with the `old_keks` rotation history.

!!! note "What `install-barbican.sh` does when the Secret is missing"

    - A KEK set in an override file (`conf.barbican.simple_crypto_plugin.kek`) is checked against the database. If
      it unwraps every project key, it is adopted into the Secret. If it does not, it is a rotation driven through
      the chart: it is honoured as-is, nothing is injected, and the deploy proceeds only when a key in the
      override's `old_kek` unwraps the rows. Without a ready `barbican-api` nothing can be checked and the
      override is honoured as-is.
    - If Barbican already holds data, the currently deployed KEK is adopted into the Secret after it has been validated
      against the database. No rotation takes place. This needs a running `barbican-api` pod.
    - If there is no Barbican data yet, a fresh KEK is generated into the Secret.

    When the Secret holds a KEK that differs from the deployed one, the deploy only proceeds if the deployed KEK is listed
    in the Secret's `old_keks`, which `--stage` always records, or if the database holds no simple_crypto project keys
    yet. Otherwise the script refuses, because the db-sync rewrap could not succeed.

### Rotate the KEK

Environments that never set a KEK have been running on Barbican's publicly documented default key, and rotating retires it.
A rotation is staged with `/opt/genestack/scripts/rotate-barbican-kek.py` and executed by the chart's db-sync job on the next
deploy, which rewraps every project key one-way. Without flags the tool is a read-only plan, and it never prints key material.
Barbican's `kek` option can hold several keys, but the chart renders a list as one comma-joined value that Fernet rejects, so
a deployment cannot run the old and the new key side by side: the one-way rewrap is the only path, which is why the backup
below is not optional.

!!! warning "Back up the Barbican database before deploying a staged rotation"

    Octavia certificates and Cinder volume encryption keys depend on Barbican secrets staying decryptable.

    ``` shell
    /opt/genestack/scripts/rotate-barbican-kek.py                      # plan: validates the deployed KEK, writes nothing
    /opt/genestack/scripts/rotate-barbican-kek.py --stage              # writes the new KEK and history into the Secret
    # back up the barbican database here: the next step rewraps every project key one-way
    /opt/genestack/bin/install-barbican.sh                             # db-sync rewraps every project KEK
    /opt/genestack/scripts/rotate-barbican-kek.py --validate deployed  # must pass; db-sync logs must show zero failures
    ```

!!! tip "Move an existing environment under Secret management without rotating"

    ``` shell
    /opt/genestack/scripts/rotate-barbican-kek.py --adopt
    /opt/genestack/bin/install-barbican.sh
    ```

    After one successful deploy the `kek` line can be removed from your override files; the Secret takes precedence over them.
