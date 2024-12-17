# Deploy Fluentbit

This guide will help you deploy fluentbit to your kubernetes cluster. Fluentbit is a lightweight log shipper that can be used to send logs to loki.

## Install the fluentbit helm chart

``` shell
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

## Install the helm chart

You will need to make changes depending on how you want to configure loki. Example files are included in this directory choose one relevant to your deploy

``` shell
helm install --values fluentbit-helm-overrides.yaml fluentbit fluent/fluent-bit
```
