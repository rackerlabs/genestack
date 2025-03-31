# Helm Overriding public endpoint fqdn openstack services

By default in Genestack the public endpoint fqdn for any openstack service is created with the cluster domain. For example if the cluster domain is "cluster.local" and keystone pods are in the "openstack" namespace then the fqdn for the keystone service would be "keystone-api.openstack.svc.cluster.local" which might not be ideal for production environments. There are examples provided in the documentation to override the domain for the [gateway api routes](https://docs.rackspacecloud.com/infrastructure-nginx-gateway-api-custom/#custom-routes); this however doesn't override the fqdn for the openstack services in the keystone catalog.

Below we will discuss how to override the public endpoint fqdn in the keystone catalog using helm values

# Providing the required overrides for public endpoints in the keystone catalog

In order to modify the public endpoint fqdn for any openstack service then helm overrides can be used; taking an example of keystone service.

This is the httproute for keystone service:

``` shell
kubectl get httproute -n openstack custom-keystone-gateway-route-http
NAME                                 HOSTNAMES                    AGE
custom-keystone-gateway-route-https   ["keystone.cluster.local"]   78d
```

This although doesn't modify the public endpoint for the keystone service in the catalog; to modify the fqdn for the keystone service in the catalog we would need to create an helm overrides file:

```yaml
endpoints:
  identity:
    host_fqdn_override:
      public:
        tls: {}
        host: keystone.cluster.local
    port:
      api:
        public: 443
    scheme:
      public: https
```

this file needs to be moved into /etc/genestack/helm-configs/keystone/ directory and when installing the helm chart this will override the fqdn of the keystone service in the catalog.

!!! note
    The fqdn in the httproute and helm overrides must be the same

This is an example overrides file for nova:

!!! example "`host_fqdn_overrides.yaml`"

    ``` yaml
    endpoints:
      compute:
        host_fqdn_override:
          public:
            tls: {}
            host: nova.cluster.local
        port:
          api:
            public: 443
        scheme:
          public: https
      compute_metadata:
        host_fqdn_override:
          public:
            tls: {}
            host: metadata.nova.cluster.local
        port:
          metadata:
            public: 443
        scheme:
          public: https
      compute_novnc_proxy:
        host_fqdn_override:
          public:
            tls: {}
            host: novnc.nova.cluster.local
        port:
          novnc_proxy:
            public: 443
        scheme:
          public: https
    ```

!!! note
    gateway-api handles tls encryption on public endpoints; it is not required to specify tls parameters in helm
