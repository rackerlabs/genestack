# Openstack Exporter

We are using Prometheus for monitoring and metrics collection along with the openstack exporter to gather openstack specific resource metrics. For more information see: [Prometheus docs](https://prometheus.io/docs/introduction/overview/) and [Openstack Exporter](https://github.com/openstack-exporter/openstack-exporter).

## Deploy the Openstack Exporter

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: [Deploy Prometheus](monitoring-prometheus.md).

The OpenStack metrics exporter implementation and base Helm configuration are maintained in the `genestack-observability` repository.

### Create os-metrics user

The openstack metrics exporter should utilize a service user with admin role to query the various openstack services. 

```shell
# Generate a secure random password.
OS_METRICS_PASSWORD="$(openssl rand -hex 32)"

# Create the Keystone user in the service domain.
openstack user create os-metrics \
    --domain service \
    --password "${OS_METRICS_PASSWORD}" \
    --description "Prometheus OpenStack Metrics Exporter"

# Assign admin role on the service project.
openstack role add \
    --user os-metrics \
    --user-domain service \
    --project service \
    --project-domain service \
    admin

# Ensure monitoring namespace exists.
kubectl create namespace monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

# Store the password in Kubernetes.
kubectl -n monitoring create secret generic os-metrics-user \
    --from-literal=password="${OS_METRICS_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Clear password from shell variable.
unset OS_METRICS_PASSWORD
```


With the `os-metrics` user secret created you can now deploy the openstack-metrics-exporter through the observability installer:

```shell
/opt/genestack/bin/install-observability.sh openstack-metrics-exporter
```

The component implementation and base Helm values are owned by `/opt/genestack-observability`; site-specific configuration remains under `/etc/genestack/helm-configs/observability/openstack-metrics-exporter/`.

!!! success

    If the installation is successful, you should see the related exporter pods in the openstack namespace.

    ```shell
    kubectl -n openstack get pods -w | grep os-metrics
    ```

!!! example

    ```text
    os-metrics-prometheus-openstack-exporter-76bf579887-bwz5k   1/1     Running     0             7s
    ```
