# Setting up Loki

Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost-effective and easy to operate. It does not index the contents of the logs, but rather a set of labels for each log stream.

## Add the grafana helm repo

``` shell
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Install the helm chart

ou will need to make changes depending on how you want to configure loki. Example files are included in `genetack/base-helm-configs`.  Choose one relevant to your deploy, edit for revelant data, and ensure you copy the file to `/etc/genestack/base-helm/loki-helm-overrides.yaml`

``` shell
helm upgrade --install \
             --values /etc/genestack/helm-configs/loki/loki-helm-overrides.yaml \
             loki grafana/loki \
             --create-namespace \
             --namespace grafana \
             --version 5.47.2
```

=== "Swift _(Recommended)_"

    !!! abstract

        If you plan on using **Swift** as a backend for log storage see the `loki-helm-swift-overrides-example.yaml` file in the `helm-configs/loki` directory.

        ``` yaml
        --8<-- "base-helm-configs/loki/loki-helm-swift-overrides-example.yaml"
        ```

=== "S3"

    !!! abstract

        If you plan on using **S3** as a backend for log storage see the `loki-helm-s3-overrides-example.yaml` file in the `helm-configs/loki` directory.

        ``` yaml
        --8<-- "base-helm-configs/loki/loki-helm-s3-overrides-example.yaml"
        ```

=== "MinIO"

    !!! abstract

        If you plan on using **Minio** as a backend for log storage see the `loki-helm-s3-overrides-example.yaml` file in the `helm-configs/loki` directory.

        ``` yaml
        --8<-- "base-helm-configs/loki/loki-helm-minio-overrides-example.yaml"
        ```
