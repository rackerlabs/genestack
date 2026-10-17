#!/bin/bash
# Description: Fetches the version for SERVICE_NAME_DEFAULT from the specified
# YAML file and executes a helm upgrade/install command with dynamic values files.

# Disable SC2124 (unused array), SC2145 (array expansion issue), SC2294 (eval)
# shellcheck disable=SC2124,SC2145,SC2294

# Service
SERVICE_NAME_DEFAULT="keystone"
SERVICE_NAMESPACE="openstack"

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

# Resolve the chart location from the service configuration.
resolve_service_chart "$SERVICE_NAME_DEFAULT" "$service_config" || exit 1

# Collect Helm values files in override order.
build_helm_args "$SERVICE_NAME_DEFAULT" || exit 1

# Collect secret-backed --set arguments from bin/services/${SERVICE_NAME_DEFAULT}.yaml.
collect_service_secret_set_args "$SERVICE_NAME_DEFAULT"
set_args=("${SECRET_HELM_SET_ARGS[@]}")

# --- Shibboleth federation detection & idempotent secret sync ---
# If the rendered chart references the `keystone-shibd-etc` secret (i.e. the
# operator has wired the keystone overlay to include ../federation), sync the
# secret from the on-host shibboleth config directory so operator edits under
# `${GENESTACK_OVERRIDES_DIR}/keystone-sp/shibboleth/` are picked up without a
# manual `kubectl create secret` step.
KEYSTONE_SHIBBOLETH_DIR="${KEYSTONE_SHIBBOLETH_DIR:-${GENESTACK_OVERRIDES_DIR}/keystone-sp/shibboleth}"
KEYSTONE_SHIBBOLETH_SECRET="keystone-shibd-etc"
# Files the operator must supply before federation can function. Everything
# else in the shibboleth directory ships as sane defaults in the repo copy at
# etc/keystone-sp/shibboleth/.
KEYSTONE_SHIBBOLETH_REQUIRED_FILES=(
    shibboleth2.xml
    sp-cert.pem
    sp-key.pem
    idp-metadata.xml
)

skip_shibboleth_secret=false
if [[ "${SKIP_SHIBBOLETH_SECRET:-}" == "1" ]]; then
    skip_shibboleth_secret=true
    echo "SKIP_SHIBBOLETH_SECRET=1 set; bypassing federation secret sync."
fi
for _arg in "$@"; do
    if [[ "$_arg" == "--dry-run" || "$_arg" == --dry-run=* ]]; then
        skip_shibboleth_secret=true
        echo "'--dry-run' detected in extra args; bypassing federation secret sync."
        break
    fi
done
unset _arg

federation_enabled=false
if ! $skip_shibboleth_secret; then
    template_command=(
        helm template "$SERVICE_NAME_DEFAULT" "$HELM_CHART_PATH"
        --version "${SERVICE_VERSION}"
        --namespace "$SERVICE_NAMESPACE"
        "${overrides_args[@]}"
        "${set_args[@]}"
        --post-renderer "$GENESTACK_OVERRIDES_DIR/kustomize/kustomize.sh"
        --post-renderer-args "$SERVICE_NAME_DEFAULT/overlay"
    )
    echo "Rendering chart to detect Shibboleth federation..."
    template_stderr="$(mk_tmp_file)"
    if ! rendered_manifests="$("${template_command[@]}" 2>"$template_stderr")"; then
        echo "Error: 'helm template' failed while detecting federation. stderr:" >&2
        cat "$template_stderr" >&2
        exit 1
    fi
    if grep -q "${KEYSTONE_SHIBBOLETH_SECRET}" <<<"$rendered_manifests"; then
        federation_enabled=true
    fi
fi

if $federation_enabled; then
    echo "Shibboleth federation detected; syncing secret '${KEYSTONE_SHIBBOLETH_SECRET}' in namespace '${SERVICE_NAMESPACE}'."
    if [[ ! -d "$KEYSTONE_SHIBBOLETH_DIR" ]]; then
        echo "Error: Shibboleth config directory not found: $KEYSTONE_SHIBBOLETH_DIR" >&2
        echo "See docs/openstack-keystone-federation.md for how to populate this directory." >&2
        exit 1
    fi
    missing_required=()
    for required in "${KEYSTONE_SHIBBOLETH_REQUIRED_FILES[@]}"; do
        if [[ ! -f "$KEYSTONE_SHIBBOLETH_DIR/$required" ]]; then
            missing_required+=("$required")
        fi
    done
    if (( ${#missing_required[@]} > 0 )); then
        echo "Error: Federation is enabled but the following required file(s) are missing under ${KEYSTONE_SHIBBOLETH_DIR}:" >&2
        for f in "${missing_required[@]}"; do
            echo "  - $f" >&2
        done
        echo "Refer to docs/openstack-keystone-federation.md to generate/place these files." >&2
        exit 1
    fi
    if ! secret_sync_from_directory "$SERVICE_NAMESPACE" "$KEYSTONE_SHIBBOLETH_SECRET" "$KEYSTONE_SHIBBOLETH_DIR"; then
        echo "Error: failed to sync '${KEYSTONE_SHIBBOLETH_SECRET}' from ${KEYSTONE_SHIBBOLETH_DIR}." >&2
        exit 1
    fi
elif ! $skip_shibboleth_secret; then
    echo "Shibboleth federation not detected; skipping '${KEYSTONE_SHIBBOLETH_SECRET}' secret sync."
fi


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
