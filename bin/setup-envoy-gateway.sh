#!/bin/bash
# shellcheck disable=SC2045,SC2124,SC2145,SC2164,SC2236,SC2294

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -e, --email EMAIL           Email address for ACME (optional)
    -d, --domain DOMAIN         Gateway domain name (default: cluster.local)
    -c, --challenge METHOD      ACME challenge method: http01 or dns01 (default: http01)
    -p, --dns-plugin PLUGIN     DNS01 plugin: godaddy (default: godaddy, only used with dns01)
    -k, --godaddy-key KEY       GoDaddy API Key (required for dns01 with godaddy)
    -s, --godaddy-secret SECRET GoDaddy API Secret (required for dns01 with godaddy)
    -h, --help                  Display this help message

EXAMPLES:
    # Basic setup with HTTP01 challenge
    $0 --email user@example.com --domain example.com

    # Setup with DNS01 challenge using GoDaddy
    $0 --email user@example.com --domain example.com --challenge dns01 --godaddy-key KEY --godaddy-secret SECRET

    # Interactive mode (original behavior)
    $0
EOF
}

# Initialize variables
ACME_EMAIL=""
GATEWAY_DOMAIN=""
CHALLENGE_METHOD="http01"
DNS_PLUGIN="godaddy"
GODADDY_KEY=""
GODADDY_SECRET=""
INTERACTIVE_MODE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            ACME_EMAIL="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -d|--domain)
            GATEWAY_DOMAIN="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -c|--challenge)
            CHALLENGE_METHOD="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -p|--dns-plugin)
            DNS_PLUGIN="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -k|--godaddy-key)
            GODADDY_KEY="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -s|--godaddy-secret)
            GODADDY_SECRET="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate challenge method
if [[ "$CHALLENGE_METHOD" != "http01" && "$CHALLENGE_METHOD" != "dns01" ]]; then
    echo "Error: Invalid challenge method. Must be 'http01' or 'dns01'"
    exit 1
fi

# Interactive prompts (fallback for missing parameters)
if [[ "$INTERACTIVE_MODE" == "true" ]]; then
    if [ -z "${ACME_EMAIL}" ]; then
        read -rp "Enter a valid email address for use with ACME, press enter to skip: " ACME_EMAIL
    fi

    if [ -z "${GATEWAY_DOMAIN}" ]; then
        echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
        read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
        export GATEWAY_DOMAIN=${GATEWAY_DOMAIN:-cluster.local}
    fi
fi

# Set default domain if not provided
if [ -z "${GATEWAY_DOMAIN}" ]; then
    GATEWAY_DOMAIN="cluster.local"
fi

# Validate required parameters for DNS01 with GoDaddy
if [[ "$CHALLENGE_METHOD" == "dns01" && "$DNS_PLUGIN" == "godaddy" ]]; then
    if [[ -z "$GODADDY_KEY" || -z "$GODADDY_SECRET" ]]; then
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            read -rp "Enter your GoDaddy API Key: " GODADDY_KEY
            read -rsp "Enter your GoDaddy API Secret: " GODADDY_SECRET
            echo
        else
            echo "Error: GoDaddy API Key and Secret are required for DNS01 challenge with GoDaddy plugin"
            echo "Use --godaddy-key and --godaddy-secret options"
            exit 1
        fi
    fi
fi

# Display configuration
echo "Configuration:"
echo "  Email: ${ACME_EMAIL:-"(not provided)"}"
echo "  Domain: ${GATEWAY_DOMAIN}"
echo "  Challenge Method: ${CHALLENGE_METHOD}"
if [[ "$CHALLENGE_METHOD" == "dns01" ]]; then
    echo "  DNS Plugin: ${DNS_PLUGIN}"
fi
echo

# Apply the gateway configuration
kubectl apply -k /etc/genestack/kustomize/envoyproxy-gateway/overlay
echo "Waiting for the gateway to be programmed"
kubectl -n envoy-gateway wait --timeout=5m gateways.gateway.networking.k8s.io flex-gateway --for=condition=Programmed

# Configure ACME if email is provided
if [ ! -z "${ACME_EMAIL}" ]; then
    if [ "${CHALLENGE_METHOD}" = "dns01" ]; then
        if [ "${DNS_PLUGIN}" = "godaddy" ]; then
            echo "Setting up GoDaddy Webhook for DNS01 challenge..."
            
            # Install GoDaddy webhook
            echo "Installing GoDaddy webhook..."
            helm repo add godaddy-webhook https://snowdrop.github.io/godaddy-webhook
            helm repo update
            helm install godaddy-webhook godaddy-webhook/godaddy-webhook -n cert-manager --set groupName=acme.${GATEWAY_DOMAIN}
            
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
            echo "Error: Unsupported DNS plugin: ${DNS_PLUGIN}"
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
