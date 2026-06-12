#!/bin/bash
# install.sh — Unified entry point for installing any genestack service.
#
# Usage:
#   install.sh --service <name> [--rotate-secrets] [--check-secrets] [HELM_FLAGS...]
#
# OPTIONS:
#   --rotate-secrets              Rotate service-owned secrets and reinstall impacted services
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
#   # rotate service-owned secrets and reinstall impacted services
#   install.sh --rotate-secrets --service nova
#
#   # check what secrets will be used (fails if any are missing)
#   install.sh --check-secrets --service nova

# ── Sourcing ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
# shellcheck disable=SC2154

# ── Global state (populated by helper functions) ─────────────────────────────

CL_ROTATE_SECRETS=0
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
    local repo_url repo_name
    repo_url=$(echo "$svc_yaml_content" | yq e '.chart.repo_url // ""' -)
    repo_name=$(echo "$svc_yaml_content" | yq e '.chart.repo_name // ""' -)
    : "${repo_url:=https://tarballs.opendev.org/openstack/openstack-helm}"
    : "${repo_name:=openstack-helm}"

    # Resolve chart name from config or derive from service name
    local chart_name
    chart_name=$(echo "$svc_yaml_content" | yq e '.chart.service_name // .service.name' -)
    : "${chart_name:=$service_name}"

    # ── Rotation mode ─────────────────────────────────────────────────────

    if [[ "${CL_ROTATE_SECRETS}" -eq 1 ]]; then
        rotation_execute_for_service "$svc_yaml_content" "$CL_SERVICE"
        exit $?
    fi

    # ── Check-secrets mode ────────────────────────────────────────────────

    if [[ "${CL_CHECK_SECRETS}" -eq 1 ]]; then
        log_header "Checking secrets for service '${CL_SERVICE}'"
        if ! secret_prepare_for_service "$svc_yaml_content" "$CL_SERVICE" 1 >/dev/null; then
            log_error "One or more secrets are missing. Run without --check-secrets to auto-create them."
            exit 1
        else
            log_info "All secrets OK for '${CL_SERVICE}'."
        fi
        exit 0
    fi

    # Resolve chart version
    if [[ -n "$CL_OVERRIDE_VERSION" ]]; then
        service_version="$CL_OVERRIDE_VERSION"
        log_info "Version override from CLI: ${service_version}"
    else
        service_version=$(resolve_chart_version "$service_name" "$svc_yaml_content")
    fi

    log_header "Installing service: ${service_name} (release: ${service_release}, namespace: ${service_namespace})"
    [[ -n "$service_version" ]] && log_info "Version: ${service_version}"
    log_info "Chart repo: ${repo_name} / ${repo_url}"

    helm_set_args=()

    # ── Pre-install hooks ─────────────────────────────────────────────────

    if [[ "$(echo "$svc_yaml_content" | yq e '.pre_install_actions | length // 0' -)" -gt 0 ]]; then
        log_header "Running pre-install hook for '${service_name}'"
        run_service_actions "$svc_yaml_content" '.pre_install_actions' "$service_name"
    fi

    # ── Kube-OVN TLS auto-detection (for neutron/octavia) ────────────────

    if [[ "$(echo "$svc_yaml_content" | yq e '.pre_install_check_actions | length // 0' -)" -gt 0 ]]; then
        log_header "Running pre-install checks for '${service_name}'"
        run_service_actions "$svc_yaml_content" '.pre_install_check_actions' "$service_name"
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
    local helm_timeout
    helm_timeout=$(resolve_helm_timeout "$svc_yaml_content")

    # ── Pre-install secret bootstrap ──────────────────────────────────────

    secret_ensure_service "$svc_yaml_content" "$service_name"

    # ── Build --set args from secrets ─────────────────────────────────────

    local set_args_raw
    set_args_raw=$(secret_prepare_for_service "$svc_yaml_content" "$CL_SERVICE" 0)

    # ── Prepare kustomize post-renderer args ──────────────────────────────

    local post_renderer_args=""
    post_renderer_args=$(build_post_renderer_args "$svc_yaml_content" "$service_name")

    # ── Multi-chart install check ─────────────────────────────────────────

    local multi_chart_count
    multi_chart_count=$(echo "$svc_yaml_content" | yq e '.multi_charts | length' -)

    if [[ "${multi_chart_count}" -gt 0 ]]; then
        log_header "Multi-chart install for '${service_name}'"
        multi_chart_install "$svc_yaml_content" "$service_name" "$service_version" "$helm_timeout" "$override_lines" "$set_args_raw" "$post_renderer_args"
        return $?
    fi

    # ── CRD-first install check (mariadb-operator) ────────────────────────

    local crd_name
    crd_name=$(echo "$svc_yaml_content" | yq e '.crd_chart // ""' -)
    if [[ -n "$crd_name" && "$crd_name" != '""' ]]; then
        # For mariadb-operator, install CRDs first, then main chart
        local crd_repo_name="${repo_name}-crds"
        helm_install_crds "$service_name" "$crd_name" "$service_version" "$crd_repo_name" "$repo_url" "$helm_timeout"
    fi

    # ── Assemble final helm command ───────────────────────────────────────

    local helm_cmd=()
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        helm_cmd+=("$token")
    done < <(build_helm_upgrade_install_cmd \
        "$service_release" \
        "$HELM_CHART_PATH" \
        "$service_namespace" \
        "$service_version" \
        "$helm_timeout" \
        "$override_lines" \
        "$set_args_raw" \
        "$post_renderer_args" \
        "${CL_EXTRA_HELM_ARGS[@]}")

    log_header "Executing helm for ${service_name}"
    printf '%q ' "${helm_cmd[@]}"
    printf '\n\n'

    "${helm_cmd[@]}"
    local helm_status=$?

    # ── Post-install hooks ────────────────────────────────────────────────

    if [[ "$(echo "$svc_yaml_content" | yq e '.post_install_actions | length // 0' -)" -gt 0 ]]; then
        if [[ "$helm_status" -eq 0 ]]; then
            log_header "Running post-install hook for '${service_name}'"
            run_service_actions "$svc_yaml_content" '.post_install_actions' "$service_name"
        else
            log_warn "Skipping post-install hook for '${service_name}' due to Helm failure."
        fi
    fi

    return $helm_status
}

main "$@"
