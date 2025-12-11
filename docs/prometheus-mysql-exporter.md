# Mariadb Exporter

Mysql Exporter is used to expose metrics from a running mysql/mariadb server. The type of metrics exposed is controlled
by the exporter and expressed in values.yaml file.

To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic mariadb-monitoring \
                --type Opaque \
                --from-literal=username="monitoring" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        ```

Add the config to a secret that'll be used within the container for our shared services

``` shell
kubectl -n openstack create secret generic mariadb-monitor --type Opaque --from-literal=my.cnf="[client.mariadb-monitor]
user=monitoring
password=$(kubectl --namespace openstack get secret mariadb-monitoring -o jsonpath='{.data.password}' | base64 -d)"
```

Next, install the exporter

??? example "`/opt/genestack/bin/install-prometheus-mysql-exporter.sh`"

    ``` shell
    --8<-- "bin/install-prometheus-mysql-exporter.sh"
    ```

!!! note

    Helm chart versions are defined in `opt/genestack/helm-chart-versions.yaml` and can be overridden in `/etc/genestack/helm-chart-versions.yaml`.

If the installation is successful, you should see the exporter pod in the openstack namespace.
