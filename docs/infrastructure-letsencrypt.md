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
            gatewayHTTPRoute:
              parentRefs:
              - group: gateway.networking.k8s.io
                kind: Gateway
                name: flex-gateway
                namespace: nginx-gateway
EOF
```
