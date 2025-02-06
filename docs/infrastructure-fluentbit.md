# Deploy Fluentbit

This guide will help you deploy fluentbit to your kubernetes cluster. Fluentbit is a lightweight log shipper that can be used to send logs to loki.

## Install the fluentbit helm repository

``` shell
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

### Deployment

Run the Fluent-Bit deployment Script `bin/install-fluentbit.sh`

??? example "Run the Fluent-Bit deployment Script `bin/install-fluentbit.sh`"

    ``` shell
    --8<-- "bin/install-fluentbit.sh"
    ```
