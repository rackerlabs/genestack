# Openstack Exporter

We are using Prometheus for monitoring and metrics collection along with the openstack exporter to gather openstack specific resource metrics. For more information see: [Prometheus docs](https://prometheus.io/docs/introduction/overview/) and [Openstack Exporter](https://github.com/openstack-exporter/openstack-exporter).

## Deploy the Openstack Exporter

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: [Deploy Prometheus](monitoring-prometheus.md).

The OpenStack metrics exporter implementation and base Helm configuration are maintained in the `genestack-observability` repository.

### Create clouds-yaml secret

Modify `/etc/genestack/helm-configs/openstack-metrics-exporter/clouds-yaml` with the appropriate settings and create the secret.

!!! tip

    See the [documentation](openstack-clouds.md) on generating your own `clouds.yaml` file which can be used to populate the monitoring configuration file.

From your generated `clouds.yaml` file, create a new manifest for your cloud config:

```shell
printf -v m "$(cat ~/.config/openstack/clouds.yaml)"; \
  t=$(echo "$m" | yq '.[] |= pick(["clouds", "default"])' | yq 'del(.cache)'); \
  t="$t" yq -I6 -n '."clouds.yaml" = strenv(t)' | tee /tmp/generated-clouds-yaml
```

generated file will look similar to this

```yaml
clouds.yaml: |
  clouds:
    default:
      region_name: RegionOne
      auth:
        username: admin
        password: <admin-password>
        project_name: admin
        project_domain_name: default
        user_domain_name: default
        auth_url: 'http://keystone-api.openstack.svc.cluster.local:5000/v3'
```

If you're using self-signed certs then you may need to add keystone certificates to the generated clouds yaml:

```shell
ks_cert="$(kubectl get secret -n openstack keystone-tls-public -o json | jq -r '.data."tls.crt"' | base64 -d)" \
  yq -I6 '."clouds.yaml" |= (from_yaml | .clouds.default.cacert = strenv(ks_cert) | to_yaml)' \
  </tmp/generated-clouds-yaml | tee /tmp/generated-clouds-certs-yaml
```

=== "Create a secret from your manifest"

    ```shell
    kubectl --namespace openstack create secret generic clouds-yaml-secret \
            --from-file /tmp/generated-clouds-yaml
    ```

=== "Create secrets for self-signed certs"

    ```shell
    kubectl --namespace openstack create secret generic clouds-yaml-secret \
            --from-file /tmp/generated-clouds-certs-yaml
    ```

With the secret created you can now deploy the openstack-metrics-exporter through the observability installer:

```shell
/opt/genestack/bin/install-observability.sh openstack-metrics-exporter
```

The component implementation and base Helm values are owned by `/opt/genestack-observability`; site-specific configuration remains under `/etc/genestack/helm-configs/openstack-metrics-exporter/`.

!!! success

    If the installation is successful, you should see the related exporter pods in the openstack namespace.

    ```shell
    kubectl -n openstack get pods -w | grep os-metrics
    ```

!!! example

    ```text
    os-metrics-prometheus-openstack-exporter-76bf579887-bwz5k   1/1     Running     0             7s
    ```
