# Mariadb Exporter

Mysql Exporter is used to expose metrics from a running mysql/mariadb server. The type of metrics exposed is controlled
by the exporter and expressed in values.yaml file.

## Installation

First create secret containing password for monitoring user

``` shell
kubectl --namespace openstack \
        create secret generic mariadb-monitoring \
        --type Opaque \
        --from-literal=username="monitoring" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
```

Next, install the exporter

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/prometheus-mysql-exporter | \
  kubectl -n openstack apply --server-side -f -
```

If the installation is successful, you should see the exporter pod in openstack namespace.
