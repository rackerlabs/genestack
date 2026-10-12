#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME_DEFAULT="kube-ovn"
SERVICE_NAMESPACE="kube-system" # Note: kube-ovn uses the kube-system namespace

# Base directories provided by the environment
GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

# Common secret helpers. Missing secrets are generated in Kubernetes and
# existing secrets are never overwritten.
# shellcheck source=helpers.sh
source "${GENESTACK_BASE_DIR}/bin/helpers.sh"
trap cleanup_tmp EXIT

# Load the service configuration once for this installer.
service_config=$(load_service_config "$SERVICE_NAME_DEFAULT" --log-sources) || exit 1

# Resolve the chart version from the service config or chart versions file.
SERVICE_VERSION=$(resolve_chart_version "$SERVICE_NAME_DEFAULT" "$service_config") || exit 1

if [[ -z "$SERVICE_VERSION" ]]; then
    log_error "No chart version found for '$SERVICE_NAME_DEFAULT'."
    exit 1
fi

# --- Kube-OVN specific logic to determine masters and replica count ---
MASTER_NODES=$(kubectl get nodes -l kube-ovn/role=master -o json | jq -r '[.items[].status.addresses[] | select(.type == "InternalIP") | .address] | join(",")' | sed 's/,/\\,/g')
MASTER_NODE_COUNT=$(kubectl get nodes -l kube-ovn/role=master -o json | jq -r '.items[].status.addresses[] | select(.type=="InternalIP") | .address' | wc -l)

if [ "${MASTER_NODE_COUNT}" -eq 0 ]; then
    echo "Error: No master nodes found labeled with 'kube-ovn/role=master'" >&2
    echo "Be sure to label your master nodes with 'kube-ovn/role=master' before running this script." >&2
    exit 1
fi
echo "Found $MASTER_NODE_COUNT master node(s) with IPs: ${MASTER_NODES//\\,/ }."
# --------------------------------------------------------------------

# Generate OVN TLS cert with proper DNS SANs if it doesn't exist yet
if ! secret_exists "$SERVICE_NAMESPACE" kube-ovn-tls; then
    echo "Generating kube-ovn-tls secret with DNS SANs..."
    ovn_tls_dir="$(mk_tmp_dir)"
    openssl genrsa -out "${ovn_tls_dir}/ovn-ca-key.pem" 2048 2>/dev/null
    openssl req -x509 -new -key "${ovn_tls_dir}/ovn-ca-key.pem" -out "${ovn_tls_dir}/ovn-ca.pem" -days 3650 -subj "/CN=ovn-ca"
    openssl genrsa -out "${ovn_tls_dir}/ovn-key.pem" 2048 2>/dev/null
    openssl req -new -key "${ovn_tls_dir}/ovn-key.pem" -out "${ovn_tls_dir}/ovn.csr" -subj "/CN=ovn"
    openssl x509 -req -in "${ovn_tls_dir}/ovn.csr" -CA "${ovn_tls_dir}/ovn-ca.pem" -CAkey "${ovn_tls_dir}/ovn-ca-key.pem" -CAcreateserial \
      -out "${ovn_tls_dir}/ovn-cert.pem" -days 3650 \
      -extfile <(printf "subjectAltName=DNS:ovn,DNS:ovn-nb,DNS:ovn-nb.kube-system.svc,DNS:ovn-sb,DNS:ovn-sb.kube-system.svc,DNS:ovn-northd,DNS:ovn-northd.kube-system.svc")
    if ! secret_sync_from_files "$SERVICE_NAMESPACE" kube-ovn-tls \
      "cacert=${ovn_tls_dir}/ovn-ca.pem" \
      "cert=${ovn_tls_dir}/ovn-cert.pem" \
      "key=${ovn_tls_dir}/ovn-key.pem"; then
        echo "Error: failed to create ${SERVICE_NAMESPACE}/kube-ovn-tls secret." >&2
        exit 1
    fi
    if ! kubectl -n "$SERVICE_NAMESPACE" annotate secret kube-ovn-tls \
      meta.helm.sh/release-name="$SERVICE_NAME_DEFAULT" \
      meta.helm.sh/release-namespace="$SERVICE_NAMESPACE"; then
        echo "Error: failed to annotate ${SERVICE_NAMESPACE}/kube-ovn-tls secret for Helm ownership." >&2
        exit 1
    fi
    if ! kubectl -n "$SERVICE_NAMESPACE" label secret kube-ovn-tls --overwrite app.kubernetes.io/managed-by=Helm; then
        echo "Error: failed to label ${SERVICE_NAMESPACE}/kube-ovn-tls secret for Helm ownership." >&2
        exit 1
    fi
fi

# Resolve the chart location from the service configuration.
resolve_service_chart "$SERVICE_NAME_DEFAULT" "$service_config" || exit 1

# Collect Helm values files in override order.
build_helm_args "$SERVICE_NAME_DEFAULT" || exit 1

# Collect all --set arguments, executing commands and quoting safely
# Collect secret-backed --set arguments from bin/services/${SERVICE_NAME_DEFAULT}.yaml.
collect_service_secret_set_args "$SERVICE_NAME_DEFAULT"
set_args=("${SECRET_HELM_SET_ARGS[@]}")

set_args+=(
    --set "MASTER_NODES=${MASTER_NODES}"
    --set "replicaCount=${MASTER_NODE_COUNT}"
)


helm_command=(
    helm upgrade --install "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
    --version "${SERVICE_VERSION}"
    --namespace="$SERVICE_NAMESPACE"
    --timeout 120m
    --create-namespace

    "${overrides_args[@]}"
    "${set_args[@]}"

    # Post-renderer configuration
    --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
    --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"

    "$@"
)

echo "Executing Helm command (arguments are quoted safely):"
printf '%q ' "${helm_command[@]}"
echo

# Execute the command directly from the array
"${helm_command[@]}"
