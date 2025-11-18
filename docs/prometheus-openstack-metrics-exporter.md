# Openstack Exporter

We are using Prometheus for monitoring and metrics collection along with the openstack exporter to gather openstack specific resource metrics.
For more information see: [Prometheus docs](https://prometheus.io) and [Openstack Exporter](https://github.com/openstack-exporter/openstack-exporter)

## Deploy the Openstack Exporter

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: [Deploy Prometheus](prometheus.md).

### Create clouds-yaml secret

Modify `/etc/genestack/helm-configs/monitoring/openstack-metrics-exporter/clouds-yaml` with the appropriate settings and create the secret.

!!! tip

    See the [documentation](openstack-clouds.md) on generating your own `clouds.yaml` file which can be used to populate the monitoring configuration file.

From your generated `clouds.yaml` file, create a new manifest for your cloud config:

``` shell
printf -v m "$(cat ~/.config/openstack/clouds.yaml)"; \
  t=$(echo "$m" | yq '.[] |= pick(["clouds", "default"])' | yq 'del(.cache)'); \
  t="$t" yq -I6 -n '."clouds.yaml" = strenv(t)' | tee /tmp/generated-clouds-yaml
```

!!! example "generated file will look similar to this"

    ``` yaml
    --8<-- "base-helm-configs/monitoring/openstack-metrics-exporter/clouds-yaml"
    ```

If you're using self-signed certs then you may need to add keystone certificates to the generated clouds yaml:

``` shell
ks_cert="$(kubectl get secret -n openstack keystone-tls-public -o json | jq -r '.data."tls.crt"' | base64 -d)" \
  yq -I6 '."clouds.yaml" |= (from_yaml | .clouds.default.cacert = strenv(ks_cert) | to_yaml)' \
  </tmp/generated-clouds-yaml | tee /tmp/generated-clouds-certs-yaml
```

=== "Create a secret from your manifest"

    ``` shell
    kubectl --namespace openstack create secret generic clouds-yaml-secret \
            --from-file /tmp/generated-clouds-yaml
    ```

=== "Create secrets for self-signed certs"

    ``` shell
    kubectl --namespace openstack create secret generic clouds-yaml-secret \
            --from-file /tmp/generated-clouds-certs-yaml
    ```

With the secret created you can now deploy the **openstack-metrics-exporter** helm chart.

=== "Install openstack-metrics-exporter helm chart"

    ``` shell
    helm upgrade --install os-metrics /opt/genestack/submodules/openstack-exporter/charts/prometheus-openstack-exporter \
                --namespace=openstack \
                --timeout 15m \
                -f /opt/genestack/base-helm-configs/monitoring/openstack-metrics-exporter/openstack-metrics-exporter-helm-overrides.yaml \
                --set clouds_yaml_config="$(kubectl --namespace openstack get secret clouds-yaml-secret -o jsonpath='{.data.generated-clouds-yaml}' | base64 -d)"
    ```

=== "Install openstack-metrics-exporter helm chart with self-signed certs"

    ``` shell
    helm upgrade --install os-metrics /opt/genestack/submodules/openstack-exporter/charts/prometheus-openstack-exporter \
                --namespace=openstack \
                --timeout 15m \
                -f /opt/genestack/base-helm-configs/monitoring/openstack-metrics-exporter/openstack-metrics-exporter-helm-overrides.yaml \
                --set clouds_yaml_config="$(kubectl --namespace openstack get secret clouds-yaml-secret -o jsonpath='{.data.generated-clouds-certs-yaml}' | base64 -d)"
    ```

!!! success

    If the installation is successful, you should see the related exporter pods in the openstack namespace.

    ``` shell
    kubectl -n openstack  get pods -w | grep os-metrics
    ```

    !!! example

        ``` shell
        os-metrics-prometheus-openstack-exporter-76bf579887-bwz5k   1/1     Running     0             7s
        ```
