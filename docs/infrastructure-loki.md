# Setting up Loki

## Add the grafana helm repo

``` shell
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Install the helm chart

You will need to make changes depending on how you want to configure loki. Example files are included in this directory choose one relevant to your deploy

``` shell
helm upgrade --install \
             --values my-loki-helm-overrides.yaml \
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
