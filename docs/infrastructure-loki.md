# Setting up Loki

Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost-effective and easy to operate. It does not index the contents of the logs, but rather a set of labels for each log stream.

## Run the package deployment

!!! example "Run the Loki deployment Script `/opt/genestack/bin/install-loki.sh`"

    ``` shell
    --8<-- "bin/install-loki.sh"
    ```

!!! tip

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
