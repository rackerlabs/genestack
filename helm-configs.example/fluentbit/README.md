# Install the fluentbit helm chart

```
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update`
helm install --values fluentbit-helm-overrides.yaml fluentbit fluent/fluent-bit
```
