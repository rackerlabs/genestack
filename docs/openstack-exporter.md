# OpenStack Exporter

OpenStack Exporter is used to monitor and collect metrics from OpenStack services. It provides visibility into various OpenStack components and their performance metrics through Prometheus.

## Prerequisites

- Kubernetes cluster
- Prometheus Operator installed
- Access to OpenStack Keystone service
- Helm (if using Helm installation)

## Installation

### 1. Create Authentication Secret

First, create the Keystone authentication secret in the prometheus namespace:

```shell
kubectl --namespace prometheus \
        create secret generic keystone-auth-openstack-exporter \
        --type Opaque \
        --from-literal=AUTH_URL="http://keystone-api.openstack.svc.cluster.local:5000/v3" \
        --from-literal=USERNAME="admin" \
        --from-literal=PASSWORD="$(kubectl get secret keystone-admin -n openstack -o jsonpath={.data.password} | base64 -d -w0)" \
        --from-literal=USER_DOMAIN_NAME="Default" \
        --from-literal=PROJECT_NAME="admin" \
        --from-literal=PROJECT_DOMAIN_NAME="Default"
```

!!! Install the openstack exporter by just running the install script - `/opt/genestack/bin/install-openstack-exporter.sh`
```shell
--8<-- "bin/install-openstack-exporter.sh"
```

!!! success
If the installation is successful, you should see the exporter pod in the prometheus namespace.

``` shell
kubectl get pods -n openstack -l app=openstack-exporter
```

## Test and Verify
Can verify the metrics by just port-forwarding and curl command.
Which port the service is running can be seen by the following command,
```shell
kubectl get svc -n prometheus | grep openstack-exporter
```

Port Forwarding of openstack-exporter service to see the metrics:-
``` shell
kubectl port-forward svc/openstack-exporter -n prometheus 9180:<service-port>
```
Run Curl command in another window - curl localhost:9180/metrics


Also we can we can see the metrics on the prometheus GUI under the target path using following command,

```shell
kubectl port-forward svc/kube-prometheus-stack-prometheus -n prometheus 9090:9090
```

open the link on a browser - http://localhost:9090/targets
And select the serviceMonitor as "serviceMonitor/prometheus/openstack-exporter/0", Then will see it is showing up and all the details about it.
