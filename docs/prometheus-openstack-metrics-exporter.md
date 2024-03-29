# Openstack Exporter

We are using Prometheus for monitoring and metrics collection along with the openstack exporter to gather openstack specific resource metrics.
For more information see: [Prometheus docs](https://prometheus.io) and [Openstack Exporter](https://github.com/openstack-exporter/openstack-exporter)

## Deploy the Openstack Exporter

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: [Deploy Prometheus](prometheus.md).

### Create clouds-yaml secret

Modify genestack/helm-configs/monitoring/openstack-metrics-exporter/clouds-yaml with the appropriate settings and create the secret.

!!! tip

    See the [documentation](openstack-clouds.md) on generating your own `clouds.yaml` file which can be used to populate the monitoring configuration file.

``` shell
kubectl create secret generic clouds-yaml-secret \
  --from-file /opt/genestack/helm-configs/monitoring/openstack-metrics-exporter/clouds-yaml
```

### Install openstack-metrics-exporter helm chart

``` shell
cd /opt/genestack/submodules/openstack-exporter/helm-charts/charts

helm upgrade --install os-metrics ./prometheus-openstack-exporter \
  --namespace=openstack \
    --timeout 15m \
    -f /opt/genestack/helm-configs/monitoring/openstack-metrics-exporter/openstack-metrics-exporter-helm-overrides.yaml \
    --set clouds_yaml_config="$(kubectl get secret clouds-yaml-secret -o jsonpath='{.data.clouds-yaml}' | base64 -d)"
```

!!! success
    If the installation is successful, you should see the related exporter pods in the openstack namespace.
