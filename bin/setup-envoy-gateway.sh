#!/bin/bash
# shellcheck disable=SC2045,SC2124,SC2145,SC2164,SC2236,SC2294

# Function to display general usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -e, --email EMAIL           Email address for ACME (required for ACME setup)
    -d, --domain DOMAIN         Gateway domain name (default: cluster.local)
    -c, --challenge METHOD      ACME challenge method: http01 or dns01 (default: http01)
    -p, --dns-plugin PLUGIN     DNS01 plugin (only used with dns01)
    -h, --help [PLUGIN]         Display this help message, or detailed help for a specific plugin

    # Generic credentials (usage depends on --dns-plugin):
    --api-key KEY               API Key (used by multiple providers)
    --api-secret SECRET         API Secret (used by multiple providers)
    --api-token TOKEN           API Token (used by multiple providers)
    --username USERNAME         Username (used by some providers)
    --password PASSWORD         Password (used by some providers)
    --project-id ID             Project ID (used by some providers)
    --tenant-id ID              Tenant ID (used by some providers)
    --subscription-id ID        Subscription ID (used by some providers)
    --resource-group NAME       Resource Group (used by some providers)
    --region REGION             Region (used by some providers)
    --hosted-zone-id ID         Hosted Zone ID (used by some providers)
    --service-account-file FILE Path to service account JSON file (used by some providers)
    --nameserver HOST           Nameserver (used by some providers)
    --tsig-key-name NAME        TSIG key name (used by some providers)
    --tsig-secret SECRET        TSIG Secret (used by some providers)
    --tsig-algorithm ALG        TSIG Algorithm (used by some providers)

SUPPORTED DNS PLUGINS:
    godaddy         GoDaddy DNS (requires webhook)
    rackspace       Rackspace Cloud DNS (requires webhook)
    cloudflare      Cloudflare DNS (built-in support)
    route53         AWS Route53 (built-in support)
    azuredns        Azure DNS (built-in support)
    google          Google Cloud DNS (built-in support)
    digitalocean    DigitalOcean DNS (built-in support)
    acmedns         ACME-DNS (built-in support)
    rfc2136         RFC2136 Dynamic DNS (built-in support)

For detailed help on a specific plugin, use: $0 --help PLUGIN
Example: $0 --help cloudflare

EXAMPLES:
    # Basic setup with HTTP01 challenge
    $0 --email user@example.com --domain example.com

    # Setup without ACME (no SSL certificates)
    $0 --domain example.com

    # Get detailed help for Cloudflare
    $0 --help cloudflare

    # Interactive mode
    $0
EOF
}

# Function to display detailed help for specific plugins
usage_plugin() {
    local plugin="$1"

    case "$plugin" in
        godaddy)
            cat << EOF
GoDaddy DNS Configuration
=========================

GoDaddy uses a webhook for DNS01 challenges and requires API credentials.

REQUIREMENTS:
    --api-key KEY               GoDaddy API Key
    --api-secret SECRET         GoDaddy API Secret

HOW TO GET CREDENTIALS:
    1. Log in to your GoDaddy account
    2. Go to https://developer.godaddy.com/keys
    3. Create a new API key (Production or Test)
    4. Save both the API Key and Secret

EXAMPLE:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin godaddy --api-key YOUR_KEY --api-secret YOUR_SECRET

NOTES:
    - GoDaddy requires a webhook to be installed in your cluster
    - The script will automatically install the webhook from the Helm chart
    - Make sure cert-manager is already installed in your cluster
EOF
            ;;
        rackspace)
            cat << EOF
Rackspace Cloud DNS Configuration
==================================

Rackspace uses a webhook for DNS01 challenges and requires your Rackspace credentials.

REQUIREMENTS:
    --username USERNAME         Rackspace username
    --api-key KEY               Rackspace API Key

HOW TO GET CREDENTIALS:
    1. Log in to your Rackspace Cloud Control Panel
    2. Click on your username in the upper right corner
    3. Select "Account Settings"
    4. Click on "API Keys" or navigate to https://manage.rackspace.com/APIKeys
    5. View or generate your API key

EXAMPLE:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin rackspace --username YOUR_USERNAME --api-key YOUR_API_KEY

NOTES:
    - Rackspace requires a webhook to be installed in your cluster
    - The script will clone and install the webhook from GitHub
    - The webhook will be installed in the cert-manager namespace
EOF
            ;;
        cloudflare)
            cat << EOF
Cloudflare DNS Configuration
=============================

Cloudflare has built-in support in cert-manager and offers two authentication methods.

OPTION 1 - API Token (RECOMMENDED):
    --api-token TOKEN           Cloudflare API Token

    How to create an API Token:
    1. Log in to your Cloudflare account
    2. Go to: User Profile > API Tokens > Create Token
    3. Use the "Edit zone DNS" template or create a custom token with:
       Permissions:
         - Zone > DNS > Edit
         - Zone > Zone > Read
       Zone Resources:
         - Include > All Zones (or specific zones)
    4. Copy the generated token

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin cloudflare --api-token YOUR_TOKEN

OPTION 2 - API Key (Legacy):
    --api-key KEY               Cloudflare Global API Key
    --email EMAIL               Your Cloudflare account email

    How to get your API Key:
    1. Log in to your Cloudflare account
    2. Go to: User Profile > API Tokens > API Keys > Global API Key > View
    3. Enter your password to view the key

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin cloudflare --api-key YOUR_KEY --email cf@example.com

NOTES:
    - API Tokens are more secure and recommended
    - API Tokens can be scoped to specific zones and permissions
    - API Keys have full account access
    - No webhook required - Cloudflare support is built into cert-manager
EOF
            ;;
        route53)
            cat << EOF
AWS Route53 DNS Configuration
==============================

Route53 has built-in support in cert-manager and offers multiple authentication methods.

OPTION 1 - IAM Role (RECOMMENDED for EKS):
    No credentials needed - uses pod IAM role

    Setup:
    1. Create an IAM policy with Route53 permissions:
       {
         "Version": "2012-10-17",
         "Statement": [
           {
             "Effect": "Allow",
             "Action": "route53:GetChange",
             "Resource": "arn:aws:route53:::change/*"
           },
           {
             "Effect": "Allow",
             "Action": [
               "route53:ChangeResourceRecordSets",
               "route53:ListResourceRecordSets"
             ],
             "Resource": "arn:aws:route53:::hostedzone/*"
           },
           {
             "Effect": "Allow",
             "Action": "route53:ListHostedZonesByName",
             "Resource": "*"
           }
         ]
       }
    2. Attach this policy to your cert-manager pod's IAM role
    3. Run the script without credentials

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin route53

OPTION 2 - Access Key/Secret:
    --api-key KEY               AWS Access Key ID
    --api-secret SECRET         AWS Secret Access Key

    Optional:
    --region REGION             AWS Region (default: us-east-1)
    --hosted-zone-id ID         Specific Hosted Zone ID

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin route53 --api-key YOUR_KEY --api-secret YOUR_SECRET \\
       --region us-west-2

NOTES:
    - IAM role method is more secure and recommended for EKS clusters
    - Hosted Zone ID is optional; cert-manager will auto-discover if not specified
    - No webhook required - Route53 support is built into cert-manager
EOF
            ;;
        azuredns)
            cat << EOF
Azure DNS Configuration
=======================

Azure DNS has built-in support in cert-manager and supports multiple authentication methods.

REQUIRED FOR ALL METHODS:
    --subscription-id ID        Azure Subscription ID
    --resource-group NAME       Azure Resource Group containing the DNS zone

OPTION 1 - Service Principal (Recommended for production):
    --tenant-id ID              Azure Tenant ID
    --api-key KEY               Azure Client ID (Application ID)
    --api-secret SECRET         Azure Client Secret

    How to create a Service Principal:
    1. Register an application in Azure AD:
       az ad sp create-for-rbac --name cert-manager-dns
    2. Note the appId (Client ID), password (Client Secret), and tenant
    3. Grant DNS Zone Contributor role:
       az role assignment create \\
         --assignee <appId> \\
         --role "DNS Zone Contributor" \\
         --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group>

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin azuredns --subscription-id SUB_ID --tenant-id TENANT_ID \\
       --resource-group RG_NAME --api-key CLIENT_ID --api-secret CLIENT_SECRET

OPTION 2 - Managed Identity (Recommended for AKS):
    --api-key KEY               Managed Identity Client ID (optional)

    Setup:
    1. Enable managed identity on your AKS cluster
    2. Grant the identity DNS Zone Contributor role
    3. Configure workload identity or pod identity

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin azuredns --subscription-id SUB_ID --resource-group RG_NAME

HOW TO FIND YOUR IDS:
    Subscription ID: az account show --query id -o tsv
    Tenant ID:       az account show --query tenantId -o tsv
    Resource Group:  The name of the resource group containing your DNS zone

NOTES:
    - No webhook required - Azure DNS support is built into cert-manager
    - The DNS zone must exist in the specified resource group
    - Managed Identity is more secure for AKS clusters
EOF
            ;;
        google)
            cat << EOF
Google Cloud DNS Configuration
===============================

Google Cloud DNS has built-in support in cert-manager.

REQUIRED:
    --project-id ID             GCP Project ID

OPTION 1 - Workload Identity (RECOMMENDED for GKE):
    No additional credentials needed - uses pod Workload Identity

    Setup:
    1. Enable Workload Identity on your GKE cluster
    2. Create a Google Service Account with DNS Admin role:
       gcloud iam service-accounts create dns-admin
    3. Bind it to the Kubernetes service account:
       gcloud iam service-accounts add-iam-policy-binding \\
         dns-admin@PROJECT_ID.iam.gserviceaccount.com \\
         --role roles/iam.workloadIdentityUser \\
         --member "serviceAccount:PROJECT_ID.svc.id.goog[cert-manager/cert-manager]"
    4. Annotate the cert-manager service account:
       kubectl annotate serviceaccount cert-manager -n cert-manager \\
         iam.gke.io/gcp-service-account=dns-admin@PROJECT_ID.iam.gserviceaccount.com

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin google --project-id YOUR_PROJECT_ID

OPTION 2 - Service Account Key File:
    --service-account-file FILE Path to service account JSON key file

    How to create a Service Account key:
    1. Go to IAM & Admin > Service Accounts in Google Cloud Console
    2. Create a service account with "DNS Administrator" role
    3. Create and download a JSON key file

    Example:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin google --project-id YOUR_PROJECT_ID \\
       --service-account-file /path/to/key.json

HOW TO FIND YOUR PROJECT ID:
    gcloud config get-value project

NOTES:
    - Workload Identity is more secure and recommended for GKE
    - Service account needs "DNS Administrator" role on the Cloud DNS zone
    - No webhook required - Google Cloud DNS support is built into cert-manager
EOF
            ;;
        digitalocean)
            cat << EOF
DigitalOcean DNS Configuration
===============================

DigitalOcean has built-in support in cert-manager and uses API tokens.

REQUIREMENTS:
    --api-token TOKEN           DigitalOcean API Token

HOW TO GET AN API TOKEN:
    1. Log in to your DigitalOcean account
    2. Go to API section: https://cloud.digitalocean.com/account/api/tokens
    3. Click "Generate New Token"
    4. Give it a name (e.g., "cert-manager")
    5. Make sure "Write" scope is enabled
    6. Copy the generated token (shown only once)

EXAMPLE:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin digitalocean --api-token YOUR_TOKEN

NOTES:
    - Your domain must be managed by DigitalOcean DNS
    - The token needs write access to manage DNS records
    - No webhook required - DigitalOcean support is built into cert-manager
    - Store your token securely; it won't be shown again
EOF
            ;;
        acmedns)
            cat << EOF
ACME-DNS Configuration
======================

ACME-DNS is a limited DNS server designed specifically for ACME DNS challenges.

REQUIREMENTS:
    --nameserver HOST           ACME-DNS server hostname (e.g., auth.acme-dns.io)
    --username USERNAME         ACME-DNS username
    --password PASSWORD         ACME-DNS password
    --api-key KEY               ACME-DNS subdomain (fulldomain)

WHAT IS ACME-DNS?
    ACME-DNS is a specialized DNS server that only handles TXT records for ACME
    challenges. It's useful when you can't give cert-manager access to your
    main DNS provider.

HOW TO SET UP:
    1. Register with an ACME-DNS server (or run your own):
       curl -X POST https://auth.acme-dns.io/register
    2. You'll receive:
       - subdomain (use as --api-key)
       - username (use as --username)
       - password (use as --password)
    3. Create a CNAME record in your main DNS:
       _acme-challenge.example.com. IN CNAME <subdomain>.auth.acme-dns.io.

EXAMPLE:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin acmedns --nameserver auth.acme-dns.io \\
       --username YOUR_USERNAME --password YOUR_PASSWORD \\
       --api-key YOUR_SUBDOMAIN

NOTES:
    - ACME-DNS is a secure way to handle DNS challenges without full DNS access
    - You need to set up the CNAME delegation in your primary DNS
    - Public ACME-DNS servers: auth.acme-dns.io
    - You can also self-host ACME-DNS
EOF
            ;;
        rfc2136)
            cat << EOF
RFC2136 Dynamic DNS Configuration
==================================

RFC2136 is a protocol for dynamic DNS updates, commonly used with BIND and other
DNS servers that support TSIG authentication.

REQUIREMENTS:
    --nameserver HOST           DNS server hostname/IP (e.g., ns1.example.com:53)
    --tsig-key-name NAME        TSIG key name
    --tsig-secret SECRET        TSIG secret (base64 encoded)
    --tsig-algorithm ALG        TSIG algorithm (default: HMACSHA256)

SUPPORTED ALGORITHMS:
    - HMACMD5
    - HMACSHA1
    - HMACSHA256 (recommended)
    - HMACSHA512

HOW TO SET UP WITH BIND:
    1. Generate a TSIG key:
       tsig-keygen -a HMAC-SHA256 cert-manager > cert-manager.key

    2. Add the key to your BIND configuration (named.conf):
       include "/etc/bind/cert-manager.key";

    3. Allow updates in your zone configuration:
       zone "example.com" {
           type master;
           file "/etc/bind/zones/example.com";
           allow-update { key "cert-manager"; };
       };

    4. Reload BIND:
       rndc reload

EXAMPLE:
    $0 --email user@example.com --domain example.com --challenge dns01 \\
       --dns-plugin rfc2136 --nameserver ns1.example.com:53 \\
       --tsig-key-name cert-manager --tsig-secret BASE64_SECRET \\
       --tsig-algorithm HMACSHA256

NOTES:
    - RFC2136 works with any DNS server supporting dynamic updates
    - Most commonly used with BIND9
    - The DNS server must be configured to accept updates from the TSIG key
    - Ensure firewall allows access to DNS server from your cluster
    - No webhook required - RFC2136 support is built into cert-manager
EOF
            ;;
        *)
            echo "Unknown plugin: $plugin"
            echo ""
            echo "Supported plugins: godaddy, rackspace, cloudflare, route53, azuredns, google, digitalocean, acmedns, rfc2136"
            echo ""
            echo "Use: $0 --help PLUGIN for detailed information"
            exit 1
            ;;
    esac
}

# Initialize variables
ACME_EMAIL=""
GATEWAY_DOMAIN=""
CHALLENGE_METHOD="http01"
DNS_PLUGIN="godaddy"

# Generic credential variables
API_KEY=""
API_SECRET=""
API_TOKEN=""
USERNAME=""
PASSWORD=""
PROJECT_ID=""
TENANT_ID=""
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
REGION=""
HOSTED_ZONE_ID=""
SERVICE_ACCOUNT_FILE=""
NAMESERVER=""
TSIG_KEY_NAME=""
TSIG_SECRET=""
TSIG_ALGORITHM="HMACSHA256"

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
        --api-key)
            API_KEY="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --api-secret)
            API_SECRET="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --api-token)
            API_TOKEN="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --username)
            USERNAME="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --project-id)
            PROJECT_ID="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --tenant-id)
            TENANT_ID="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --subscription-id)
            SUBSCRIPTION_ID="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --region)
            REGION="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --hosted-zone-id)
            HOSTED_ZONE_ID="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --service-account-file)
            SERVICE_ACCOUNT_FILE="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --nameserver)
            NAMESERVER="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --tsig-key-name)
            TSIG_KEY_NAME="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --tsig-secret)
            TSIG_SECRET="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --tsig-algorithm)
            TSIG_ALGORITHM="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -h|--help)
            if [[ -n "$2" && "$2" != -* ]]; then
                # Detailed help for specific plugin
                usage_plugin "$2"
                exit 0
            else
                # General help
                usage
                exit 0
            fi
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

# Validate DNS plugin
VALID_PLUGINS="godaddy rackspace cloudflare route53 azuredns google digitalocean acmedns rfc2136"
if [[ "$CHALLENGE_METHOD" == "dns01" ]]; then
    if [[ ! " $VALID_PLUGINS " =~ " $DNS_PLUGIN " ]]; then
        echo "Error: Invalid DNS plugin. Must be one of: $VALID_PLUGINS"
        echo "Use --help PLUGIN for detailed information about a specific plugin"
        exit 1
    fi
fi

# Interactive prompts (fallback for missing parameters)
if [[ "$INTERACTIVE_MODE" == "true" ]]; then
    if [ -z "${ACME_EMAIL}" ]; then
        read -rp "Enter email address for ACME (press enter to skip ACME setup): " ACME_EMAIL
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

# Function to validate and prompt for credentials based on DNS plugin
validate_credentials() {
    local plugin="$1"

    case "$plugin" in
        godaddy)
            if [[ -z "$API_KEY" || -z "$API_SECRET" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "GoDaddy requires API credentials. Get them from: https://developer.godaddy.com/keys"
                    read -rp "Enter your GoDaddy API Key: " API_KEY
                    read -rsp "Enter your GoDaddy API Secret: " API_SECRET
                    echo
                else
                    echo "Error: GoDaddy requires --api-key and --api-secret"
                    echo "Use: $0 --help godaddy for more information"
                    exit 1
                fi
            fi
            ;;
        rackspace)
            if [[ -z "$USERNAME" || -z "$API_KEY" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "Rackspace requires your account credentials."
                    read -rp "Enter your Rackspace username: " USERNAME
                    read -rsp "Enter your Rackspace API Key: " API_KEY
                    echo
                else
                    echo "Error: Rackspace requires --username and --api-key"
                    echo "Use: $0 --help rackspace for more information"
                    exit 1
                fi
            fi
            ;;
        cloudflare)
            if [[ -z "$API_TOKEN" && ( -z "$API_KEY" || -z "$ACME_EMAIL" ) ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "Cloudflare supports two authentication methods:"
                    echo "  1. API Token (recommended - more secure)"
                    echo "  2. API Key (requires email + key)"
                    echo ""
                    read -rp "Do you want to use API Token? (y/n) [y]: " USE_TOKEN
                    USE_TOKEN=${USE_TOKEN:-y}

                    if [[ "$USE_TOKEN" == "y" || "$USE_TOKEN" == "Y" ]]; then
                        echo "Create a token at: User Profile > API Tokens > Create Token"
                        read -rsp "Enter your Cloudflare API Token: " API_TOKEN
                        echo
                    else
                        if [ -z "${ACME_EMAIL}" ]; then
                            read -rp "Enter your Cloudflare account email: " ACME_EMAIL
                        fi
                        echo "Get your API key at: User Profile > API Tokens > Global API Key"
                        read -rsp "Enter your Cloudflare API Key: " API_KEY
                        echo
                    fi
                else
                    echo "Error: Cloudflare requires either:"
                    echo "  --api-token TOKEN (recommended), or"
                    echo "  --api-key KEY --email EMAIL"
                    echo "Use: $0 --help cloudflare for more information"
                    exit 1
                fi
            fi
            ;;
        route53)
            # Route53 can work with IAM roles (no creds needed) or explicit credentials
            if [[ -n "$API_KEY" && -z "$API_SECRET" ]] || [[ -z "$API_KEY" && -n "$API_SECRET" ]]; then
                echo "Error: Route53 requires both --api-key (Access Key ID) and --api-secret (Secret Access Key), or neither (for IAM role)"
                echo "Use: $0 --help route53 for more information"
                exit 1
            fi
            # Set default region if not provided
            REGION=${REGION:-us-east-1}
            ;;
        azuredns)
            if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "Azure DNS requires subscription and resource group information."
                    read -rp "Enter your Azure Subscription ID: " SUBSCRIPTION_ID
                    read -rp "Enter your Azure Resource Group: " RESOURCE_GROUP
                else
                    echo "Error: Azure DNS requires --subscription-id and --resource-group"
                    echo "Use: $0 --help azuredns for more information"
                    exit 1
                fi
            fi
            # Check if using Service Principal or Managed Identity
            if [[ -n "$API_KEY" || -n "$API_SECRET" || -n "$TENANT_ID" ]]; then
                # Service Principal mode - all three required
                if [[ -z "$TENANT_ID" || -z "$API_KEY" || -z "$API_SECRET" ]]; then
                    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                        echo ""
                        echo "Service Principal authentication requires tenant ID, client ID, and client secret."
                        read -rp "Enter your Azure Tenant ID: " TENANT_ID
                        read -rp "Enter your Azure Client ID: " API_KEY
                        read -rsp "Enter your Azure Client Secret: " API_SECRET
                        echo
                    else
                        echo "Error: Azure Service Principal requires --tenant-id, --api-key (Client ID), and --api-secret (Client Secret)"
                        echo "Use: $0 --help azuredns for more information"
                        exit 1
                    fi
                fi
            fi
            ;;
        google)
            if [[ -z "$PROJECT_ID" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "Google Cloud DNS requires your project ID."
                    read -rp "Enter your GCP Project ID: " PROJECT_ID
                else
                    echo "Error: Google Cloud DNS requires --project-id"
                    echo "Use: $0 --help google for more information"
                    exit 1
                fi
            fi
            # Service account file is optional (can use Workload Identity)
            if [[ -n "$SERVICE_ACCOUNT_FILE" && ! -f "$SERVICE_ACCOUNT_FILE" ]]; then
                echo "Error: Service account file not found: $SERVICE_ACCOUNT_FILE"
                exit 1
            fi
            ;;
        digitalocean)
            if [[ -z "$API_TOKEN" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "DigitalOcean requires an API token. Get one at: https://cloud.digitalocean.com/account/api/tokens"
                    read -rsp "Enter your DigitalOcean API Token: " API_TOKEN
                    echo
                else
                    echo "Error: DigitalOcean requires --api-token"
                    echo "Use: $0 --help digitalocean for more information"
                    exit 1
                fi
            fi
            ;;
        acmedns)
            if [[ -z "$NAMESERVER" || -z "$API_KEY" || -z "$USERNAME" || -z "$PASSWORD" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "ACME-DNS requires registration information from your ACME-DNS server."
                    read -rp "Enter ACME-DNS server hostname: " NAMESERVER
                    read -rp "Enter ACME-DNS username: " USERNAME
                    read -rsp "Enter ACME-DNS password: " PASSWORD
                    echo
                    read -rp "Enter ACME-DNS subdomain (fulldomain): " API_KEY
                else
                    echo "Error: ACME-DNS requires --nameserver, --username, --password, and --api-key"
                    echo "Use: $0 --help acmedns for more information"
                    exit 1
                fi
            fi
            ;;
        rfc2136)
            if [[ -z "$NAMESERVER" || -z "$TSIG_KEY_NAME" || -z "$TSIG_SECRET" ]]; then
                if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                    echo ""
                    echo "RFC2136 requires DNS server and TSIG authentication information."
                    read -rp "Enter DNS server hostname:port (e.g., ns1.example.com:53): " NAMESERVER
                    read -rp "Enter TSIG key name: " TSIG_KEY_NAME
                    read -rsp "Enter TSIG secret (base64): " TSIG_SECRET
                    echo
                    read -rp "Enter TSIG algorithm [HMACSHA256]: " TSIG_ALG_INPUT
                    TSIG_ALGORITHM=${TSIG_ALG_INPUT:-HMACSHA256}
                else
                    echo "Error: RFC2136 requires --nameserver, --tsig-key-name, and --tsig-secret"
                    echo "Use: $0 --help rfc2136 for more information"
                    exit 1
                fi
            fi
            ;;
    esac
}

# Validate credentials if using DNS01
if [[ "$CHALLENGE_METHOD" == "dns01" ]]; then
    validate_credentials "$DNS_PLUGIN"
fi

# Display configuration
echo "Configuration:"
echo "  Email: ${ACME_EMAIL:-"(not provided - ACME setup will be skipped)"}"
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
        case "${DNS_PLUGIN}" in
            godaddy)
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
                    --from-literal=token="${API_KEY}:${API_SECRET}" \
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
                ;;
            rackspace)
                echo "Setting up Rackspace Webhook for DNS01 challenge..."

                # Clone Rackspace webhook repository if not already present
                if [ ! -d "/opt/cert-manager-webhook-rackspace" ]; then
                    echo "Cloning Rackspace webhook repository..."
                    cd /opt
                    sudo git clone https://github.com/rackerlabs/cert-manager-webhook-rackspace.git
                else
                    echo "Rackspace webhook repository already exists, updating..."
                    cd /opt/cert-manager-webhook-rackspace
                    sudo git pull
                fi

                # Install Rackspace webhook from local chart
                echo "Installing Rackspace webhook from local chart..."
                helm install cert-manager-webhook-rackspace \
                    /opt/cert-manager-webhook-rackspace/charts/cert-manager-webhook-rackspace \
                    -n cert-manager \
                    --set groupName=acme.${GATEWAY_DOMAIN}

                # Create secret for Rackspace API credentials
                echo "Creating Rackspace API credentials secret..."
                kubectl create secret generic cert-manager-webhook-rackspace-creds \
                    --namespace cert-manager \
                    --from-literal=username="${USERNAME}" \
                    --from-literal=api-key="${API_KEY}" \
                    --dry-run=client -o yaml | kubectl apply -f -

                # Create ClusterIssuer for DNS01 with Rackspace
                echo "Creating ClusterIssuer for DNS01 with Rackspace webhook..."
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
          solverName: rackspace
          config:
            authSecretRef: cert-manager-webhook-rackspace-creds
            domainName: ${GATEWAY_DOMAIN}
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                ;;
            cloudflare)
                echo "Setting up Cloudflare for DNS01 challenge..."

                # Determine which auth method to use
                if [ -n "${API_TOKEN}" ]; then
                    # API Token method (recommended)
                    echo "Using Cloudflare API Token authentication..."

                    # Create secret for Cloudflare API token
                    echo "Creating Cloudflare API Token secret..."
                    kubectl create secret generic cloudflare-api-token-secret \
                        --namespace cert-manager \
                        --from-literal=api-token="${API_TOKEN}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    # Create ClusterIssuer for DNS01 with Cloudflare API Token
                    echo "Creating ClusterIssuer for DNS01 with Cloudflare API Token..."
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
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                else
                    # API Key method
                    echo "Using Cloudflare API Key authentication..."

                    # Create secret for Cloudflare API key
                    echo "Creating Cloudflare API Key secret..."
                    kubectl create secret generic cloudflare-api-key-secret \
                        --namespace cert-manager \
                        --from-literal=api-key="${API_KEY}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    # Create ClusterIssuer for DNS01 with Cloudflare API Key
                    echo "Creating ClusterIssuer for DNS01 with Cloudflare API Key..."
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
        cloudflare:
          email: ${ACME_EMAIL}
          apiKeySecretRef:
            name: cloudflare-api-key-secret
            key: api-key
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                fi
                ;;
            route53)
                echo "Setting up Route53 for DNS01 challenge..."

                if [ -n "${API_KEY}" ]; then
                    # Using explicit credentials
                    echo "Using explicit AWS credentials..."

                    # Create secret for AWS credentials
                    echo "Creating AWS credentials secret..."
                    kubectl create secret generic route53-credentials \
                        --namespace cert-manager \
                        --from-literal=access-key-id="${API_KEY}" \
                        --from-literal=secret-access-key="${API_SECRET}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    # Create ClusterIssuer with explicit credentials
                    echo "Creating ClusterIssuer for DNS01 with Route53..."
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
        route53:
          region: ${REGION}
          accessKeyID: ${API_KEY}
          secretAccessKeySecretRef:
            name: route53-credentials
            key: secret-access-key
$([ -n "${HOSTED_ZONE_ID}" ] && echo "          hostedZoneID: ${HOSTED_ZONE_ID}")
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                else
                    # Using IAM role (no credentials needed)
                    echo "Using IAM role for authentication..."

                    # Create ClusterIssuer without credentials (uses IAM role)
                    echo "Creating ClusterIssuer for DNS01 with Route53..."
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
        route53:
          region: ${REGION}
$([ -n "${HOSTED_ZONE_ID}" ] && echo "          hostedZoneID: ${HOSTED_ZONE_ID}")
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                fi
                ;;
            azuredns)
                echo "Setting up Azure DNS for DNS01 challenge..."

                if [ -n "${TENANT_ID}" ]; then
                    # Using Service Principal
                    echo "Using Azure Service Principal authentication..."

                    # Create secret for Azure Service Principal
                    echo "Creating Azure Service Principal secret..."
                    kubectl create secret generic azuredns-credentials \
                        --namespace cert-manager \
                        --from-literal=client-secret="${API_SECRET}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    # Create ClusterIssuer with Service Principal
                    echo "Creating ClusterIssuer for DNS01 with Azure DNS..."
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
        azureDNS:
          subscriptionID: ${SUBSCRIPTION_ID}
          resourceGroupName: ${RESOURCE_GROUP}
          hostedZoneName: ${GATEWAY_DOMAIN}
          environment: AzurePublicCloud
          tenantID: ${TENANT_ID}
          clientID: ${API_KEY}
          clientSecretSecretRef:
            name: azuredns-credentials
            key: client-secret
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                else
                    # Using Managed Identity
                    echo "Using Azure Managed Identity authentication..."

                    # Create ClusterIssuer with Managed Identity
                    echo "Creating ClusterIssuer for DNS01 with Azure DNS..."
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
        azureDNS:
          subscriptionID: ${SUBSCRIPTION_ID}
          resourceGroupName: ${RESOURCE_GROUP}
          hostedZoneName: ${GATEWAY_DOMAIN}
          environment: AzurePublicCloud
$([ -n "${API_KEY}" ] && echo "          managedIdentity:")
$([ -n "${API_KEY}" ] && echo "            clientID: ${API_KEY}")
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                fi
                ;;
            google)
                echo "Setting up Google Cloud DNS for DNS01 challenge..."

                if [ -n "${SERVICE_ACCOUNT_FILE}" ]; then
                    # Using Service Account file
                    echo "Using Google Service Account file authentication..."

                    # Create secret from service account file
                    echo "Creating Google Service Account secret..."
                    kubectl create secret generic clouddns-service-account \
                        --namespace cert-manager \
                        --from-file=key.json="${SERVICE_ACCOUNT_FILE}" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    # Create ClusterIssuer with Service Account
                    echo "Creating ClusterIssuer for DNS01 with Google Cloud DNS..."
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
        cloudDNS:
          project: ${PROJECT_ID}
          serviceAccountSecretRef:
            name: clouddns-service-account
            key: key.json
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                else
                    # Using Workload Identity
                    echo "Using Google Workload Identity authentication..."

                    # Create ClusterIssuer without credentials (uses Workload Identity)
                    echo "Creating ClusterIssuer for DNS01 with Google Cloud DNS..."
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
        cloudDNS:
          project: ${PROJECT_ID}
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                fi
                ;;
            digitalocean)
                echo "Setting up DigitalOcean for DNS01 challenge..."

                # Create secret for DigitalOcean API token
                echo "Creating DigitalOcean API Token secret..."
                kubectl create secret generic digitalocean-dns \
                    --namespace cert-manager \
                    --from-literal=access-token="${API_TOKEN}" \
                    --dry-run=client -o yaml | kubectl apply -f -

                # Create ClusterIssuer for DNS01 with DigitalOcean
                echo "Creating ClusterIssuer for DNS01 with DigitalOcean..."
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
        digitalocean:
          tokenSecretRef:
            name: digitalocean-dns
            key: access-token
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                ;;
            acmedns)
                echo "Setting up ACME-DNS for DNS01 challenge..."

                # Create secret for ACME-DNS credentials
                echo "Creating ACME-DNS credentials secret..."
                kubectl create secret generic acmedns-credentials \
                    --namespace cert-manager \
                    --from-literal=acmedns.json="{\"${GATEWAY_DOMAIN}\":{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\",\"fulldomain\":\"${API_KEY}\",\"subdomain\":\"${API_KEY}\",\"allowfrom\":[]}}" \
                    --dry-run=client -o yaml | kubectl apply -f -

                # Create ClusterIssuer for DNS01 with ACME-DNS
                echo "Creating ClusterIssuer for DNS01 with ACME-DNS..."
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
        acmeDNS:
          host: https://${NAMESERVER}
          accountSecretRef:
            name: acmedns-credentials
            key: acmedns.json
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                ;;
            rfc2136)
                echo "Setting up RFC2136 for DNS01 challenge..."

                # Create secret for TSIG key
                echo "Creating TSIG secret..."
                kubectl create secret generic rfc2136-credentials \
                    --namespace cert-manager \
                    --from-literal=tsig-secret="${TSIG_SECRET}" \
                    --dry-run=client -o yaml | kubectl apply -f -

                # Create ClusterIssuer for DNS01 with RFC2136
                echo "Creating ClusterIssuer for DNS01 with RFC2136..."
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
        rfc2136:
          nameserver: ${NAMESERVER}
          tsigKeyName: ${TSIG_KEY_NAME}
          tsigAlgorithm: ${TSIG_ALGORITHM}
          tsigSecretSecretRef:
            name: rfc2136-credentials
            key: tsig-secret
      selector:
        dnsZones:
        - ${GATEWAY_DOMAIN}
EOF
                ;;
            *)
                echo "Error: Unsupported DNS plugin: ${DNS_PLUGIN}"
                exit 1
                ;;
        esac
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
else
    echo "Skipping ACME configuration (no email provided)"
fi

# Process routes
sudo mkdir -p /etc/genestack/gateway-api/routes
for route in $(ls -1 /opt/genestack/etc/gateway-api/routes); do
    sed "s/your.domain.tld/${GATEWAY_DOMAIN}/g" "/opt/genestack/etc/gateway-api/routes/${route}" > "/tmp/${route}"
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
