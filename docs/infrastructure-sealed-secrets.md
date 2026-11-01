# Deploy Sealed Secrets

## Install sealed secrets

!!! example "Run the deployment: `/opt/genestack/bin/install.sh --service sealed-secrets`"

    ``` shell
    /opt/genestack/bin/install.sh --service sealed-secrets
    ```


## Verify readiness with the following command.

``` shell
kubectl --namespace sealed-secrets get horizontalpodautoscaler.autoscaling sealed-secrets -w
```
