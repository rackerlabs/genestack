#!/bin/bash
# install.sh — Unified entry point for installing any genestack service.
#
# Usage:
#   install.sh --service <name> [--rotate-keys] [--check-secrets] [HELM_FLAGS...]
#
# OPTIONS:
#   --rotate-keys                 Rotate secrets for the given service only
#   --check-secrets               Report which secrets are missing, don't install
#   --version <ver>               Override chart version
#   --service <name>              (required) service to install
#
# Remaining --* flags after the service name are passed through to helm upgrade --install.
#
# Examples:
#   # basic install
#   install.sh --service nova
#
#   # pass helm flags (--wait tells helm to wait for resources, --timeout sets max wait)
#   install.sh --service nova --wait --timeout 30m
#
#   # helm dry-run renders templates without applying (helm's built-in --dry-run)
#   install.sh --service nova --dry-run
#
#   # --dry-run as --set value
#   install.sh --service nova --set conf.nova.some_option="dry-run"
#
#   # rotate secrets before install
#   install.sh --rotate-keys --service nova
#
#   # check what secrets will be used (fails if any are missing)
#   install.sh --check-secrets --service nova

# ── Sourcing ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
# shellcheck disable=SC2154

# ── Global state (populated by helper functions) ─────────────────────────────

CL_ROTATE_KEYS=0
CL_CHECK_SECRETS=0
CL_SERVICE=""
CL_EXTRA_HELM_ARGS=()
CL_OVERRIDE_VERSION=""

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Step 0: Validate tools
    validate_tools

    # Step 1: Parse CLI args
    parse_cli "$@"

    # Step 2: Setup cleanup trap
    _setup_cleanup_trap

    # Step 3: Load + resolve service config
    local config_file="${GENESTACK_SERVICES_DIR}/${CL_SERVICE}.yaml"

    if [[ ! -f "$config_file" ]]; then
        log_error "Service config not found at ${config_file}"
        exit 1
    fi

    log_header "Loading service config: ${CL_SERVICE}"

    local svc_yaml_content
    svc_yaml_content=$(load_service_config "$CL_SERVICE")

    # Extract core fields from merged config
    local service_name service_namespace service_release
    service_name=$(echo "$svc_yaml_content" | yq e '.service.name' -)
    service_release=$(echo "$svc_yaml_content" | yq e '.service.release_name // .service.name' -)
    service_namespace=$(echo "$svc_yaml_content" | yq e '.service.namespace // "openstack"' -)
    local repo_url repo_name version_enabled
    repo_url=$(echo "$svc_yaml_content" | yq e '.chart.repo_url // ""' -)
    repo_name=$(echo "$svc_yaml_content" | yq e '.chart.repo_name // ""' -)
    local version_from_config
    version_from_config=$(echo "$svc_yaml_content" | yq e '.service.version // ""' -)
    : "${repo_url:=https://tarballs.opendev.org/openstack/openstack-helm}"
    : "${repo_name:=openstack-helm}"

    # Resolve chart version
    if [[ -n "$CL_OVERRIDE_VERSION" ]]; then
        service_version="$CL_OVERRIDE_VERSION"
        log_info "Version override from CLI: ${service_version}"
    else
        service_version=$(resolve_chart_version "$service_name" "$svc_yaml_content")
    fi

    # Resolve chart name from config or derive from service name
    local chart_name
    chart_name=$(echo "$svc_yaml_content" | yq e '.chart.service_name // .service.name' -)
    : "${chart_name:=$service_name}"

    log_header "Installing service: ${service_name} (release: ${service_release}, namespace: ${service_namespace})"
    [[ -n "$service_version" ]] && log_info "Version: ${service_version}"
    log_info "Chart repo: ${repo_name} / ${repo_url}"

    # ── Rotation mode ─────────────────────────────────────────────────────

    if [[ "${CL_ROTATE_KEYS}" -eq 1 ]]; then
        log_header "Secret rotation mode for '${CL_SERVICE}'"
        secret_rotate_for_service "$svc_yaml_content" "$CL_SERVICE"
        # Fall through to normal install — secrets are now fresh
    fi

    # ── Check-secrets mode ────────────────────────────────────────────────

    if [[ "${CL_CHECK_SECRETS}" -eq 1 ]]; then
        log_header "Checking secrets for service '${CL_SERVICE}'"
        local missing=0
        local result
        result=$(secret_prepare_for_service "$svc_yaml_content" "$CL_SERVICE" 1)
        if echo "$result" | grep -q "MISSING SECRET"; then
            echo "$result" | grep "MISSING SECRET" >&2
            missing=1
        fi
        if [[ $missing -ne 0 ]]; then
            log_error "One or more secrets are missing. Run without --check-secrets to auto-create them."
            exit 1
        else
            log_info "All secrets OK for '${CL_SERVICE}'."
        fi
        exit 0
    fi

    # ── Pre-install hooks ─────────────────────────────────────────────────

    local pre_install_hook
    pre_install_hook=$(echo "$svc_yaml_content" | yq e '.pre_install // ""' - | sed '/^null$/d')
    if [[ -n "$pre_install_hook" && "$pre_install_hook" != '""' ]]; then
        log_header "Running pre-install hook for '${service_name}'"
        eval "$pre_install_hook"
    fi

    # ── Kube-OVN TLS auto-detection (for neutron/octavia) ────────────────

    local pre_install_checks
    pre_install_checks=$(echo "$svc_yaml_content" | yq e '.pre_install_checks // ""' - | sed '/^null$/d')
    if [[ -n "$pre_install_checks" && "$pre_install_checks" != '""' ]]; then
        log_header "Running pre-install checks for '${service_name}'"
        eval "$pre_install_checks"
    fi

    if [[ "${CONNECTION_STRING:-}" == "ssl" || "${CONNECTION_STRING:-}" == "tcp" ]]; then
        log_info "OVN TLS enabled (${CONNECTION_STRING})"
    fi

    # ── Namespace ─────────────────────────────────────────────────────────

    ensure_namespace "$service_namespace"
    # Check if namespace label is needed (talos detection)
    label_namespace_for_talos "$service_namespace"

    # ── Resolve helm chart path ───────────────────────────────────────────

    resolve_helm_repo "$repo_url" "$repo_name" "$chart_name"

    # ── Build helm -f override args ───────────────────────────────────────

    local override_lines
    override_lines=$(build_helm_args "$svc_yaml_content")

    # ── Build --set args from secrets ─────────────────────────────────────

    local set_args_raw
    set_args_raw=$(secret_prepare_for_service "$svc_yaml_content" "$CL_SERVICE" 0)

    # ── Prepare kustomize post-renderer args ──────────────────────────────

    local post_renderer_args=""
    local kustomize_enabled
    kustomize_enabled=$(echo "$svc_yaml_content" | yq e '.kustomize.enabled // true' -)
    local overlay_path
    overlay_path=$(echo "$svc_yaml_content" | yq e '.kustomize.overlay_path // "${service_name}/overlay"' -)
    if [[ "$kustomize_enabled" == "true" && -f "$HELM_KUSTOMIZE_CMD" ]]; then
        post_renderer_args="${HELM_KUSTOMIZE_CMD} ${overlay_path}"
    fi

    # ── Multi-chart install check ─────────────────────────────────────────

    local multi_chart_count
    multi_chart_count=$(echo "$svc_yaml_content" | yq e '.multi_charts | length' -)

    if [[ "${multi_chart_count}" -gt 0 ]]; then
        log_header "Multi-chart install for '${service_name}'"
        multi_chart_install "$svc_yaml_content" "$service_name" "$service_version"
        return $?
    fi

    # ── CRD-first install check (mariadb-operator) ────────────────────────

    local crd_name
    crd_name=$(echo "$svc_yaml_content" | yq e '.crd_chart // ""' -)
    if [[ -n "$crd_name" && "$crd_name" != '""' ]]; then
        # For mariadb-operator, install CRDs first, then main chart
        log_header "Installing CRD chart: ${crd_name}"
        helm_install_crds "$service_name" "$crd_name" "$service_version" "mariadb-operator-crds" "https://helm.mariadb.com/mariadb-operator"
    fi

    # ── Assemble final helm command ───────────────────────────────────────

    local helm_cmd=()
    helm_cmd+=(helm upgrade --install "$service_release" "$HELM_CHART_PATH")

    [[ -n "$service_version" ]] && helm_cmd+=("--version=${service_version}")

    helm_cmd+=(--namespace="$service_namespace")
    helm_cmd+=(--timeout 120m)
    helm_cmd+=(--create-namespace)

    # -f argument files (base → global → custom)
    if [[ -n "$override_lines" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            helm_cmd+=(${line})
        done <<< "$override_lines"
    fi

    # --set arguments (secrets)
    if [[ -n "$set_args_raw" ]]; then
        while IFS= read -r arg; do
            [[ -z "$arg" ]] && continue
            helm_cmd+=("--set" "${arg}")
        done <<< "$set_args_raw"
    fi

    # Post-renderer
    if [[ -n "$post_renderer_args" ]]; then
        local pr_cmd pr_args
        pr_cmd=$(echo "$post_renderer_args" | awk '{print $1}')
        pr_args=$(echo "$post_renderer_args" | awk '{$1=""; print $0}' | sed 's/^ //')
        helm_cmd+=(--post-renderer "$pr_cmd" --post-renderer-args "$pr_args")
    fi

    # Extra helm args passed by user (any remaining flags)
    if [[ ${#CL_EXTRA_HELM_ARGS[@]} -gt 0 ]]; then
        helm_cmd+=("${CL_EXTRA_HELM_ARGS[@]}")
    fi

    log_header "Executing helm for ${service_name}"
    printf '%q ' "${helm_cmd[@]}"
    printf '\n\n'

    "${helm_cmd[@]}"
    local helm_status=$?

    # ── Post-install hooks ────────────────────────────────────────────────

    local post_install_hook
    post_install_hook=$(echo "$svc_yaml_content" | yq e '.post_install // ""' - | sed '/^null$/d')
    if [[ -n "$post_install_hook" && "$post_install_hook" != '""' ]]; then
        log_header "Running post-install hook for '${service_name}'"
        eval "$post_install_hook"
    fi

    return $helm_status
}

main "$@"
