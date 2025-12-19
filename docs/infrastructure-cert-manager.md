# Deploy Cert-Manager

Cert Manager integrates with the Envoy Gateway API to automate the issuance, renewal, and management of TLS/SSL certificates within a cluster. This installation includes envoy gateway-api support and custom DNS server forwarders in the helm chart config.

## Configure custom cert-manager DNS forwarders

View the upstream chart Documentation [cert-manager helm](https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml) to configure custom-values.

!!! Edit /etc/genestack/helm-configs/cert-manager/cert-manager/cert-manager-helm-overrides.yaml

   ```bash
   ---
   dns01RecursiveNameservers: "8.8.8.8:53, 1.1.1.1:53" <-----CHANGE
   dns01RecursiveNameserversOnly: true
   ```

## Run Cert-Manager deployment

!!! example "Run the cert-manager deployment Script `/opt/genestack/bin/install-cert-manager.sh`"

    ``` shell
    --8<-- "bin/install-cert-manager.sh"
    ```

## Verify readiness with the following command

``` shell
kubectl -n cert-manager deployments.apps/cert-manager -w
```
