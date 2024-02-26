## Openstack API Exporter

We are using Prometheus for monitoring and metrics collection backend along with the openstack api exporter to gather openstack resource metrics
For more information see: https://prometheus.io and https://github.com/openstack-exporter/openstack-exporter

## Deploy the Prometheus Openstack API Exporter


### Install openstack-api-exporter helm chart
```shell
cd /opt/genestack/submodules/openstack-helm-infra

helm upgrade --install prometheus-openstack-exporter ./prometheus-openstack-exporter \
  --namespace=openstack \
    --timeout 15m \
    -f /opt/genestack/helm-configs/monitoring/openstack-api-exporter/openstack-api-exporter-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args monitoring/openstack-api-exporter/base
```
