# Prometheus

We are taking advantage of the prometheus community kube-prometheus-stack as
well as other various components for monitoring and alerting. For more
information, take a look at [Prometheus Kube Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

!!! tip

    You may need to provide custom values to configure prometheus. For a simple
    single region or lab deployment you can supply an additional overrides flag
    using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the
    [Multi-Region Support](multi-region-support.md) guide to for a workflow
    solution.

## Install the Prometheus Stack

!!! example "Run the Prometheus deployment"

    ``` shell
    /opt/genestack/bin/install-prometheus.sh
    ```

!!! success

    If the installation is successful, you should see the related exporter pods
    in the prometheus namespace.
    ``` shell
    kubectl -n prometheus get pods -l "release=kube-prometheus-stack"
    ```

## Update Alertmanager Configuration

In this example, we supply a Teams webhook URL to send all open alerts to a
teams channel. However, there are a plethora of other receivers available.
For a full list, review prometheus documentation: [receiver-integration-settings](https://prometheus.io/docs/alerting/latest/configuration/#receiver-integration-settings).

!!! example

    You can ignore this step if you don't want to send alerts to Teams, the
    alertmanager will still deploy and provide information.

    ``` shell
    read -p "webhook_url: " webhook_url;
    sed -i -e "s#https://webhook_url.example#$webhook_url#" \
    /etc/genestack/helm-configs/prometheus/alertmanager_config.yaml
    ```
