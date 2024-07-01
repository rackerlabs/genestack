# Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /etc/genestack/kustomize/openstack
```

Then you can create all needed secrets by running the create-secrets.sh command located in /opt/genestack/bin

``` shell
/opt/genestack/bin/create-secrets.sh
```

That will create a secrets.yaml file located in /etc/genestack

You can then apply them to kubernetes with the following command:

``` shell
kubectl apply -f /etc/genestack/secrets.yaml -n openstack
```
