# Deploy Skyline

[![asciicast](https://asciinema.org/a/629816.svg)](https://asciinema.org/a/629816)

Skyline is an alternative Web UI for OpenStack. If you deploy horizon there's no need for Skyline.

## Create secrets
!!! info

    This step is not needed if you ran the create-secrets.sh script located in /opt/genestack/bin

Skyline is a little different because there's no helm integration. Given this difference the deployment is far simpler, and all secrets can be managed in one object.

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
        --from-literal=keystone-endpoint="$(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)" \
        --from-literal=keystone-username="skyline" \
        --from-literal=default-region="RegionOne" \
        --from-literal=prometheus_basic_auth_password="" \
        --from-literal=prometheus_basic_auth_user="" \
        --from-literal=prometheus_enable_basic_auth="false" \
        --from-literal=prometheus_endpoint="http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090"
```

!!! note

    All the configuration is in this one secret, so be sure to set your entries accordingly.

## Run the deployment

!!! tip

    Pause for a moment to consider if you will be wanting to access Skyline via the gateway-api controller over a specific FQDN. If so, adjust the gateway api definitions to suit your needs. For more information view [Gateway API](infrastructure-gateway-api.md)...

``` shell
kubectl --namespace openstack apply -k /opt/genestack/base-kustomize/skyline/base
```
