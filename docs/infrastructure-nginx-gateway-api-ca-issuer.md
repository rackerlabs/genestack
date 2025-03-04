# NGINX Creating a CA issuer for Gateway API

By default in Genestack the selfSigned issuer is used to issue certificates to Gateway API listeners. This is a fairly simple issuer to create and requires a very simple yaml manifest. Although the main purpose of the selfSigned issuer to create a local PKI i.e bootstrap a local self-signed CA which can then be used to issue certificates as required. This is helpful for test environments. The selfSigned issuer itself doesn't represent a certificate authority by rather indicates that the certificates will sign themselves.

Below we'll discuss on how to create a self-signed CA certicate and create a CA clusterissuer to issue certificates to Gateway API listeners

## Overview

Firstly, we'll note that Gateway API in Genestack is currently utilizing selfSigned issuer:

``` shell
cat internal-gateway-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: flex-gateway-issuer
  namespace: nginx-gateway
spec:
  selfSigned: {}

cat internal-gateway-api.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: flex-gateway
  namespace: nginx-gateway
  annotations: # This is the name of the ClusterIssuer created in the previous step
    cert-manager.io/cluster-issuer: flex-gateway-issuer
    acme.cert-manager.io/http01-edit-in-place: "true"
....
```

with the selfSigned issuer being used to issue certificates; every certificate issued to Gateway API listeners is a CA certificate

A more suitable approach would be to use selfSigned issuer to create a CA issuer and that's what we will discuss below

## Create the CA certificate and a CA clusterissuer

For this example workflow we'll edit `internal-gateway-issuer.yaml` file to create a CA certificate and then create a CA clusterissuer:

The structure may look something like:

!!! example
```
cat internal-gateway-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: flex-gateway-issuer
  namespace: nginx-gateway
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: public-endpoint-ca-cert
  namespace: cert-manager
spec:
  isCA: true
  commonName: public-endpoint-ca
  secretName: public-endpoint-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: flex-gateway-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: public-endpoint-issuer
  namespace: nginx-gateway
spec:
  ca:
    secretName: public-endpoint-ca-secret
```

!!! note
    The namespace for the certificate resoruce must be cert-manager

#### Use the CA ClusterIssuer for Gateway API

It is pretty straightforward to use the CA created above for Gateway API; just modify the annotation on the flex-gateway resource:

``` shell
cat internal-gateway-api.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: flex-gateway
  namespace: nginx-gateway
  annotations: # This is the name of the ClusterIssuer created in the previous step
    cert-manager.io/cluster-issuer: public-endpoint-issuer
    acme.cert-manager.io/http01-edit-in-place: "true"
....
```

The CA certificate created above can be obainted with:

``` shell
kubectl get secret -n cert-manager public-endpoint-ca-secret -o jsonpath='{.data.tls\.crt}' | base64 -d
```

This is a simple example on how to create CA certificates with selfSigned issuers and use them for issuing certificates

!!! note
    It is not recommend to use self-singed certificates in production environments.
