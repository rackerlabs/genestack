# Setting up Loki

## Add the grafana helm repo
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## Install the helm chart

You will need to make changes depending on how you want to configure loki. Example files are included in this directory choose one relevant to your deploy

```bash
helm upgrade --install --values my-loki-helm-overrides.yaml loki grafana/loki --create-namespace --namespace grafana
```

### Swift notes

If you plan on using swift as a backend for log storage see the [loki-helm-swift-overrides-example.yaml](loki-helm-swift-overrides-example.yaml)

### S3 notes

If you plan on using s3 as a backend for log storage see the [loki-helm-s3-overrides-example.yaml](loki-helm-s3-overrides-example.yaml)

### minio notes

If you plan on using minio as a backend for log storage see the [loki-helm-minio-overrides-example.yaml](loki-helm-minio-overrides-example.yaml)
