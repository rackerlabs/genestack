# Grafana

Grafana is installed with the upstream Helm Chart. Running the installation is simple and can be done with our integration script.

Before running the script, you will need to create a secret file with your database username and passwords.

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace grafana \
                create secret generic grafana-db \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
                --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
                --from-literal=username=grafana
        ```

## Custom Values

Before running the deployment script, you must set the `custom_host` value `grafana-helm-overrides.yaml` to the correct FQDN you wish to use within the deployment.

!!! example "grafana-helm-overrides.yaml"

    ``` yaml
    custom_host: grafana.api.your.domain.tld
    ```

## Installation

=== "Default"

    The default installation is simple. The `grafana-helm-overrides.yaml` file is located at `/etc/genestack/helm-configs/grafana/` and overrides can be set there to customize the installation.

=== "Azure Integrated"

    Before running installation when integrating with Azure AD, you must create te `azure-client-secret`

    You can base64 encode your `client_id` and `client_secret` by using the echo and base64 command.

    ``` shell
    echo -n "YOUR CLIENT ID OR SECRET" | base64
    ```

    Apply your base64 encoded values to the `azure-client-secret.yaml` file and apply it to the `grafana` namespace.

    !!! example "azure-client-secret.yaml"

        ``` yaml
        --8<-- "manifests/grafana/azure-client-secret.yaml"
        ```

    Once you have created the secret file, update your `grafana-helm-overrides.yaml` file with the Azure AD values.

    !!! example "azure-overrides.yaml"

        ``` yaml
        --8<-- "base-helm-configs/grafana/azure-overrides.yaml.example"
        ```

### Listeners and Routes

Listeners and Routes should have been configureed when you installed the Gateway API.  If so some reason they were not created, please following the install guide here: [Gateway API](infrastructure-gateway-api.md)

### Deployment

Run the Grafana deployment Script `/opt/genestack/bin/install-grafana.sh`

??? example "Run the Grafana deployment Script `/opt/genestack/bin/install-grafana.sh`"

    ``` shell
    --8<-- "bin/install-grafana.sh"
    ```
