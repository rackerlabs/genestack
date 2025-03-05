# Deploy Sealed Secrets

## Install sealed secrets

!!! example "Run the deployment Script `bin/install-sealed-secrets.sh`"

    ``` shell
    --8<-- "bin/install-sealed-secrets.sh"
    ```


## Verify readiness with the following command.

``` shell
kubectl --namespace sealed-secrets get horizontalpodautoscaler.autoscaling sealed-secrets -w
```
