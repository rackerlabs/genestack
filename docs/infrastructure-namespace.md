# Create our basic OpenStack namespace

The following command generates the OpenStack namespace and prepares the base resources needed before service deployment.

``` shell
kubectl apply -k /etc/genestack/kustomize/openstack/base
```

Service secrets are managed by the individual `/opt/genestack/bin/install-*.sh` scripts. Each installer creates missing Kubernetes secrets idempotently and reuses existing values on subsequent runs. See [Secret management](secret-management.md) for the install-script boundary and the remaining intentional secret creators outside that path.
