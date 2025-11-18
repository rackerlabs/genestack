# Prometheus Blackbox Exporter

Using the blackbox exporter we can gather metrics around uptime, latency, cert expiry and more for our public endpoints.
The blackbox exporter ideally would be ran outside the cluster but can still provide useful information when deployed within it when combined with alerting and visualizations.

## Installation

??? example "`/opt/genestack/bin/install-prometheus-blackbox-exporter.sh`"

    ``` shell
    --8<-- "bin/install-prometheus-blackbox-exporter.sh"
    ```

If the installation is successful, you should see the related Blackbox exporter pods in the prometheus namespace.
