# Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /etc/genestack/kustomize/openstack
```

Then you can create all needed secrets by running the create-secrets.sh command located in /opt/genestack/bin

!!! tip "Optional --region param"

    Note that the `create-secrets.sh` script by default creates a secret
    with a default region of RegionOne. This can be overridden with the
    `--region` parameter to specify your custom region name in Keystone.
    > Usage: ./create-secrets.sh [--region <region> default: RegionOne]

``` shell
/opt/genestack/bin/create-secrets.sh
```

That will create a kubesecrets.yaml file located in /etc/genestack

You can then apply it to kubernetes with the following command:

``` shell
kubectl create -f /etc/genestack/kubesecrets.yaml
```
