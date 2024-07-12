# Deploy the ingress controllers

!!! tip

    When deploying Ingress for the first time, make sure to build the helm charts. Information on building the helm charts can be [found here](openstack-helm-make.md).

We need two different Ingress controllers, one in the `openstack` namespace, the other in the `ingress-nginx` namespace. The `openstack` controller is for east-west connectivity, the `ingress-nginx` controller is for north-south.

### Deploy our ingress controller within the ingress-nginx Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/base-kustomize/ingress/external | kubectl apply --namespace ingress-nginx -f -
```

### Deploy our ingress controller within the OpenStack Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/base-kustomize/ingress/internal | kubectl apply --namespace openstack -f -
```

The openstack ingress controller uses the class name `nginx-openstack`.

#### Patching the ingress ConfigMap

Sometimes you may need to make an update to your ingress setup which is managed in the ConfigMaps.

!!! example "Patching the worker processes"

    ``` shell
    kubectl -n ${NAMESPACE} patch configmaps ingress-conf -p '{"data": {"worker-processes": "8"}}'
    ```

!!! note

    If you make a system level change in the ConfigMap you will need to recreate the pods.
