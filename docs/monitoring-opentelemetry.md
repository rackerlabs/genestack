# OpenTelemetry

We are taking advantage of the Opentelemetry community opentelemetry-kube-stack as
well as other various components for monitoring and observability. For more
information, take a look at the [Opentelemetry Kube Stack Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-kube-stack)
as well as the [Opentelemetry Docs](https://opentelemetry.io/).

The [Monitoring and Observability Overview](monitoring-observability-overview.md) documentation page for more information
into it's features, components and how it's used within genestack. 

## Install the Opentelemetry Stack

!!! example "Run the Opentelemetry deployment Script `/opt/genestack/bin/install-opentelemetry-kube-stack.sh`"

    ``` shell
    --8<-- "bin/install-opentelemetry-kube-stack.sh"
    ```

!!! success

    If the installation is successful, you should see the related pods
    in the monitoring namespace.
    ``` shell
    kubectl -n monitoring get pods -l "release=opentelemetry-kube-stack"
    ```
