# Kubernetes Event Exporter

Kubernetes Event Exporter is used to expose kubernetes events which provides useful information regarding the operation of
the kubernetes system.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

Edit the Helm overrides file for the event exporter at `/etc/genestack/helm-configs/kubernetes-event-exporter/values.yaml`
to add any event notification receivers you may wish to use. View the examples at [Kubernetes Event Exporter](https://github.com/resmoio/kubernetes-event-exporter).

Once the changes have been made, apply them by running the  `/opt/genestack/bin/install-kubernetes-event-exporter.sh` script:

??? example "`/opt/genestack/bin/install-kubernetes-event-exporter.sh`"

    ``` shell
    --8<-- "bin/install-kubernetes-event-exporter.sh"
    ```
