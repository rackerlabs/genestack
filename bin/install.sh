#!/bin/bash
# install.sh — Unified entry point for installing any genestack service.
#
# Usage:
#   install.sh --service <name> [--rotate-secrets] [--check-secrets]
#              [--yes-i-really-want-to] [--config <file>] [HELM_FLAGS...]
#
# OPTIONS:
#   --rotate-secrets              Rotate service-owned secrets and reinstall impacted services
#   --check-secrets               Report which secrets are missing, don't install
#   --yes-i-really-want-to        Auto-approve all installer confirmation prompts
#   --version <ver>               Override chart version
#   --service <name>              (required) service to install
#   --config, --gateway-config    Gateway config file applied after a successful
#                                 envoyproxy-gateway install
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
#
#   # install envoyproxy-gateway with a gateway config
#   install.sh --service envoyproxy-gateway --config /etc/genestack/gateway-config.yaml

# ── Sourcing ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
# shellcheck disable=SC2154

# ── Global state (populated by helper functions) ─────────────────────────────

CL_ROTATE_SECRETS=0
CL_CHECK_SECRETS=0
CL_FORCE_YES=0
CL_SERVICE=""
CL_EXTRA_HELM_ARGS=()
CL_OVERRIDE_VERSION=""
CL_GATEWAY_CONFIG=""

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
    svc_yaml_content=$(load_service_config "$CL_SERVICE" --log-sources) || return 1

    # Extract core fields from merged config
    local service_name service_namespace service_release
    service_name=$(echo "$svc_yaml_content" | yq e '.service.name' -)
    service_release=$(echo "$svc_yaml_content" | yq e '.service.release_name // .service.name' -)
    service_namespace=$(echo "$svc_yaml_content" | yq e '.service.namespace // "openstack"' -)
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

    # Resolve chart version before running hooks or changing cluster resources.
    local service_version
    if [[ -n "$CL_OVERRIDE_VERSION" ]]; then
        service_version="$CL_OVERRIDE_VERSION"
        log_info "Version override from CLI: ${service_version}"
    else
        service_version=$(resolve_chart_version "$CL_SERVICE" "$svc_yaml_content") || return 1
    fi
    if [[ -z "$service_version" ]]; then
        log_error "No chart version resolved for '${CL_SERVICE}'."
        return 1
    fi

    log_header "Installing service: ${service_name} (release: ${service_release}, namespace: ${service_namespace})"

    helm_set_args=()
    # Service actions can append conditional values before arguments are built.
    local additional_base_values=()

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

    resolve_service_chart "$CL_SERVICE" "$svc_yaml_content" || return 1

    # ── Build helm -f override args ───────────────────────────────────────

    local override_lines
    override_lines=$(build_helm_args "$svc_yaml_content" "${additional_base_values[@]}") || return 1
    local helm_timeout
    helm_timeout=$(resolve_helm_timeout "$svc_yaml_content")

    # ── Pre-install secret bootstrap ──────────────────────────────────────

    if ! secret_ensure_service "$svc_yaml_content" "$service_name"; then
        log_error "Failed to ensure secrets for '${service_name}'."
        exit 1
    fi

    # Non-blocking guardrail for clusters with inherited chart defaults.
    if [[ "${GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN:-0}" != "1" ]]; then
        secret_warn_default_chart_passwords "$service_name"
    fi

    # ── Build --set args from secrets ─────────────────────────────────────

    local set_args_raw
    if ! set_args_raw=$(secret_prepare_for_service "$svc_yaml_content" "$CL_SERVICE" 0); then
        log_error "Failed to prepare secret-backed Helm arguments for '${CL_SERVICE}'. Refusing to run Helm with chart defaults."
        exit 1
    fi

    # Pre-flight safety checks that inspect the fully-assembled Helm argument
    # set (service-specific guards; they never print secret values).
    if [[ "$service_name" == "blazar" ]]; then
        # The guard also inspects user-passed flags (last --set wins).
        verify_blazar_os_admin_password "$set_args_raw" "$(printf '%s\n' "${CL_EXTRA_HELM_ARGS[@]:-}")" || exit 1
    fi

    # ── Prepare kustomize post-renderer args ──────────────────────────────

    # With --config the service may select a different overlay (for example the
    # Envoy config-mode overlay that omits the legacy flex-gateway resources).
    local renderer_mode=""
    [[ -n "$CL_GATEWAY_CONFIG" ]] && renderer_mode="gateway-config"

    local post_renderer_args=""
    post_renderer_args=$(build_post_renderer_args "$svc_yaml_content" "$service_name" "$renderer_mode")

    if [[ -n "$renderer_mode" && -n "$post_renderer_args" ]]; then
        ensure_kustomize_overlay_path \
            "$(resolve_kustomize_overlay_path "$svc_yaml_content" "$service_name" "$renderer_mode")" || return 1
    fi

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
    crd_name=$(echo "$svc_yaml_content" | yq e '.chart.service_crds // .crd_chart // ""' -)
    if [[ -n "$crd_name" && "$crd_name" != '""' ]]; then
        # For mariadb-operator, install CRDs first, then main chart
        helm_install_crds "$service_name" "$crd_name" "$service_version" "$HELM_CHART_PATH" "$service_namespace" "$helm_timeout" || return 1
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

    if [[ "$helm_status" -eq 0 && -n "$CL_GATEWAY_CONFIG" ]]; then
        log_header "Waiting for ${service_name} to be available"
        if "$KUBECTL_BIN" -n "$service_namespace" wait --timeout=5m \
            deployments.apps/envoy-gateway --for=condition=available; then
            log_header "Applying gateway config: ${CL_GATEWAY_CONFIG}"
            "${SCRIPT_DIR}/setup-envoy-gateway.sh" --config "$CL_GATEWAY_CONFIG" ||
                log_error "Failed to apply gateway config for '${service_name}'."
        else
            log_error "'${service_name}' did not become available; gateway config was not applied."
            helm_status=1
        fi
    fi

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
