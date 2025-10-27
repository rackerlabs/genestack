# Deploy Skyline

OpenStack Skyline is the next-generation web-based dashboard designed to provide a modern, responsive, and highly performant interface for managing OpenStack services. As an evolution of the traditional Horizon dashboard, Skyline focuses on improving user experience with a more streamlined and intuitive design, offering faster load times and enhanced responsiveness. It aims to deliver a more efficient and scalable way to interact with OpenStack components, catering to both administrators and end-users who require quick and easy access to cloud resources. In this document, we will cover the deployment of OpenStack Skyline using Genestack. Genestack ensures that Skyline is deployed effectively, allowing users to leverage its improved interface for managing both private and public cloud environments with greater ease and efficiency.

## Create secrets

!!! note "Automated secret generation"

    Skyline secrets can be generated automatically using the `create-skyline-secrets.sh` script located in `/opt/genestack/bin`. This script integrates with the main `create-secrets.sh` workflow and handles all secret generation automatically.

### Automated Secret Generation

The recommended approach is to use the automated script:

``` shell
# Generate Skyline secrets with default region (RegionOne)
/opt/genestack/bin/create-skyline-secrets.sh
```

The script will:

- Generate secure random passwords for all Skyline services
- Create `/etc/genestack/skylinesecrets.yaml` with the Skyline-specific secrets
- Append the secrets to `/etc/genestack/kubesecrets.yaml` for integration with the main workflow
- Perform safety checks to prevent duplicate secret generation
- Ensure the main `kubesecrets.yaml` file exists before proceeding

!!! warning "Prerequisites"

    The `create-skyline-secrets.sh` script requires that `/etc/genestack/kubesecrets.yaml` already exists. Run the main `create-secrets.sh` script first if you haven't already.

!!! note "Secret Management"

    All Skyline configuration is managed in a single secret object (`skyline-apiserver-secrets`), making deployment simpler compared to other OpenStack services that use Helm integration.

### Manual Secret Generation (Alternative)

If you prefer manual control or need to customize specific values, you can still create secrets manually:

??? example "Manual secret generation"

    ``` shell
    kubectl --namespace openstack \
            create secret generic skyline-apiserver-secrets \
            --type Opaque \
            --from-literal=service-username="skyline" \
            --from-literal=service-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
            --from-literal=service-domain="service" \
            --from-literal=service-project="service" \
            --from-literal=service-project-domain="service" \
            --from-literal=db-endpoint="mariadb-cluster-primary.openstack.svc.cluster.local" \
            --from-literal=db-name="skyline" \
            --from-literal=db-username="skyline" \
            --from-literal=db-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
            --from-literal=secret-key="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
            --from-literal=keystone-endpoint="http://keystone-api.openstack.svc.cluster.local:5000/v3" \
            --from-literal=keystone-username="skyline" \
            --from-literal=default-region="RegionOne" \
            --from-literal=prometheus_basic_auth_password="" \
            --from-literal=prometheus_basic_auth_user="" \
            --from-literal=prometheus_enable_basic_auth="false" \
            --from-literal=prometheus_endpoint="http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090"
    ```

## Run the deployment

!!! tip

    Pause for a moment to consider if you will be wanting to access Skyline via the gateway-api controller over a specific FQDN. If so, adjust the gateway api definitions to suit your needs. For more information view [Gateway API](infrastructure-gateway-api.md)...

``` shell
kubectl --namespace openstack apply -k /etc/genestack/kustomize/skyline/overlay
```

## Demo

[![asciicast](https://asciinema.org/a/629816.svg)](https://asciinema.org/a/629816)
