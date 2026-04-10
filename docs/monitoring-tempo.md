# Tempo

We are taking advantage of the Grafana community tempo helm chart to provide storage and querying ability for
tracing components. For more information, take a look at 
[Tempo Helm Chart](https://github.com/grafana-community/helm-charts/tree/main/charts/tempo) and the
[Grafana Tempo docs](https://grafana.com/oss/tempo/).

## Install the Opentelemetry Stack

!!! example "Run the Opentelemetry deployment Script `/opt/genestack/bin/install-tempo.sh`"

    ``` shell
    --8<-- "bin/install-tempo.sh"
    ```

!!! success

    If the installation is successful, you should see the related pods
    in the monitoring namespace.
    ``` shell
    kubectl -n monitoring get pods -l "release=tempo"
    ```
