# Deploy the ingress controllers

We need two different Ingress controllers, one in the `openstack` namespace, the other in the `ingress-nginx` namespace. The `openstack` controller is for east-west connectivity, the `ingress-nginx` controller is for north-south.

!!! note

    To deploy the ingress controller please ensure Helm is installed first ([Install Helm](openstack-helm-make.md)).


### Deploy our ingress controller within the ingress-nginx Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/ingress/external | kubectl apply --namespace ingress-nginx -f -
```

### Deploy our ingress controller within the OpenStack Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/ingress/internal | kubectl apply --namespace openstack -f -
```

The openstack ingress controller uses the class name `nginx-openstack`.
