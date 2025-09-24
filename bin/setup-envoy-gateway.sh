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

kubectl apply -k /etc/genestack/kustomize/envoyproxy-gateway/overlay
echo "Waiting for the gateway to be programmed"
kubectl -n envoy-gateway wait --timeout=5m gateways.gateway.networking.k8s.io flex-gateway --for=condition=Programmed

if [ ! -z "${ACME_EMAIL}" ]; then
  echo "Choose ACME challenge method:"
  echo "1) HTTP01 (default)"
  echo "2) DNS01"
  read -rp "Enter your choice [1]: " CHALLENGE_METHOD
  CHALLENGE_METHOD=${CHALLENGE_METHOD:-1}
  
  if [ "${CHALLENGE_METHOD}" = "2" ]; then
    echo "Choose DNS01 cert-manager plugin:"
    echo "1) GoDaddy Webhook"
    read -rp "Enter your choice [1]: " DNS_PLUGIN
    DNS_PLUGIN=${DNS_PLUGIN:-1}
    
    if [ "${DNS_PLUGIN}" = "1" ]; then
      echo "Setting up GoDaddy Webhook for DNS01 challenge..."
      
      # Install GoDaddy webhook
      echo "Installing GoDaddy webhook..."
      helm repo add godaddy-webhook https://snowdrop.github.io/godaddy-webhook
      helm repo update
      helm install godaddy-webhook godaddy-webhook/godaddy-webhook -n cert-manager --set groupName=acme.${GATEWAY_DOMAIN}
      
      # Prompt for GoDaddy API credentials
      read -rp "Enter your GoDaddy API Key: " GODADDY_KEY
      read -rsp "Enter your GoDaddy API Secret: " GODADDY_SECRET
      echo
      
      # Create secret for GoDaddy API credentials
      echo "Creating GoDaddy API credentials secret..."
      kubectl create secret generic godaddy-api-key \
        --namespace cert-manager \
        --from-literal=token="${GODADDY_KEY}:${GODADDY_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
      
      # Create ClusterIssuer for DNS01 with GoDaddy
      echo "Creating ClusterIssuer for DNS01 with GoDaddy webhook..."
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
      name: letsencrypt-prod-account-key
    solvers:
    - dns01:
        webhook:
          groupName: acme.${GATEWAY_DOMAIN}
          solverName: godaddy
          config:
            apiKeySecretRef:
              name: godaddy-api-key
              key: token
            production: true
            ttl: 600
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
    else
      echo "Invalid DNS plugin selection"
      exit 1
    fi
  else
    # HTTP01 challenge (original behavior)
    echo "Setting up HTTP01 challenge..."
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
              namespace: envoy-gateway
EOF
  fi
  
  # Annotate the gateway with the cluster issuer
  kubectl -n envoy-gateway annotate --overwrite gateway/flex-gateway cert-manager.io/cluster-issuer=letsencrypt-prod
fi

# Process routes
sudo mkdir -p /etc/genestack/gateway-api/routes
for route in $(ls -1 /opt/genestack/etc/gateway-api/routes); do
    sed "s/your.domain.tld/${GATEWAY_DOMAIN}/g" "/opt/genestack/etc/gateway-api/routes/${route}" > "/tmp/${route}"
    sed -i 's/namespace: nginx-gateway/namespace: envoy-gateway/g' "/tmp/${route}"
    sudo mv -v "/tmp/${route}" "/etc/genestack/gateway-api/routes/${route}"
done
kubectl apply -f /etc/genestack/gateway-api/routes

# Process listeners
sudo mkdir -p /etc/genestack/gateway-api/listeners
for listener in $(ls -1 /opt/genestack/etc/gateway-api/listeners); do
    sed "s/your.domain.tld/${GATEWAY_DOMAIN}/g" "/opt/genestack/etc/gateway-api/listeners/${listener}" > "/tmp/${listener}"
    sudo mv -v "/tmp/${listener}" "/etc/genestack/gateway-api/listeners/${listener}"
done
kubectl patch -n envoy-gateway gateway flex-gateway \
              --type='json' \
              --patch="$(jq -s 'flatten | .' /etc/genestack/gateway-api/listeners/*)"

echo "Setup Complete"
