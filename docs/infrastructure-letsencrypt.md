# Deploying Let's Encrypt Certificates

Are you tired of manually renewing and deploying a countless number of
certificates across your environments? Us too!

## Apply the Let's Encrypt Cluster Issuer

Before we can have Cert Manager start coordinating Let's Encrypt certificate
requests for us, we need to add an ACME issuer with a valid, monitored
email (for expiration reminders and other important ACME related information).

``` yaml
read -p "Enter a valid email address for use with ACME: " ACME_EMAIL; \
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
EOF
```

## Use the proper TLS issuerRef

!!! danger "Important for later helm installations!"
    The `letsencrypt-prod` ClusterIssuer is used to generate the certificate through cert-manager. This ClusterIssuer is applied using a Kustomize patch. However, to ensure that the certificate generation process is initiated, it is essential to include `endpoints.$service.host_fqdn_override.public.tls: {}` in the service helm override file.
    Similarly, ensure that `endpoints.$service.host_fqdn_override.public.host` is set to the external DNS hostname you plan to expose for a given service endpoint.
    This configuration is necessary for proper certificate generation and to ensure the service is accessible via the specified hostname.

!!! example
    You can find several examples of this in the
    `helm-configs/prod-example-openstack-overrides.yaml`, one such example
    for glance is below for reference.
    ```yaml
    endpoints:
      image:
        host_fqdn_override:
          public:
            tls: {}
            host: glance.api.your.domain.tld
        port:
          api:
            public: 443
        scheme:
          public: https
    ```

## Helm Kustomize Post Render Args

In order for Cert Manager to set up the ACME challenge, it needs to know which
ingress to target. We do this via a kustomize overlay that injects the
needed annotation(s) to the ingress that will be publicly exposed. The
kustomize overlay to use for that is aptly named, `letsencrypt`.

!!! example "Example keystone installation using the letsencrypt overlay"
    ```shell
    helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/keystone/keystone-helm-overrides.yaml \
    -f /opt/genestack/helm-configs/prod-example-openstack-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args keystone/letsencrypt
    ```
