#!/bin/bash
# shellcheck disable=SC2045,SC2124,SC2145,SC2164,SC2236,SC2294

if [ -z "${ACME_EMAIL}" ]; then
  read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
fi

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
  read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
  export GATEWAY_DOMAIN=${GATEWAY_DOMAIN:-cluster.local}
fi

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "Gateway domain is required"
  exit 1
fi

kubectl kustomize /etc/genestack/kustomize/gateway/nginx-gateway-fabric | kubectl apply -f -

echo "Waiting for the gateway to be programmed"
kubectl -n nginx-gateway wait --timeout=5m gateways.gateway.networking.k8s.io flex-gateway --for=condition=Programmed

if [ ! -z "${ACME_EMAIL}" ]; then
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

  kubectl patch --namespace nginx-gateway \
                --type merge \
                --patch-file /etc/genestack/gateway-api/gateway-letsencrypt.yaml \
                gateway flex-gateway

  kubectl rollout restart deployment cert-manager --namespace cert-manager
fi

sudo mkdir -p /etc/genestack/gateway-api/routes
for route in $(ls -1 /opt/genestack/etc/gateway-api/routes); do
    sed "s/your.domain.tld/${GATEWAY_DOMAIN}/g" "/opt/genestack/etc/gateway-api/routes/${route}" > "/tmp/${route}"
    sudo mv -v "/tmp/${route}" "/etc/genestack/gateway-api/routes/${route}"
done

kubectl apply -f /etc/genestack/gateway-api/routes

sudo mkdir -p /etc/genestack/gateway-api/listeners
for listener in $(ls -1 /opt/genestack/etc/gateway-api/listeners); do
    sed "s/your.domain.tld/${GATEWAY_DOMAIN}/g" "/opt/genestack/etc/gateway-api/listeners/${listener}" > "/tmp/${listener}"
    sudo mv -v "/tmp/${listener}" "/etc/genestack/gateway-api/listeners/${listener}"
done

kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch="$(jq -s 'flatten | .' /etc/genestack/gateway-api/listeners/*)"

echo "Setup Complete"
