# Deploy Barbican

OpenStack Barbican is the dedicated security service within the OpenStack ecosystem, focused on the secure storage, management, and provisioning of sensitive data such as encryption keys, certificates, and passwords. Barbican plays a crucial role in enhancing the security posture of cloud environments by providing a centralized and controlled repository for cryptographic secrets, ensuring that sensitive information is protected and accessible only to authorized services and users. It integrates seamlessly with other OpenStack services to offer encryption and secure key management capabilities, which are essential for maintaining data confidentiality and integrity. In this document, we will explore the deployment of OpenStack Barbican using Genestack. With Genestack, the deployment of Barbican is optimized, ensuring that cloud infrastructures are equipped with strong and scalable security measures for managing critical secrets.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.

## Setup Barbican Overrides

When deploying barbican, it is important to provide the necessary configuration values to ensure that the service is properly
configured and integrated with other OpenStack services. The `/etc/genestack/helm-configs/barbican/barbican-helm-overrides.yaml`
file contains the necessary configuration values for Barbican, including database connection details, RabbitMQ credentials, and other
service-specific settings. By providing these values, you can customize the deployment of Barbican to meet your specific requirements
and ensure that the service operates correctly within your OpenStack environment.

!!! note "Gazpacho (2026.1) / OpenStack 2026.1"

    Barbican is validated here against the OpenStack `2026.1` stream.
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

    For Gazpacho validation, DB credentials are injected at install time from Kubernetes secrets in
    `bin/install-barbican.sh` (for example `endpoints.oslo_db.auth.admin.password` and
    `endpoints.oslo_db.auth.barbican.password`).

!!! tip

    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Simple crypto master KEK

Barbican's `simple_crypto` plugin wraps every project key with a master key-encryption-key (KEK). Since Gazpacho there is
no built-in default: if no KEK is rendered into `barbican.conf`, `barbican-api` fails to start with `SimpleCrypto KEK is
undefined`. A KEK set in an override file (`conf.barbican.simple_crypto_plugin.kek`) always takes precedence and is
deployed as is: `install-barbican.sh` injects nothing and writes no Secret. Otherwise Genestack keeps the KEK in the
`barbican-simple-crypto-kek` Kubernetes Secret, which `install-barbican.sh` creates on a new deployment and injects on
every deploy together with the `old_keks` rotation history.

!!! note "What `install-barbican.sh` does when neither an override file nor the Secret supplies a KEK"

    - If a running deployment already rendered a KEK into the `barbican-etc` Secret, the installer adopts that KEK into
      `barbican-simple-crypto-kek` before any random generation is considered.
    - If no override, managed Secret, or deployed `barbican-etc` KEK exists, the installer treats the deployment as a
      first install and generates a fresh KEK into the Secret.

When the Secret holds a KEK that differs from the deployed one, the deploy only proceeds if the deployed KEK is listed
in the Secret's `old_keks`, which `--stage` always records. Otherwise the script refuses, because the db-sync rewrap
could not succeed. A KEK from an override file gets no such check: on that path the chart's db-sync job is the only
safeguard, and it fails the deploy rather than losing data when the KEK cannot unwrap the existing project keys.

### Rotate the KEK

Environments that never set a KEK have been running on Barbican's publicly documented default key, and rotating retires it.
A rotation of a Secret-managed KEK is staged with `/opt/genestack/scripts/rotate-barbican-kek.py` and executed by the chart's
db-sync job on the next deploy, which rewraps every project key one-way. `install-barbican.sh` never calls the tool. Without
flags the tool is a read-only plan, and it never prints key material. Genestack injects a single `kek` and the previous
keys as the chart's comma-separated `old_kek`, so the rotation is the db-sync job's one-way rewrap, which is why the backup
below is not optional. Never set `kek` as a plain YAML list: the chart renders it as one comma-joined value that Fernet
rejects.

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
    ```

    `--adopt` validates the currently deployed KEK against the database from inside a ready `barbican-api` pod and
    stores it in the Secret. (Note: `barbican-api` must be running; if a previous deploy crashlooped, `helm rollback`
    to the last good revision first). The installer can also adopt the deployed KEK directly from `barbican-etc` when
    no managed Secret exists, but the rotation tool remains the safer operator workflow when you want database
    validation before changing management mode. If a `kek` line is set in your override files, remove it (since an
    override always takes precedence over the Secret), then run `install-barbican.sh`: the Secret's KEK matches the
    deployed one, so nothing is rewrapped.
