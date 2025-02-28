# Deploy a argocd

## Install Argocd

!!! example "Run the argocd deployment Script `bin/install-argocd.sh`"

    ``` shell
    --8<-- "bin/install-argocd.sh"
    ```


## Verify readiness with the following command.

``` shell
kubectl --namespace argocd get horizontalpodautoscaler.autoscaling argocd -w
```
