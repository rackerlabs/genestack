# OpenTelemetry

We are taking advantage of the Opentelemetry community opentelemetry-kube-stack as
well as other various components for monitoring and observability. For more
information, take a look at the [Opentelemetry Kube Stack Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-kube-stack)
as well as the [Opentelemetry Docs](https://opentelemetry.io/).

The [Monitoring and Observability Overview](monitoring-observability-overview.md) documentation page for more information
into it's features, components and how it's used within genestack. 

## Install the Opentelemetry Stack

efore installing OpenTelemetry we'll need secrets for various services we're gather metrics from. 
If this is a fresh cluster deployment we'll need to create the secrets in the `monitoring` namespace:

??? example "Create MariaDB secret"
```shell
kubectl --namespace monitoring \
  create secret generic mariadb-monitoring \
  --type Opaque \
  --from-literal=username="monitoring" \
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
```

??? example "Create Postgres secret"
```shell
kubectl --namespace monitoring \
  create secret generic postgres-monitoring \
  --type Opaque \
  --from-literal=username="monitoring" 
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64}; echo;)"
```

??? example "Create RabbitMQ secret in openstack namespace"
```shell
kubectl --namespace openstack \
  create secret generic rabbitmq-monitoring-user \
  --type Opaque \
  --from-literal=username="monitoring" \
  --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64}; echo;)"
```
For now we'll have to copy the secret into the monitoring namespace as well. 

??? example "Copy RabbitMQ secret to monitoring namespace"
```shell
kubectl get secret rabbitmq-monitoring-user \
  -n openstack -o yaml \
  | sed 's/namespace: openstack/namespace: monitoring/' \
  | kubectl apply -f -
```

!!! example "Run the Opentelemetry deployment Script `/opt/genestack/bin/install-opentelemetry-kube-stack.sh`"

    ``` shell
    --8<-- "bin/install-opentelemetry-kube-stack.sh"
    ```

!!! success

    If the installation is successful, you should see the related pods
    in the monitoring namespace.
    ``` shell
    kubectl -n monitoring get pods -l "release=opentelemetry-kube-stack"
    ```
