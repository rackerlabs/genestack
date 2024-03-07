# Deploy Skyline

[![asciicast](https://asciinema.org/a/629816.svg)](https://asciinema.org/a/629816)

Skyline is an alternative Web UI for OpenStack. If you deploy horizon there's no need for Skyline.

## Create secrets

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
        --from-literal=db-endpoint="mariadb-galera-primary.openstack.svc.cluster.local" \
        --from-literal=db-name="skyline" \
        --from-literal=db-username="skyline" \
        --from-literal=db-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=secret-key="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=keystone-endpoint="http://keystone-api.openstack.svc.cluster.local:5000" \
        --from-literal=default-region="RegionOne"
```

!!! note

    All the configuration is in this one secret, so be sure to set your entries accordingly.

## Run the deployment

!!! tip

    Pause for a moment to consider if you will be wanting to access Skyline via your ingress controller over a specific FQDN. If so, modify `/opt/genestack/kustomize/skyline/fqdn/kustomization.yaml` to suit your needs then use `fqdn` below in lieu of `base`...

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/skyline/base
```
