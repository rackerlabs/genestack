# Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /opt/genestack/base-kustomize/openstack
```

Then you can create all needed secrets by running the create-secrets.sh command located in /opt/genestack/bin

``` shell
/opt/genestack/bin/create-secrets.sh -h
Usage: ./create-secrets.sh [--region <region> default: RegionOne]
```

That will create a kubesecrets.yaml file located in /etc/genestack

You can then apply them to kubernetes with the following command:

``` shell
kubectl apply -f /etc/genestack/kubesecrets.yaml -n openstack
```
