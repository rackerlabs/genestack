# Barbican Exporter

Barbican Exporter is used to validate if Barbican API is up.

!!! note

    To deploy metric exporters you will first need to deploy the Prometheus Operator, see: ([Deploy Prometheus](prometheus.md)).

## Installation

First create make sure if `keystone-auth` secret exist in `openstack` namespace. If not then create the secret:

``` shell
kubectl get secret keystone-auth -n openstack
kubectl --namespace openstack \
        create secret generic keystone-auth \
        --type Opaque \
        --from-literal=AUTH_UR="http://keystone-api.openstack.svc.cluster.local:5000/v3" \
        --from-literal=USERNAME="admin" \
        --from-literal=PASSWORD="$(kubectl get secret keystone-admin -n openstack -o jsonpath={.data.password} | base64 -d -w0)" \
        --from-literal=USER_DOMAIN_NAME="Default" \
        --from-literal=PROJECT_NAME="admin" \
        --from-literal=PROJECT_DOMAIN_NAME="Default"
```

Create barbican-exporter deployment and expose the deployment using Kubernetes Service. Further create service monitor so that prometheus can scrape the data:

``` shell
kubectl kustomize /etc/genestack/kustomize/barbican-exporter | kubectl apply -f -
```

!!! success
    If the installation is successful, you should see the exporter pod in the openstack namespace.

``` shell
kubectl get pods -n openstack -l app=barbican-exporter
```
