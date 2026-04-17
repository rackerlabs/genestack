### Component Maintenance: Observability Stack Upgrade - Multiple Service Impact


## Validation

This maintenance impacts multiple services related to the observability stack. 
- Grafana
- Loki
- Fluentbit
- Prometheus/Alertmanager
- Tempo
- Various Prometheus metrics exporters

### New components:
    - Opentelemetry (unified source for collection, procession and enrichment of metrics, logs and traces)
    - Tempo (storage backend for tracing metrics)

### Components removed:
    - Fluentbit (replaced with opentelemetry fileLog receiver)
    - prometheus-blackbox-exporter (replaced with opentelemetry httpcheck receiver)
    - prometheus-snmp-exporter (replaced with opentelemetry snmp receiver)
    - prometheus-rabbitmq-exporter (replaced with opentelemetry rabbitmq receiver)
    - prometheus-postgres-exporter (replaced with opentelemetry postgres receiver)
    - prometheus-mysql-exporter (replaced with opentelemetry mysql receiver)
    
    
### Impact

Upgrading the observability stack impacts all the above listed components and will cause data-loss for metrics as 
currently configured. This upgrade unifies the monitoring and observability stack under a single `monitoring` namespace.
If your installation of Loki is not using an external storage system logs will be lost (minIO PVC storage for example). 
The grafana database can be backed up, but it may be preferable to simply reimport dashboards. 
Prometheus metrics will be lost as the PVC's will need to be removed during this upgrade. 

## Goal

Upgrade the monitoring/observability stack to include Opentelemetry tooling, reduce the need for prometheus exporters
and unify the entire stack under the `monitoring` namespace. 

## Prep

# Deployment Node

All commands should be able to be ran from the region's overseer aside from exporting the grafana dashboards if needed. 
The dashboards should be identical across regions so this step can be done prior to save time.

### Take backups

#### Grafana-db backup
If exporting-importing dashboards this step is only needed as a safety-net/good practice. Users and keys will 
still have to be added/updated manually as needed. 

 ```
$ ROOT_PASSWORD=$(kubectl --namespace grafana get secret grafana-db -o jsonpath='{.data.root-password}' | base64 -d)

$ kubectl -n grafana exec mariadb-cluster-0 -- sh -c \
  "exec mariadb-dump --all-databases --single-transaction -uroot -p'${ROOT_PASSWORD}'" \
  > mariadb-backup-grafana-$(date +'%Y%m%d-%H%M%S').sql
```  

#### Export Grafana dashboards
Run this and the importer from your local machine for ease-of-use.

!!! note
    - This can be done once for any region as they should all be identical.
    - You may need to have a proper python3 virtualenv preconfigured.
    - Run within a directory defined for dashboards as the script does not create its own root directory.
    - Update the script with the service account token and regional endpoint of your choice

``` 
$ python /opt/genestack/scripts/export-grafana-dashboards.py
```

# Configuration Review

If needed, verify the configurations for all the services, add/update overrides as needed:

  - Grafana - opt/genestack/base-helm-configs/grafana/* - etc/genestack/base-kustomize/grafana/*
  - Loki - opt/genestack/base-helm-configs/loki/* - etc/genestack/base-kustomize/loki/*
  - Prometheus/Alertmanager - opt/genestack/base-helm-configs/kube-prometheus-stack/* - - etc/genestack/base-kustomize/kube-prometheus-stack/*
  - Tempo - opt/genestack/base-helm-configs/tempo/* - - etc/genestack/base-kustomize/tempo/*

# Pre-Change Safety Checks

We're tearing down pvc's and databases, ensure you've collected the data as needed.

# Run The Maintenance

## Execute Uninstalls

### Uninstall Fluentbit

```
helm uninstall -n fluentbit fluentbit
```

### Uninstall Loki

``` 
helm uninstall -n grafana loki
kubectl delete httproutes -n grafana logcli-gateway-route
kubectl delete httproutes -n grafana internal-loki-gateway-route
kubectl delete pvc data-loki-write-0 data-loki-write-1 data-loki-write-2 data-loki-write-3 -n grafana
```

!!! note
    You may need to adjust the data-loki-write-<n> for the particular cluster. Verify you've removed them all.  

### Uninstall Grafana components

```
helm uninstall -n grafana grafana
kubectl delete configmap mariadb-cluster -n grafana
kubectl delete database grafana -n grafana
kubectl delete mariadb mariadb-cluster -n grafana
kubectl delete grant grafana-grant -n grafana --force --grace-period=0
kubectl delete user grafana -n grafana
kubectl delete httproutes -n grafana grafana-gateway-route
kubectl delete backup -n grafana mariadb-backup
```

### Uninstall Prometheus/Alertmanager components

```
helm uninstall -n prometheus kube-prometheus-stack
kubectl delete pvc -n prometheus alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0
kubectl delete pvc -n prometheus prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
kubectl delete httproutes -n prometheus prometheus-gateway-route
kubectl delete httproutes -n prometheus alertmanager-gateway-route 
```

### Uninstall Prometheus Exporters

``` 
helm uninstall -n prometheus prometheus-blackbox-exporter
helm uninstall -n prometheus prometheus-snmp-exporter
helm uninstall -n openstack prometheus-rabbitmq-exporter
helm uninstall -n openstack prometheus-postgres-exporter
helm uninstall -n openstack prometheus-mysql-exporter
```

## Execute Installs

### Install Prometheus/Alertmanager

``` 
/opt/genestack/bin/install-kube-prometheus-stack.sh
kubectl apply -f /etc/genestack/gateway-api/routes/monitoring-prometheus-gateway-route.yaml
kubectl apply -f /etc/genestack/gateway-api/routes/monitoring-alertmanager-gateway-route.yaml    
```
### Install Opentelemetry

``` 
/opt/genestack/bin/install-opentelemetry-kube-stack.sh
```
!!! note
    For existing installs we may need to ensure the etc symlink exist, if it doesn't then create it.
``` 
- /etc/genestack/kustomize/opentelemetry-kube-stack$  ln -s /opt/genestack/base-kustomize/opentelemetry-kube-stack/base/ .
```

### Install Loki

``` 
/opt/genestack/bin/install-loki.sh
kubectl apply -f /etc/genestack/gateway-api/routes/monitoring-internal-loki-gateway-route.yaml
```

### Install Grafana

``` 
kubectl --namespace monitoring \
    create secret generic grafana-db \
    --type Opaque \
    --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
    --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
    --from-literal=username=grafana


kubectl apply -f /etc/genestack/helm-configs/grafana/azure-client-secret.yaml

/opt/genestack/bin/install-grafana.sh

kubectl apply -f /etc/genestack/gateway-api/routes/monitoring-grafana-gateway-route.yaml

```

### Install Tempo

```
/opt/genestack/bin/install-temo.sh
```

!!! note
    For existing installs we may need to ensure the etc symlink exist, if it doesn't then create it.
``` 
- /etc/genestack/kustomize/tempo$  ln -s /opt/genestack/base-kustomize/tempo/base/ .
```

### Auto-instrumentation for Openstack applications
With Tempo installed you may auto-instrument Openstack applications via Opentelemetry to collect tracing data. 

!!! warning
    This is still largely untested in Genestack and may break applications. There's known bugs around 
    python monkey-patching. One being the need to pass OTEL_PYTHON_AUTO_INSTRUMENTATION_EXPERIMENTAL_GEVENT_PATCH=patch_all
    in the Instrumentation configuration in order to avoid recursion issues. Proceed with caution.

!!! warning
    Tempo is a tracing storage system that receives data via Opentelemetry powered auto-instrumentation. 
    The auto-instrumented monkey-patching agents are deployed to application pods, like Nova, which modify 
    running libraries to gather requested tracing data. The impact on performance depends on various factors 
    like the sampler ratio and cluster resource limits.   

Edit the file `/opt/genestack/base-kustomize/opentelemetry-kube-stack/base/openstack-annotate-instrumentation.yaml`
and uncommoment the applications you want to instrument and the run the following: 

``` 
kubectl apply -f /opt/genestack/base-kustomize/opentelemetry-kube-stack/base/openstack-instrumentation.yaml
kubectl apply -f /opt/genestack/base-kustomize/opentelemetry-kube-stack/base/openstack-annotate-instrumentation.yaml
```
!!! warning
    Running the above commands will restart all service that were targeted for annotation. It may be ideal 
    to stagger the application annotation updates.  
    

## Post-Maint

### Grafana post-maint

1. Login via azure auth for the regions grafana endpoint and create a service account and token. 
    - This doc explains how to do so: https://grafana.com/docs/grafana/latest/administration/service-accounts/

2. Import the dashboards
   - Run from local machine within the directory created during export
   - Update the script with the new token and regional endpoint
   - ``` 
      $ python /opt/genestack/scripts/import-grafana-dashboard.py
     ```        
### General verification
Use Grafana to confirm that Prometheus, Loki, Tempo, and Alertmanager datasources are healthy. Then verify:

 - metrics are being scraped into Prometheus
 - logs are queryable in Loki
 - traces are queryable in Tempo
 - OpenTelemetry collector pods are running and are forwarding telemetry successfully

## Troubleshooting

View logs of the various services for potential issues, check the pod rollout events for any notifications...

I believe there's a bug in opentelemetry helm that *may* require installing twice for all collectors to fully deploy.

# Rollback

There is no rollback procedure for this maintenance.

## Sources

https://docs.rackspacecloud.com/monitoring-getting-started/
