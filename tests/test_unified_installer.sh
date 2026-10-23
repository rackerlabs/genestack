#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services"

# shellcheck source=../bin/helpers.sh
source "${REPO_ROOT}/bin/helpers.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" != "$actual" ]]; then
        echo "Expected:" >&2
        printf '%s\n' "$expected" >&2
        echo "Actual:" >&2
        printf '%s\n' "$actual" >&2
        fail "$message"
    fi
}

assert_file_content() {
    local file_path="$1"
    local expected="$2"
    local message="$3"

    [[ -f "$file_path" ]] || fail "${message}: missing file ${file_path}"
    assert_eq "$expected" "$(cat "$file_path")" "$message"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Missing fragment:" >&2
        printf '%s\n' "$needle" >&2
        echo "Within:" >&2
        printf '%s\n' "$haystack" >&2
        fail "$message"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "Unexpected fragment:" >&2
        printf '%s\n' "$needle" >&2
        echo "Within:" >&2
        printf '%s\n' "$haystack" >&2
        fail "$message"
    fi
}

assert_matches_regex() {
    local haystack="$1"
    local pattern="$2"
    local message="$3"

    if ! printf '%s\n' "$haystack" | grep -Eq "$pattern"; then
        echo "Missing regex match:" >&2
        printf '%s\n' "$pattern" >&2
        echo "Within:" >&2
        printf '%s\n' "$haystack" >&2
        fail "$message"
    fi
}

setup_test_components_file() {
    local tmp_root="$1"
    GENESTACK_COMPONENTS_FILE="${tmp_root}/openstack-components.yaml"
    cat > "${GENESTACK_COMPONENTS_FILE}" <<'EOF'
components:
  barbican: true
  blazar: false
  ceilometer: false
  cinder: true
  cloudkitty: false
  freezer: false
  glance: true
  gnocchi: false
  heat: false
  keystone: true
  magnum: false
  manila: false
  masakari: false
  neutron: true
  nova: true
  octavia: false
  openstack-exporter: true
  opentelemetry-kube-stack: true
  placement: true
  skyline: true
  trove: false
  zaqar: false
EOF
}

lookup_secret_value() {
    local namespace="$1"
    local secret_name="$2"
    local data_key="$3"

    case "${namespace}/${secret_name}:${data_key}" in
        openstack/nova-admin:password) echo "nova-admin-pass" ;;
        openstack/nova-db-password:password) echo "nova-db-pass" ;;
        openstack/nova-rabbitmq-password:password) echo "nova-rabbit-pass" ;;
        openstack/nova-ssh:public-key) echo "ssh-ed25519 AAAANOVA" ;;
        openstack/nova-ssh:private-key) printf '%s' "NOVA_PRIVATE_KEY" ;;
        openstack/manila-service-keypair:public_key) echo "ssh-ed25519 AAAAMANILA" ;;
        openstack/manila-service-keypair:private_key) printf '%s' "MANILA_PRIVATE_KEY" ;;
        monitoring/keystone-auth-openstack-exporter:AUTH_URL) echo "https://keystone.example/v3" ;;
        *)
            echo "${secret_name}-${data_key}-value"
            ;;
    esac
}

secret_exists() {
    return 0
}

secret_get() {
    lookup_secret_value "$1" "$2" "$3"
}

secret_get_to_file() {
    secret_get "$1" "$2" "$3" > "$4"
}

create_fake_installer_binaries() {
    local target_dir="$1"
    local kubectl_path="${target_dir}/kubectl"
    local helm_path="${target_dir}/helm"

    cat >"$kubectl_path" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ -n "${KUBECTL_LOG_FILE:-}" ]]; then
    printf '%s\n' "$*" >> "${KUBECTL_LOG_FILE}"
fi

lookup_secret() {
    local namespace="$1"
    local secret_name="$2"
    local data_key="$3"
    case "${namespace}/${secret_name}:${data_key}" in
        openstack/nova-ssh:public-key) printf '%s' "ssh-ed25519 AAAANOVA" ;;
        openstack/nova-ssh:private-key) printf '%s' "NOVA_PRIVATE_KEY" ;;
        testing/synthetic-multi-keypair:private-key) printf '%s' "MULTI_PRIVATE_KEY" ;;
        *) printf '%s' "${secret_name}-${data_key}-value" ;;
    esac
}

secret_is_missing() {
    local ref="$1/$2"
    [[ ",${MISSING_SECRET_REFS:-}," == *",${ref},"* ]]
}

secret_data_is_empty() {
    local ref="$1/$2:$3"
    [[ ",${EMPTY_SECRET_DATA_REFS:-}," == *",${ref},"* ]]
}

if [[ "${1:-}" == "get" && "${2:-}" == "secret" ]]; then
    secret_name="$3"
    namespace="default"
    jsonpath=""
    output_format=""
    shift 3

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)
                namespace="$2"
                shift 2
                ;;
            -o)
                if [[ "$2" == "json" ]]; then
                    output_format="json"
                else
                    jsonpath="$2"
                fi
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if secret_is_missing "$namespace" "$secret_name"; then
        exit 1
    fi

    if [[ "$output_format" == "json" ]]; then
        # secret_has_keys() pipes this JSON into yq and checks .data for the
        # requested keys. The key names are NOT passed to kubectl, so report
        # every data key referenced by bin/services/*.yaml (plus the shared
        # TLS/auth keys) as present so ensure/verify flows succeed.
        _sk_b64() { printf '%s-value' "$1" | base64 | tr -d '\n'; }
        _sk_out="{"
        for _sk_key in \
            ACCESS_KEY AUTH_PASSWORD AUTH_PROJECT_DOMAIN_NAME AUTH_PROJECT_NAME \
            AUTH_URL AUTH_USER_NAME AUTH_USER_PASSWORD AUTH_USER_USER_DOMAIN_NAME \
            ETCDCTL_API ETCDCTL_CACERT ETCDCTL_CERT ETCDCTL_ENDPOINTS ETCDCTL_KEY \
            OS_AUTH_URL OS_PASSWORD OS_PROJECT_DOMAIN_NAME OS_PROJECT_NAME \
            OS_USERNAME OS_USER_DOMAIN_NAME S3_BUCKET S3_ENDPOINT S3_HOST \
            S3_REGION SECRET_KEY access-key-id cacert cert cookie \
            heartbeat_key horizon_secret_key key memcache_secret_key password \
            private-key private_key public-key public_key rabbitmq_key \
            root-password root-password-credentials secret-access-key username \
            zaqar_signed_url_secret_key; do
            _sk_out+="\"${_sk_key}\":\"$(_sk_b64 "$_sk_key")\","
        done
        _sk_out="${_sk_out%,}}"
        printf '{"data":%s}\n' "$_sk_out"
        exit 0
    fi

    if [[ -n "$jsonpath" ]]; then
        data_key="${jsonpath#jsonpath=}"
        data_key="${data_key#\{.data}"
        data_key="${data_key%\}}"
        if [[ "$data_key" == \[* ]]; then
            # kubectl -o "jsonpath={.data['key']}" form: strip brackets and quotes
            data_key="${data_key#\[}"
            data_key="${data_key%\]}"
            data_key="${data_key#\'}"
            data_key="${data_key%\'}"
            # main's secret_get escapes dots in the bracketed key: private\.key
            data_key="${data_key//\\./.}"
        fi
        if secret_data_is_empty "$namespace" "$secret_name" "$data_key"; then
            exit 0
        fi
        lookup_secret "$namespace" "$secret_name" "$data_key" | base64
    else
        echo "secret/${secret_name}"
    fi
    exit 0
fi

if [[ "${1:-}" == "get" && "${2:-}" == "namespace" ]]; then
    echo "namespace/${3:-default}"
    exit 0
fi

if [[ "${1:-}" == "create" && "${2:-}" == "namespace" ]]; then
    echo "namespace/${3:-default}"
    exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "namespace" ]]; then
    exit 0
fi

if [[ "${1:-}" == "patch" && "${2:-}" == "secret" ]]; then
    exit 0
fi

if [[ "${1:-}" == "-n" ]]; then
    shift 2
fi

if [[ "${1:-}" == "wait" && "${KUBECTL_FAIL_WAIT:-0}" == "1" ]]; then
    exit 1
fi

if [[ "${1:-}" == "get" && "${2:-}" == "deploy" ]]; then
    echo "false"
    exit 0
fi

if [[ "${1:-}" == "get" && "${2:-}" == "service" ]]; then
    if [[ "${3:-}" == "ovn-nb" ]]; then
        if [[ "${5:-}" == "jsonpath={.spec.clusterIP}" ]]; then
            echo "10.0.0.10"
        else
            echo "6641"
        fi
        exit 0
    fi
    if [[ "${3:-}" == "ovn-sb" ]]; then
        if [[ "${5:-}" == "jsonpath={.spec.clusterIP}" ]]; then
            echo "10.0.0.11"
        else
            echo "6642"
        fi
        exit 0
    fi
fi

if [[ "${1:-}" == "get" && "${2:-}" == "nodes" ]]; then
    printf '10.0.0.21\n10.0.0.22\n'
    exit 0
fi

if [[ "${1:-}" == "rollout" && "${2:-}" == "status" ]]; then
    exit 0
fi

if [[ "${1:-}" == "get" && "${2:-}" == "pods" ]]; then
    echo "pod/example"
    exit 0
fi

if [[ "${1:-}" == "get" && "${2:-}" == "svc" ]]; then
    echo "service/example"
    exit 0
fi

exit 0
EOF

    cat >"$helm_path" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ -n "${HELM_LOG_FILE:-}" ]]; then
    printf '%s\n' "$*" >> "${HELM_LOG_FILE}"
fi

if [[ "${1:-}" == "upgrade" && "${2:-}" == "--install" && "${HELM_FAIL_UPGRADE:-0}" == "1" ]]; then
    exit 1
fi

exit 0
EOF

    chmod +x "$kubectl_path" "$helm_path"
}

collect_owned_secret_refs() {
    for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
        yq e '.secrets[]? | select(.rotate_with_service == true) | ((.source_namespace // .service.namespace // "openstack") + "/" + .source_secret)' "$f" 2>/dev/null || true
    done | sed '/^null$/d;/^$/d' | sort -u
}

validate_action_schemas() {
    local failures=""
    local action_paths=(".pre_install_actions" ".pre_install_check_actions" ".post_install_actions")
    local f action_path svc type node_label master_key replica_key workload resource source_ns target_ns source_secret target_secret entry_count

    for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
        svc="$(basename "$f" .yaml)"
        [[ "$svc" == "example-service" ]] && continue

        for action_path in "${action_paths[@]}"; do
            while IFS='|' read -r type node_label master_key replica_key workload resource source_ns target_ns source_secret target_secret entry_count; do
                [[ -z "$type" || "$type" == "null" ]] && continue
                case "$type" in
                    monitoring_grafana_db_secret_bootstrap)
                        ;;
                    kube_ovn_master_discovery)
                        [[ -n "$node_label" && -n "$master_key" && -n "$replica_key" ]] || failures+="${svc}:${action_path}:${type}:missing-required-fields"$'\n'
                        ;;
                    detect_kube_ovn_tls)
                        ;;
                    ensure_ovn_client_tls_secret)
                        [[ -n "$source_ns" && -n "$target_ns" && -n "$source_secret" && -n "$target_secret" ]] || failures+="${svc}:${action_path}:${type}:missing-required-fields"$'\n'
                        ;;
                    ovn_connection_set_args)
                        [[ "$entry_count" =~ ^[1-9][0-9]*$ ]] || failures+="${svc}:${action_path}:${type}:entries-required"$'\n'
                        while IFS='|' read -r entry_key entry_env; do
                            [[ -z "$entry_key" && -z "$entry_env" ]] && continue
                            [[ -n "$entry_key" && -n "$entry_env" ]] || failures+="${svc}:${action_path}:${type}:entry-missing-fields"$'\n'
                        done < <(yq e "${action_path}[]? | select(.type == \"${type}\") | .entries[]? | [(.helm_key // \"\"), (.env // \"\")] | join(\"|\")" "$f" 2>/dev/null || true)
                        ;;
                    rollout_status)
                        [[ -n "$workload" ]] || failures+="${svc}:${action_path}:${type}:workload-required"$'\n'
                        ;;
                    get_by_label_optional)
                        [[ -n "$resource" ]] || failures+="${svc}:${action_path}:${type}:resource-required"$'\n'
                        ;;
                    namespace_resource_dump_if_pods_present)
                        ;;
                    *)
                        failures+="${svc}:${action_path}:${type}:unsupported-action-type"$'\n'
                        ;;
                esac
            done < <(yq e "${action_path}[]? | [
                    (.type // \"\"),
                    (.node_label // \"\"),
                    (.master_nodes_helm_key // \"\"),
                    (.replica_count_helm_key // \"\"),
                    (.workload // \"\"),
                    (.resource // \"\"),
                    (.source_namespace // \"\"),
                    (.target_namespace // \"\"),
                    (.source_secret // \"\"),
                    (.target_secret // \"\"),
                    ((.entries | length // 0) | tostring)
                ] | join(\"|\")" "$f" 2>/dev/null || true)
        done
    done

    [[ -z "$failures" ]] || fail "invalid structured action schemas detected: ${failures}"
}

validate_value_from_and_secret_source_schemas() {
    local failures refs f svc idx value_from_type source_secret source_data_key has_keys literal_value replace_count vf_ns vf_name vf_data_key vf_ref

    refs="$(collect_owned_secret_refs)"
    failures=""

    for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
        svc="$(basename "$f" .yaml)"
        [[ "$svc" == "example-service" ]] && continue

        while IFS='|' read -r idx value_from_type source_secret source_data_key has_keys literal_value replace_count vf_ns vf_name vf_data_key; do
            [[ -z "$idx" || "$idx" == "null" ]] && continue

            if [[ -n "$value_from_type" && "$value_from_type" != "null" ]]; then
                case "$value_from_type" in
                    secret_data)
                        [[ -n "$vf_name" && -n "$vf_data_key" ]] || failures+="${svc}:secrets[${idx}]:value_from.secret_data-missing-fields"$'\n'
                        ;;
                    *)
                        failures+="${svc}:secrets[${idx}]:unsupported-value_from-type:${value_from_type}"$'\n'
                        ;;
                esac

                if [[ -n "$source_secret" || -n "$source_data_key" || "${has_keys:-0}" != "0" || -n "$literal_value" || "${replace_count:-0}" != "0" ]]; then
                    failures+="${svc}:secrets[${idx}]:mixed-secret-source-definitions"$'\n'
                fi

                vf_ref="${vf_ns}/${vf_name}"
                if printf '%s\n' "$refs" | grep -Fx "$vf_ref" >/dev/null; then
                    failures+="${svc}:secrets[${idx}]:value_from-references-owned-secret:${vf_ref}"$'\n'
                fi
            fi
        done < <(yq e '.secrets | to_entries[]? | [
                (.key | tostring),
                (.value.value_from.type // ""),
                (.value.source_secret // ""),
                (.value.data_key // ""),
                ((.value.keys | length // 0) | tostring),
                (.value.value // ""),
                ((.value.replace | length // 0) | tostring),
                (.value.value_from.namespace // .service.namespace // "openstack"),
                (.value.value_from.secret_name // ""),
                (.value.value_from.data_key // "")
            ] | join("|")' "$f" 2>/dev/null || true)
    done

    [[ -z "$failures" ]] || fail "invalid value_from/secret-source schemas detected: ${failures}"
}

test_secret_arg_formatting() {
    local nova_yaml nova_args nova_private_line nova_private_arg nova_private_path
    local manila_yaml manila_args manila_private_line manila_private_path

    nova_yaml="$(load_service_config nova)"
    nova_args="$(secret_prepare_for_service "$nova_yaml" nova 0)"

    printf '%s\n' "$nova_args" | grep -F -- $'--set	endpoints.identity.auth.nova.password=nova-admin-pass' >/dev/null \
        || fail "nova admin password should use --set"
    printf '%s\n' "$nova_args" | grep -F -- $'--set-string	network.ssh.public_key=ssh-ed25519 AAAANOVA' >/dev/null \
        || fail "nova public key should use --set-string"

    nova_private_line="$(printf '%s\n' "$nova_args" | grep -F -- $'--set-file	network.ssh.private_key=' | head -n1)"
    [[ -n "$nova_private_line" ]] || fail "nova private key should use --set-file"
    nova_private_arg="${nova_private_line#*$'\t'}"
    nova_private_path="${nova_private_arg#*=}"
    assert_file_content "$nova_private_path" "NOVA_PRIVATE_KEY" "nova private key file should contain the secret value"

    manila_yaml="$(load_service_config manila)"
    manila_args="$(secret_prepare_for_service "$manila_yaml" manila 0)"
    printf '%s\n' "$manila_args" | grep -F -- $'--set-string	network.ssh.public_key=ssh-ed25519 AAAAMANILA' >/dev/null \
        || fail "manila public key should use --set-string"
    manila_private_line="$(printf '%s\n' "$manila_args" | grep -F -- $'--set-file	network.ssh.private_key=' | head -n1)"
    [[ -n "$manila_private_line" ]] || fail "manila private key should use --set-file"
    manila_private_path="${manila_private_line#*$'\t'}"
    manila_private_path="${manila_private_path#*=}"
    assert_file_content "$manila_private_path" "MANILA_PRIVATE_KEY" "manila private key file should contain the secret value"

    assert_eq $'--set\nendpoints.identity.auth.nova.password=nova-admin-pass' \
        "$(printf '%s\n' "$nova_args" | grep -F -- $'--set	endpoints.identity.auth.nova.password=nova-admin-pass' | tr '\t' '\n')" \
        "install token parser should preserve --set pairs"
}

test_secret_arg_token_parser() {
    local parsed
    parsed="$(secret_args_to_helm_tokens $'--set\tfoo=bar\n--set-file\tbaz=/tmp/qux')"
    assert_eq $'--set\nfoo=bar\n--set-file\nbaz=/tmp/qux' "$parsed" \
        "structured secret args should flatten into alternating Helm tokens"
}

test_base64_encode_helper() {
    assert_eq "YWJj" "$(encode_base64_single_line "abc")" \
        "portable base64 helper should emit single-line output"
}

test_service_config_repo_url_overrides() {
    local service_dir override_root merged_yaml original_services_dir original_service_overrides_dir

    service_dir="$(mktemp -d)"
    override_root="$(mktemp -d)"
    mkdir -p "${override_root}/service-configs"
    original_services_dir="${GENESTACK_SERVICES_DIR}"
    original_service_overrides_dir="${GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR:-}"

    cat > "${service_dir}/openstack-common.yaml" <<'EOF'
service:
  namespace: openstack
chart:
  repo_name: openstack-helm
  repo_url: https://tarballs.opendev.org/openstack/openstack-helm
EOF

    cat > "${service_dir}/override-target.yaml" <<'EOF'
service:
  name: override-target
chart: {}
secrets: []
EOF

    cat > "${override_root}/service-configs/openstack-common.yaml" <<'EOF'
chart:
  repo_url: https://airgap.example.invalid/openstack-helm
EOF

    cat > "${override_root}/service-configs/override-target.yaml" <<'EOF'
chart:
  repo_name: airgap-openstack
  repo_url: https://airgap.example.invalid/override-target
EOF

    GENESTACK_SERVICES_DIR="${service_dir}"
    GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="${override_root}/service-configs"

    merged_yaml="$(load_service_config override-target)"

    assert_eq "airgap-openstack" "$(echo "$merged_yaml" | yq e '.chart.repo_name' -)" \
        "service-specific overrides should replace chart repo names"
    assert_eq "https://airgap.example.invalid/override-target" "$(echo "$merged_yaml" | yq e '.chart.repo_url' -)" \
        "service-specific overrides should replace chart repo URLs"

    GENESTACK_SERVICES_DIR="${original_services_dir}"
    GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="${original_service_overrides_dir}"
}

test_final_helm_command_construction() {
    local nova_yaml nova_args cmd

    nova_yaml="$(load_service_config nova)"
    nova_args="$(secret_prepare_for_service "$nova_yaml" nova 0)"
    cmd="$(
        build_helm_upgrade_install_cmd \
            "nova" \
            "openstack-helm/nova" \
            "openstack" \
            "2025.1.19" \
            "120m" \
            $'-f\n/tmp/base path.yaml\n-f\n/tmp/custom.yaml' \
            "$nova_args" \
            $'--post-renderer\n/tmp/post-renderer path.sh\n--post-renderer-args\nnova overlay' \
            --dry-run
    )"

    assert_contains "$cmd" $'helm\nupgrade\n--install\nnova\nopenstack-helm/nova' \
        "final Helm command should start with upgrade --install"
    assert_contains "$cmd" $'--version=2025.1.19\n--namespace=openstack\n--timeout\n120m\n--create-namespace' \
        "final Helm command should include version and namespace flags"
    assert_contains "$cmd" $'-f\n/tmp/base path.yaml\n-f\n/tmp/custom.yaml' \
        "final Helm command should include override files"
    assert_contains "$cmd" $'--set\nendpoints.identity.auth.nova.password=nova-admin-pass' \
        "final Helm command should preserve --set secret args"
    assert_contains "$cmd" $'--set-string\nnetwork.ssh.public_key=ssh-ed25519 AAAANOVA' \
        "final Helm command should preserve --set-string secret args"
    assert_contains "$cmd" $'--set-file\nnetwork.ssh.private_key=' \
        "final Helm command should preserve --set-file secret args"
    assert_contains "$cmd" $'--post-renderer\n/tmp/post-renderer path.sh\n--post-renderer-args\nnova overlay\n--dry-run' \
        "final Helm command should include post-renderer and extra args"
}

test_multi_chart_install_reuses_secret_pipeline() {
    local svc_yaml set_args_raw override_lines post_renderer_args fakebin log_file kubectl_log
    local first_call second_call

    svc_yaml="$(cat <<'EOF'
service:
  name: synthetic-multi
  namespace: testing
chart:
  repo_name: openstack-helm
  repo_url: https://example.invalid/charts
secrets:
  - helm_key: "auth.password"
    source_secret: synthetic-multi-admin
    source_namespace: testing
    data_key: password
    rotate_with_service: true
    helm_flag: --set
  - helm_key: "tls.private_key"
    source_secret: synthetic-multi-keypair
    source_namespace: testing
    data_key: private-key
    rotate_with_service: true
    helm_flag: --set-file
multi_charts:
  - release_name: synthetic-one
    chart: service-one
    repo_name: multi-repo
    repo_url: oci://registry.example/services
    namespace: testing-a
  - release_name: synthetic-two
    chart: service-two
    repo_name: multi-repo
    repo_url: oci://registry.example/services
    namespace: testing-b
EOF
)"

    secret_get() {
        case "$1/$2:$3" in
            testing/synthetic-multi-admin:password) echo "multi-pass" ;;
            testing/synthetic-multi-keypair:private-key) printf '%s' "MULTI_PRIVATE_KEY" ;;
            *) echo "${2}-${3}-value" ;;
        esac
    }
    secret_get_to_file() {
        secret_get "$1" "$2" "$3" > "$4"
    }
    secret_exists() { return 0; }

    set_args_raw="$(secret_prepare_for_service "$svc_yaml" synthetic-multi 0)"
    override_lines=$'-f\n/tmp/multi a.yaml\n-f\n/tmp/multi-b.yaml'
    post_renderer_args=$'--post-renderer\n/tmp/post-renderer path.sh\n--post-renderer-args\nsynthetic overlay'
    fakebin="$(mktemp -d)"
    log_file="${fakebin}/helm.log"
    kubectl_log="${fakebin}/kubectl.log"

    cat >"${fakebin}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${HELM_LOG_FILE}"
exit 0
EOF
    chmod +x "${fakebin}/helm"

    resolve_helm_repo() {
        HELM_CHART_PATH="resolved/$3"
    }
    ensure_namespace() {
        printf 'ensure_namespace %s\n' "$1" >> "$kubectl_log"
    }
    label_namespace_for_talos() {
        printf 'label_namespace_for_talos %s\n' "$1" >> "$kubectl_log"
    }

    CL_EXTRA_HELM_ARGS=(--dry-run)
    export PATH="${fakebin}:$PATH"
    export HELM_LOG_FILE="$log_file"
    multi_chart_install "$svc_yaml" "synthetic-multi" "9.9.9" "45m" "$override_lines" "$set_args_raw" "$post_renderer_args"

    first_call="$(sed -n '1p' "$log_file")"
    second_call="$(sed -n '2p' "$log_file")"

    assert_contains "$first_call" "upgrade --install synthetic-one resolved/service-one" \
        "multi-chart install should build the first chart command"
    assert_contains "$second_call" "upgrade --install synthetic-two resolved/service-two" \
        "multi-chart install should build the second chart command"
    assert_contains "$first_call" "--namespace=testing-a" \
        "first multi-chart command should use its chart namespace"
    assert_contains "$second_call" "--namespace=testing-b" \
        "second multi-chart command should use its chart namespace"
    assert_contains "$first_call" "--timeout 45m" \
        "multi-chart command should honor the shared timeout"
    assert_contains "$first_call" "-f /tmp/multi a.yaml -f /tmp/multi-b.yaml" \
        "multi-chart command should preserve override paths without shell splitting"
    assert_contains "$first_call" "--set auth.password=multi-pass" \
        "multi-chart command should include shared --set secret args"
    assert_contains "$first_call" "--set-file tls.private_key=" \
        "multi-chart command should include shared --set-file secret args"
    assert_contains "$first_call" "--post-renderer /tmp/post-renderer path.sh --post-renderer-args synthetic overlay" \
        "multi-chart command should include post-renderer args"
    assert_contains "$first_call" "--dry-run" \
        "multi-chart command should include extra Helm args"
    assert_contains "$(cat "$kubectl_log")" "ensure_namespace testing-a" \
        "multi-chart install should prepare the first chart namespace"
    assert_contains "$(cat "$kubectl_log")" "label_namespace_for_talos testing-a" \
        "multi-chart install should label the first chart namespace"
    assert_contains "$(cat "$kubectl_log")" "ensure_namespace testing-b" \
        "multi-chart install should prepare the second chart namespace"
    assert_contains "$(cat "$kubectl_log")" "label_namespace_for_talos testing-b" \
        "multi-chart install should label the second chart namespace"
}

test_build_post_renderer_args_tokenization() {
    local svc_yaml tmp_root tmp_kustomize args

    tmp_root="$(mktemp -d)"
    tmp_kustomize="${tmp_root}/kustomize wrapper.sh"
    printf '#!/bin/bash\nexit 0\n' > "$tmp_kustomize"
    chmod +x "$tmp_kustomize"

    svc_yaml="$(cat <<'EOF'
service:
  name: synthetic-renderer
kustomize:
  enabled: true
  overlay_path: custom overlay
EOF
)"

    HELM_KUSTOMIZE_CMD="$tmp_kustomize"
    args="$(build_post_renderer_args "$svc_yaml" synthetic-renderer)"
    assert_eq $'--post-renderer\n'"$tmp_kustomize"$'\n--post-renderer-args\ncustom overlay' "$args" \
        "post-renderer args should be emitted as structured tokens"
}

# --config selects kustomize.gateway_config_overlay_path when a service defines
# it; every other case keeps kustomize.overlay_path.
test_gateway_config_overlay_selection() {
    local tmp_root with_alt without_alt envoy_cfg args
    local HELM_KUSTOMIZE_CMD GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR
    tmp_root="$(mktemp -d)"
    HELM_KUSTOMIZE_CMD="${tmp_root}/kustomize.sh"
    GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="${tmp_root}/no-site-configs"
    printf '#!/bin/bash\nexit 0\n' > "$HELM_KUSTOMIZE_CMD"
    chmod +x "$HELM_KUSTOMIZE_CMD"

    with_alt="$(cat <<'EOF'
service:
  name: gateway-service
kustomize:
  enabled: true
  overlay_path: ${service_name}/overlay
  gateway_config_overlay_path: ${service_name}/config-mode
EOF
)"
    without_alt="$(cat <<'EOF'
service:
  name: plain-service
kustomize:
  enabled: true
  overlay_path: ${service_name}/overlay
EOF
)"

    assert_eq "gateway-service/overlay" \
        "$(resolve_kustomize_overlay_path "$with_alt" gateway-service)" \
        "without a mode the normal overlay_path must be used"
    assert_eq "gateway-service/config-mode" \
        "$(resolve_kustomize_overlay_path "$with_alt" gateway-service gateway-config)" \
        "gateway-config mode must use gateway_config_overlay_path with \${service_name} expanded"
    assert_eq "plain-service/overlay" \
        "$(resolve_kustomize_overlay_path "$without_alt" plain-service gateway-config)" \
        "a service without gateway_config_overlay_path must keep its normal overlay in gateway-config mode"

    args="$(build_post_renderer_args "$with_alt" gateway-service)"
    assert_eq $'--post-renderer\n'"$HELM_KUSTOMIZE_CMD"$'\n--post-renderer-args\ngateway-service/overlay' "$args" \
        "post-renderer args must use the normal overlay without a mode"
    args="$(build_post_renderer_args "$with_alt" gateway-service gateway-config)"
    assert_eq $'--post-renderer\n'"$HELM_KUSTOMIZE_CMD"$'\n--post-renderer-args\ngateway-service/config-mode' "$args" \
        "post-renderer args must use the gateway config overlay in gateway-config mode"
    args="$(build_post_renderer_args "$without_alt" plain-service gateway-config)"
    assert_eq $'--post-renderer\n'"$HELM_KUSTOMIZE_CMD"$'\n--post-renderer-args\nplain-service/overlay' "$args" \
        "post-renderer args must keep the normal overlay when the service has no gateway overlay"

    # The shipped Envoy service definition selects config-mode with --config.
    envoy_cfg="$(load_service_config envoyproxy-gateway)"
    assert_eq "envoyproxy-gateway/overlay" \
        "$(resolve_kustomize_overlay_path "$envoy_cfg" envoyproxy-gateway)" \
        "envoyproxy-gateway must use its normal overlay by default"
    assert_eq "envoyproxy-gateway/config-mode" \
        "$(resolve_kustomize_overlay_path "$envoy_cfg" envoyproxy-gateway gateway-config)" \
        "envoyproxy-gateway must use the config-mode overlay with --config"
}

test_ensure_kustomize_overlay_path() {
    local tmp_root site_dir base_dir output rc
    local GENESTACK_OVERRIDES_DIR GENESTACK_BASE_DIR
    tmp_root="$(mktemp -d)"
    GENESTACK_OVERRIDES_DIR="${tmp_root}/overrides"
    GENESTACK_BASE_DIR="${tmp_root}/base"
    site_dir="${GENESTACK_OVERRIDES_DIR}/kustomize"
    base_dir="${GENESTACK_BASE_DIR}/base-kustomize"

    # Already present in the site tree: nothing to do.
    mkdir -p "${site_dir}/present-svc/config-mode" "${base_dir}/present-svc/config-mode"
    rc=0
    output="$(ensure_kustomize_overlay_path present-svc/config-mode 2>&1)" || rc=$?
    assert_eq "0" "$rc" "an existing overlay must be accepted"
    assert_not_contains "$output" "Linked kustomize overlay" "an existing overlay must not be relinked"
    [[ -d "${site_dir}/present-svc/config-mode" && ! -L "${site_dir}/present-svc/config-mode" ]] ||
        fail "an existing overlay directory must be left untouched"

    # Missing from the site tree but shipped in base-kustomize: link it.
    mkdir -p "${base_dir}/linked-svc/config-mode"
    rc=0
    output="$(ensure_kustomize_overlay_path linked-svc/config-mode 2>&1)" || rc=$?
    assert_eq "0" "$rc" "an overlay shipped in base-kustomize must be linked successfully"
    [[ -L "${site_dir}/linked-svc/config-mode" ]] || fail "a missing overlay must be linked from base-kustomize"
    assert_eq "${base_dir}/linked-svc/config-mode" "$(readlink "${site_dir}/linked-svc/config-mode")" \
        "the linked overlay must point at base-kustomize"
    assert_contains "$output" "Linked kustomize overlay" "linking an overlay must be logged"

    # Missing everywhere: fail with a clear error and create nothing.
    rc=0
    output="$(ensure_kustomize_overlay_path missing-svc/config-mode 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an overlay missing from both trees must fail"
    assert_contains "$output" "Kustomize overlay not found" "a missing overlay must produce a clear error"
    [[ ! -e "${site_dir}/missing-svc" ]] || fail "a missing overlay must not create site directories"
}

test_helm_set_args_isolation() {
    local cmd

    helm_set_args=(--set leaked.value=true)
    cmd="$(
        build_helm_upgrade_install_cmd \
            "synthetic" \
            "repo/chart" \
            "testing" \
            "1.0.0" \
            "30m" \
            "" \
            "" \
            ""
    )"
    assert_contains "$cmd" $'--set\nleaked.value=true' \
        "builder should include dynamic helm_set_args when explicitly populated"

    helm_set_args=()
    cmd="$(
        build_helm_upgrade_install_cmd \
            "synthetic" \
            "repo/chart" \
            "testing" \
            "1.0.0" \
            "30m" \
            "" \
            "" \
            ""
    )"
    assert_not_contains "$cmd" "leaked.value=true" \
        "builder should not retain helm_set_args after explicit reset"
}

test_rotation_ownership() {
    local nova_yaml neutron_yaml exporter_yaml nova_owned neutron_owned exporter_owned

    nova_yaml="$(load_service_config nova)"
    neutron_yaml="$(load_service_config neutron)"
    exporter_yaml="$(load_service_config openstack-exporter)"

    nova_owned="$(rotation_collect_owned_secrets "$nova_yaml" nova | sort)"
    assert_eq $'openstack/nova-admin\nopenstack/nova-db-password\nopenstack/nova-keystone-service-password\nopenstack/nova-keystone-test-password\nopenstack/nova-rabbitmq-password\nopenstack/nova-ssh' \
        "$nova_owned" "nova owned secrets should be explicit-only"

    neutron_owned="$(rotation_collect_owned_secrets "$neutron_yaml" neutron | sort)"
    assert_eq $'openstack/metadata-shared-secret\nopenstack/neutron-admin\nopenstack/neutron-db-password\nopenstack/neutron-keystone-test-password\nopenstack/neutron-rabbitmq-password' \
        "$neutron_owned" "neutron owned secrets should include metadata-shared-secret"

    # openstack-exporter consumes the keystone-admin credential via
    # ensure_keystone_auth_openstack_exporter_secret; it owns no rotatable
    # secrets of its own.
    exporter_owned="$(rotation_collect_owned_secrets "$exporter_yaml" openstack-exporter | sort)"
    assert_eq "" "$exporter_owned" \
        "openstack-exporter should own no rotatable secrets"

    if printf '%s\n' "$nova_owned" | grep -F "openstack/mariadb" >/dev/null; then
        fail "shared mariadb secret must not be owned by nova"
    fi
    if printf '%s\n' "$nova_owned" | grep -F "openstack/os-memcached" >/dev/null; then
        fail "shared memcached secret must not be owned by nova"
    fi
}

test_rotation_impacts() {
    local nova_yaml nova_owned nova_impacted

    nova_impacted="$(
        rotation_collect_impacted_services nova \
            openstack/nova-admin \
            openstack/nova-db-password \
            openstack/nova-rabbitmq-password \
            openstack/nova-ssh | sort
    )"
    assert_eq $'neutron\nplacement' "$nova_impacted" \
        "nova rotation should reinstall only enabled dependent services"

    if printf '%s\n' "$nova_impacted" | grep -Fx "trove" >/dev/null; then
        fail "nova rotation should not include disabled services from openstack-components.yaml"
    fi

    # Sanity: without the components file gating, more dependents match.
    nova_yaml="$(load_service_config nova)"
    nova_owned="$(rotation_collect_owned_secrets "$nova_yaml" nova | sort)"
    [[ -n "$nova_owned" ]] || fail "nova should own rotatable secrets"
}

test_manifest_invariants() {
    local owner_entries owner_refs duplicates unsupported_flags shared_secret_failures fanout_failures legacy_hook_usage
    local expected_owner_services consumers impacted service_refs replace_refs

    owner_entries="$(
        for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
            svc="$(basename "$f" .yaml)"
            [[ "$svc" == "example-service" ]] && continue
            yq e '.secrets[] | select(.rotate_with_service == true) | ((.source_namespace // .service.namespace // "openstack") + "/" + .source_secret + "|" + "'"$svc"'")' "$f" 2>/dev/null || true
        done
    )"
    owner_entries="$(printf '%s\n' "$owner_entries" | sed '/^$/d' | sort -u)"

    owner_refs="$(printf '%s\n' "$owner_entries" | cut -d'|' -f1 | sed '/^$/d' | sort)"
    duplicates="$(printf '%s\n' "$owner_refs" | uniq -d)"
    [[ -z "$duplicates" ]] || fail "each rotate_with_service secret must have exactly one owner: ${duplicates}"

    unsupported_flags="$(
        for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
            yq e '.secrets[].helm_flag // "--set"' "$f" 2>/dev/null || true
        done | sed '/^null$/d;/^$/d' | sort -u | grep -Ev '^--set$|^--set-string$|^--set-file$' || true
    )"
    [[ -z "$unsupported_flags" ]] || fail "unsupported helm_flag values detected: ${unsupported_flags}"

    validate_action_schemas
    validate_value_from_and_secret_source_schemas

    legacy_hook_usage="$(
        for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
            svc="$(basename "$f" .yaml)"
            if [[ "$(yq e '.pre_install // ""' "$f" 2>/dev/null)" != "" ]]; then
                echo "$svc"
            fi
            if [[ "$(yq e '.pre_install_checks // ""' "$f" 2>/dev/null)" != "" ]]; then
                echo "$svc"
            fi
            if [[ "$(yq e '.post_install // ""' "$f" 2>/dev/null)" != "" ]]; then
                echo "$svc"
            fi
            if yq e '.secrets[]? | select(.custom_command != null) | .helm_key' "$f" 2>/dev/null | grep -q .; then
                echo "$svc"
            fi
        done | sed '/^null$/d;/^$/d' | sort -u
    )"
    [[ -z "$legacy_hook_usage" ]] || fail "legacy free-form hook fields are still present: ${legacy_hook_usage}"

    shared_secret_failures=""
    while IFS='|' read -r ref owner; do
        [[ -z "$ref" ]] && continue
        case "$ref" in
            openstack/keystone-admin)
                expected_owner_services="keystone"
                [[ "$owner" == "$expected_owner_services" ]] || shared_secret_failures+="${ref}:${owner}"$'\n'
                ;;
            openstack/mariadb|openstack/os-memcached|openstack/rabbitmq-default-user|openstack/postgres.postgres-cluster.credentials.postgresql.acid.zalan.do)
                shared_secret_failures+="${ref}:${owner}"$'\n'
                ;;
        esac
    done <<< "$owner_entries"
    [[ -z "$shared_secret_failures" ]] || fail "shared platform secrets have invalid owners: ${shared_secret_failures}"

    fanout_failures=""
    while IFS='|' read -r ref owner; do
        [[ -z "$ref" || -z "$owner" ]] && continue
        consumers=""
        for f in "${GENESTACK_SERVICES_DIR}"/*.yaml; do
            svc="$(basename "$f" .yaml)"
            [[ "$svc" == "$owner" || "$svc" == "example-service" ]] && continue
            rotation_service_enabled "$svc" || continue

            service_refs="$(yq e '.secrets[] | ((.source_namespace // .service.namespace // "openstack") + "/" + .source_secret)' "$f" 2>/dev/null || true)"
            replace_refs="$(yq e '.secrets[].replace[]? | ((.namespace // .service.namespace // "openstack") + "/" + .secret)' "$f" 2>/dev/null || true)"

            if printf '%s\n%s\n' "$service_refs" "$replace_refs" | grep -Fx "$ref" >/dev/null; then
                consumers+="$svc"$'\n'
            fi
        done

        [[ -z "$consumers" ]] && continue
        impacted="$(rotation_collect_impacted_services "$owner" "$ref" | sort -u)"
        while IFS= read -r consumer; do
            [[ -z "$consumer" ]] && continue
            if ! printf '%s\n' "$impacted" | grep -Fx "$consumer" >/dev/null; then
                fanout_failures+="${owner}:${ref}:${consumer}"$'\n'
            fi
        done <<< "$(printf '%s\n' "$consumers" | sort -u)"
    done <<< "$owner_entries"
    [[ -z "$fanout_failures" ]] || fail "owned-secret consumers are missing from reinstall fan-out: ${fanout_failures}"
}

test_direct_action_handlers() {
    local fakebin log_file helper_dir svc_yaml

    fakebin="$(mktemp -d)"
    log_file="${fakebin}/kubectl.log"
    helper_dir="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    cat >"${helper_dir}/monitoring-common.sh" <<'EOF'
#!/bin/bash
monitoring_ensure_grafana_db_secret() {
    echo "grafana-bootstrap" >> "${ACTION_LOG_FILE}"
}
EOF
    chmod +x "${helper_dir}/monitoring-common.sh"

    svc_yaml="$(cat <<'EOF'
service:
  name: synthetic-actions
  namespace: openstack
pre_install_actions:
  - type: monitoring_grafana_db_secret_bootstrap
  - type: kube_ovn_master_discovery
    node_label: kube-ovn/role=master
    master_nodes_helm_key: MASTER_NODES
    replica_count_helm_key: replicaCount
pre_install_check_actions:
  - type: detect_kube_ovn_tls
    namespace: kube-system
  - type: ovn_connection_set_args
    entries:
      - helm_key: conf.service.ovn_nb_connection
        env: OVN_NB_CONNECTION
      - helm_key: conf.service.ovn_sb_connection
        env: OVN_SB_CONNECTION
post_install_actions:
  - type: rollout_status
    namespace: monitoring
    workload: deployment/example
    timeout: 90s
  - type: get_by_label_optional
    namespace: monitoring
    resource: pods
    selector: app=demo
    not_found_message: not-ready
  - type: namespace_resource_dump_if_pods_present
    namespace: longhorn-system
    resources:
      - pods
      - svc
EOF
)"

    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        KUBECTL_LOG_FILE="$log_file" \
        ACTION_LOG_FILE="${fakebin}/action.log" \
        GENESTACK_HELPERS_DIR="$helper_dir" \
        run_service_actions "$svc_yaml" '.pre_install_actions' synthetic-actions

    assert_eq "grafana-bootstrap" "$(cat "${fakebin}/action.log")" \
        "grafana bootstrap action should dispatch through monitoring-common"
    assert_eq "2" "${MASTER_NODE_COUNT}" \
        "kube-ovn master discovery should count matching nodes"
    assert_eq '10.0.0.21\,10.0.0.22' "${MASTER_NODES}" \
        "kube-ovn master discovery should escape the master node list"
    assert_contains "${helm_set_args[*]}" "MASTER_NODES=10.0.0.21\\,10.0.0.22" \
        "kube-ovn master discovery should append master node Helm args"
    assert_contains "${helm_set_args[*]}" "replicaCount=2" \
        "kube-ovn master discovery should append replica count Helm args"

    helm_set_args=()
    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl KUBECTL_LOG_FILE="$log_file" run_service_actions "$svc_yaml" '.pre_install_check_actions' synthetic-actions
    assert_eq "tcp" "${CONNECTION_STRING}" \
        "OVN detection action should set the connection string"
    assert_contains "${helm_set_args[*]}" "conf.service.ovn_nb_connection=tcp:10.0.0.10:6641" \
        "OVN connection set args should inject the northbound connection"
    assert_contains "${helm_set_args[*]}" "conf.service.ovn_sb_connection=tcp:10.0.0.11:6642" \
        "OVN connection set args should inject the southbound connection"

    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl KUBECTL_LOG_FILE="$log_file" run_service_actions "$svc_yaml" '.post_install_actions' synthetic-actions
    assert_contains "$(cat "$log_file")" "rollout status deployment/example --namespace monitoring --timeout=90s" \
        "rollout_status action should call kubectl rollout status"
    assert_contains "$(cat "$log_file")" "get pods --namespace monitoring -l app=demo" \
        "get_by_label_optional action should query the labeled resource"
    assert_contains "$(cat "$log_file")" "get pods --namespace longhorn-system" \
        "namespace_resource_dump_if_pods_present should query pods"
    assert_contains "$(cat "$log_file")" "get svc --namespace longhorn-system" \
        "namespace_resource_dump_if_pods_present should query services"
}

test_value_from_secret_data_happy_path() {
    local gnocchi_yaml gnocchi_args keyring_line keyring_path fakebin

    gnocchi_yaml="$(load_service_config gnocchi)"
    gnocchi_args="$(secret_prepare_for_service "$gnocchi_yaml" gnocchi 0)"
    keyring_line="$(printf '%s\n' "$gnocchi_args" | grep -F -- $'--set-file\tconf.ceph.admin_keyring=' | head -n1)"
    [[ -n "$keyring_line" ]] || fail "value_from.secret_data should resolve into a --set-file Helm arg"
    keyring_path="${keyring_line#*$'\t'}"
    keyring_path="${keyring_path#*=}"
    assert_file_content "$keyring_path" "rook-ceph-admin-keyring-keyring-value" \
        "value_from.secret_data file should contain the referenced secret data"

    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service gnocchi >/dev/null
}

test_helm_timeout_propagation() {
    local fakebin service_dir log_file service_file

    fakebin="$(mktemp -d)"
    service_dir="$(mktemp -d)"
    log_file="${fakebin}/helm.log"
    service_file="${service_dir}/timeout-service.yaml"
    create_fake_installer_binaries "$fakebin"

    cat >"$service_file" <<'EOF'
service:
  name: timeout-service
  namespace: testing
  version: 1.2.3
chart:
  repo_name: openstack-helm
  repo_url: https://example.invalid/charts
helm:
  timeout: 45m
secrets: []
EOF

    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        HELM_LOG_FILE="$log_file" \
        GENESTACK_SERVICES_DIR="$service_dir" \
        "${REPO_ROOT}/bin/install.sh" --service timeout-service --dry-run >/dev/null

    assert_contains "$(sed -n '3p' "$log_file")" "--timeout 45m" \
        "install.sh should honor manifest-defined Helm timeouts"
}

test_crd_install_honors_service_timeout() {
    local fakebin log_file

    fakebin="$(mktemp -d)"
    log_file="${fakebin}/helm.log"

    cat >"${fakebin}/helm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${HELM_LOG_FILE}"
exit 0
EOF
    chmod +x "${fakebin}/helm"

    PATH="${fakebin}:$PATH" HELM_LOG_FILE="$log_file" helm_install_crds \
        "synthetic" "synthetic-crds" "1.2.3" "synthetic-repo/synthetic" "testing" "37m"

    assert_contains "$(cat "$log_file")" "synthetic-repo/synthetic-crds" \
        "CRDs should resolve beside the operator chart"
    assert_contains "$(cat "$log_file")" "--namespace testing" \
        "CRDs should use the service namespace"
    assert_contains "$(cat "$log_file")" "--timeout 37m" \
        "CRD installs should honor the resolved Helm timeout"
}

test_rotation_secret_shapes() {
    local nova_yaml manila_yaml last_ssh_call generic_calls

    last_ssh_call=""
    generic_calls=""

    secret_delete() { :; }
    secret_ensure() { generic_calls="${generic_calls}$1/$2:$3"$'\n'; }
    secret_ensure_rabbitmq_user_credentials() { fail "did not expect rabbitmq credential regeneration in ssh tests"; }
    secret_ensure_ssh_keypair() { last_ssh_call="$1 $2 $3 $4"; }

    nova_yaml="$(load_service_config nova)"
    rotation_regenerate_owned_secret "$nova_yaml" openstack nova-ssh
    assert_eq "openstack nova-ssh public-key private-key" "$last_ssh_call" \
        "nova keypair rotation should regenerate SSH material"

    manila_yaml="$(load_service_config manila)"
    rotation_regenerate_owned_secret "$manila_yaml" openstack manila-service-keypair
    assert_eq "openstack manila-service-keypair public_key private_key" "$last_ssh_call" \
        "manila keypair rotation should regenerate SSH material"

    generic_calls=""
    rotation_regenerate_owned_secret "$nova_yaml" openstack nova-db-password
    printf '%s' "$generic_calls" | grep -F "openstack/nova-db-password:password" >/dev/null \
        || fail "generic nova-db-password rotation should regenerate password data"
}

test_check_secrets_smoke() {
    local fakebin
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service nova >/dev/null
    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service manila >/dev/null
    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service neutron >/dev/null
    PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service openstack-exporter >/dev/null
}

test_check_secrets_failures() {
    local fakebin
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    if PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl MISSING_SECRET_REFS="openstack/nova-admin" \
        GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service nova >/dev/null 2>&1; then
        fail "--check-secrets should fail when a required secret object is missing"
    fi

    if PATH="${fakebin}:$PATH" KUBECTL_BIN=kubectl EMPTY_SECRET_DATA_REFS="openstack/nova-admin:password" \
        GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --check-secrets --service nova >/dev/null 2>&1; then
        fail "--check-secrets should fail when a required secret data key is empty"
    fi
}

test_install_command_path_real_service() {
    local fakebin log_file tmp_root tmp_base tmp_overrides tmp_kustomize nova_private_path cmd_log
    fakebin="$(mktemp -d)"
    log_file="${fakebin}/helm.log"
    tmp_root="$(mktemp -d)"
    tmp_base="${tmp_root}/base"
    tmp_overrides="${tmp_root}/overrides"
    tmp_kustomize="${tmp_overrides}/kustomize"

    mkdir -p "${tmp_base}/base-helm-configs/nova" "${tmp_overrides}/helm-configs/global_overrides" "${tmp_overrides}/helm-configs/nova" "$tmp_kustomize"
    : > "${tmp_base}/base-helm-configs/nova/base.yaml"
    : > "${tmp_overrides}/helm-configs/global_overrides/global.yaml"
    : > "${tmp_overrides}/helm-configs/nova/custom.yaml"
    printf '#!/bin/bash\nexit 0\n' > "${tmp_kustomize}/kustomize.sh"
    chmod +x "${tmp_kustomize}/kustomize.sh"
    cat > "${tmp_overrides}/helm-chart-versions.yaml" <<'EOF'
charts:
  nova: 2025.1.19
EOF

    create_fake_installer_binaries "$fakebin"

    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        HELM_LOG_FILE="$log_file" \
        GENESTACK_BASE_DIR="$tmp_base" \
        GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
        GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --service nova --dry-run >/dev/null

    cmd_log="$(sed -n '3p' "$log_file")"
    assert_contains "$cmd_log" "upgrade --install nova openstack-helm/nova" \
        "install.sh should build the real Helm upgrade command for nova"
    assert_contains "$cmd_log" "--version=2025.1.19 --namespace=openstack --timeout 120m --create-namespace" \
        "install.sh should include version and namespace in the real Helm command"
    assert_contains "$cmd_log" "--set endpoints.identity.auth.nova.password=nova-admin-password-value" \
        "install.sh should preserve real --set secret injection"
    assert_contains "$cmd_log" "--set-string network.ssh.public_key=ssh-ed25519 AAAANOVA" \
        "install.sh should preserve real --set-string secret injection"
    assert_contains "$cmd_log" "--set-file network.ssh.private_key=" \
        "install.sh should preserve real --set-file secret injection"
    assert_contains "$cmd_log" "--post-renderer ${tmp_kustomize}/kustomize.sh --post-renderer-args nova/overlay" \
        "install.sh should include the post-renderer in the real Helm command"
    assert_contains "$cmd_log" "--dry-run" \
        "install.sh should pass through user Helm flags in the real Helm command"
}

test_install_command_path_name_keys_real_service() {
    local fakebin log_file tmp_root tmp_base tmp_overrides main_cmd
    fakebin="$(mktemp -d)"
    log_file="${fakebin}/helm.log"
    tmp_root="$(mktemp -d)"
    tmp_base="${tmp_root}/base"
    tmp_overrides="${tmp_root}/overrides"

    mkdir -p "${tmp_base}/base-helm-configs/mariadb-operator" "${tmp_overrides}"
    cat > "${tmp_overrides}/helm-chart-versions.yaml" <<'EOF'
charts:
  mariadb-operator: 25.6.2
EOF

    create_fake_installer_binaries "$fakebin"

    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        HELM_LOG_FILE="$log_file" \
        GENESTACK_BASE_DIR="$tmp_base" \
        GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
        GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --service mariadb-operator --dry-run >/dev/null

    main_cmd="$(grep -F "upgrade --install mariadb-operator mariadb-operator/mariadb-operator" "$log_file" | tail -n1)"
    [[ -n "$main_cmd" ]] || fail "expected real Helm install command for mariadb-operator"

    assert_contains "$main_cmd" "--version=25.6.2 --namespace=mariadb-system --timeout 120m --create-namespace" \
        "mariadb-operator install should include version, namespace, and timeout"
    # name+keys entries bootstrap shared k8s secrets (openstack/mariadb) but
    # are intentionally NOT injected as --set args; only source_secret entries
    # with explicit helm_key reach the chart.
    assert_not_contains "$main_cmd" "--set root-password=" \
        "name+keys model should not inject root-password into the real Helm command"
    assert_not_contains "$main_cmd" "--set password=" \
        "name+keys model should not inject password into the real Helm command"
    assert_contains "$main_cmd" "--dry-run" \
        "mariadb-operator install should pass through user Helm flags"
}

test_post_install_skipped_on_helm_failure() {
    local fakebin kubectl_log install_output
    fakebin="$(mktemp -d)"
    kubectl_log="${fakebin}/kubectl.log"
    create_fake_installer_binaries "$fakebin"

    install_output="$(
        PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_LOG_FILE="$kubectl_log" \
            HELM_FAIL_UPGRADE=1 \
            GENESTACK_SERVICES_DIR="${GENESTACK_SERVICES_DIR}" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service longhorn --version 1.0.0 2>&1 || true
    )"

    assert_contains "$install_output" "Skipping post-install hook for 'longhorn' due to Helm failure." \
        "installer should explain that post-install actions were skipped after Helm failure"
    assert_not_contains "$(cat "$kubectl_log")" "get svc --namespace longhorn-system" \
        "post-install diagnostics should not run after a failed Helm install"
}

# Runs a copy of bin/ with setup-envoy-gateway.sh stubbed, so the Envoy install
# flow can be observed without touching a cluster. Callers set the fixture
# variables below as locals; this helper reads them through dynamic scope.
#   envoy_fail_wait  1 makes the fake "kubectl wait" fail
run_envoy_install_fixture() {
    : > "$kubectl_log"
    : > "$helm_log"
    envoy_rc=0
    envoy_output="$(
        PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_LOG_FILE="$kubectl_log" \
            KUBECTL_FAIL_WAIT="${envoy_fail_wait:-0}" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${tmp_bin}/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${tmp_bin}/install.sh" "$@" 2>&1
    )" || envoy_rc=$?
}

# install.sh --service envoyproxy-gateway --config <file> must render the
# config-mode overlay, wait for the controller, and only then apply the config.
test_install_gateway_config_mode() {
    local fakebin tmp_root tmp_bin tmp_base tmp_overrides kubectl_log helm_log gateway_file
    local envoy_rc envoy_output envoy_fail_wait wait_line setup_line helm_cmd
    fakebin="$(mktemp -d)"
    tmp_root="$(mktemp -d)"
    tmp_bin="${tmp_root}/bin"
    tmp_base="${tmp_root}/base"
    tmp_overrides="${tmp_root}/overrides"
    kubectl_log="${tmp_root}/kubectl.log"
    helm_log="${tmp_root}/helm.log"
    gateway_file="${tmp_root}/envoy-gateways.yaml"

    mkdir -p "$tmp_bin" "${tmp_base}/base-helm-configs/envoyproxy-gateway" \
        "${tmp_base}/base-kustomize/envoyproxy-gateway/config-mode" "${tmp_overrides}/kustomize"
    cp -R "${REPO_ROOT}/bin/." "${tmp_bin}/"
    printf 'domain: example.com\n' > "$gateway_file"
    cat > "${tmp_bin}/setup-envoy-gateway.sh" <<'EOF'
#!/bin/bash
printf 'SETUP %s\n' "$*" >> "${KUBECTL_LOG_FILE}"
EOF
    chmod +x "${tmp_bin}/setup-envoy-gateway.sh"
    printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
    chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
    cat > "${tmp_overrides}/helm-chart-versions.yaml" <<'EOF'
charts:
  envoyproxy-gateway: v1.7.0
EOF
    create_fake_installer_binaries "$fakebin"

    # --config: config-mode overlay, wait, then setup, in that order.
    run_envoy_install_fixture --service envoyproxy-gateway --config "$gateway_file"
    assert_eq "0" "$envoy_rc" "a config-mode install must succeed"
    helm_cmd="$(grep '^upgrade --install' "$helm_log")"
    assert_contains "$helm_cmd" "upgrade --install envoyproxy-gateway oci://docker.io/envoyproxy/gateway-helm" \
        "the Envoy release must keep the envoyproxy-gateway name and chart"
    assert_contains "$helm_cmd" "--version=v1.7.0" "the Envoy chart version must come from helm-chart-versions.yaml"
    assert_contains "$helm_cmd" \
        "--post-renderer ${tmp_overrides}/kustomize/kustomize.sh --post-renderer-args envoyproxy-gateway/config-mode" \
        "--config must render the config-mode overlay"
    [[ -L "${tmp_overrides}/kustomize/envoyproxy-gateway/config-mode" ]] ||
        fail "the config-mode overlay must be linked from base-kustomize when missing"
    wait_line="$(grep -n 'wait --timeout=5m deployments.apps/envoy-gateway --for=condition=available' "$kubectl_log" | head -1 | cut -d: -f1)"
    setup_line="$(grep -n "^SETUP --config ${gateway_file}\$" "$kubectl_log" | head -1 | cut -d: -f1)"
    [[ -n "$wait_line" ]] || fail "the installer must wait for the Envoy controller before applying the config"
    [[ -n "$setup_line" ]] || fail "the installer must apply the gateway config with --config <file>"
    (( wait_line < setup_line )) || fail "the controller wait must happen before the gateway config is applied"
    assert_contains "$(sed -n "${wait_line}p" "$kubectl_log")" "-n envoyproxy-gateway-system" \
        "the wait must target the Envoy namespace"

    # A controller that never becomes available: no config applied, install fails.
    envoy_fail_wait=1
    run_envoy_install_fixture --service envoyproxy-gateway --config "$gateway_file"
    [[ "$envoy_rc" -ne 0 ]] || fail "a failed controller wait must fail the install"
    assert_contains "$envoy_output" "did not become available" "a failed wait must be reported"
    assert_not_contains "$(cat "$kubectl_log")" "SETUP" "the gateway config must not be applied after a failed wait"

    # Without --config: normal overlay, no wait, no setup.
    envoy_fail_wait=0
    run_envoy_install_fixture --service envoyproxy-gateway
    assert_eq "0" "$envoy_rc" "a normal Envoy install must succeed"
    assert_contains "$(grep '^upgrade --install' "$helm_log")" "--post-renderer-args envoyproxy-gateway/overlay" \
        "without --config the normal overlay must be used"
    assert_not_contains "$(cat "$kubectl_log")" " wait " "without --config the installer must not wait for the controller"
    assert_not_contains "$(cat "$kubectl_log")" "SETUP" "without --config no gateway config may be applied"
}

# Callers must name services that exist, and the Envoy service must resolve
# the same release, values directory and chart version everything else expects.
test_service_references_and_envoy_resolution() {
    local references name missing="" envoy_cfg version
    local CHART_VERSIONS_FILE GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR
    CHART_VERSIONS_FILE="${REPO_ROOT}/helm-chart-versions.yaml"
    GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="$(mktemp -d)/no-site-configs"

    references="$(
        {
            grep -ohE 'install\.sh[[:space:]]+--service[[:space:]]+[A-Za-z0-9][A-Za-z0-9._-]*' \
                "${REPO_ROOT}"/bin/*.sh "${REPO_ROOT}"/docs/*.md 2>/dev/null || true
            find "${REPO_ROOT}/scripts" -name '*.sh' -print0 2>/dev/null |
                xargs -0 grep -ohE 'install\.sh[[:space:]]+--service[[:space:]]+[A-Za-z0-9][A-Za-z0-9._-]*' 2>/dev/null || true
        } | awk '{print $NF}' | sort -u
    )"
    [[ -n "$references" ]] || fail "no install.sh --service references were found to validate"
    while IFS= read -r name; do
        [[ -f "${GENESTACK_SERVICES_DIR}/${name}.yaml" ]] || missing+="${name} "
    done <<< "$references"
    assert_eq "" "$missing" "every install.sh --service reference must have a bin/services/<name>.yaml"

    envoy_cfg="$(load_service_config envoyproxy-gateway)"
    assert_eq "envoyproxy-gateway" \
        "$(printf '%s\n' "$envoy_cfg" | yq e '.service.release_name // .service.name' -)" \
        "the Envoy Helm release must be named envoyproxy-gateway"
    [[ -d "${REPO_ROOT}/base-helm-configs/$(printf '%s\n' "$envoy_cfg" | yq e '.chart.service_name // .service.name' -)" ]] ||
        fail "the Envoy values directory must exist under base-helm-configs"
    version="$(resolve_chart_version envoyproxy-gateway "$envoy_cfg" 2>/dev/null)" ||
        fail "envoyproxy-gateway must resolve a chart version from helm-chart-versions.yaml"
    assert_matches_regex "$version" '^v?[0-9]+\.[0-9]+' "the resolved Envoy chart version must look like a version"
}

# Isolate configuration fixtures and resolver mocks from the secret tests.
test_config_layer_precedence() (
    local root merged sources
    root="$(mktemp -d)"
    GENESTACK_SERVICES_DIR="$root/services"
    GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="$root/site"
    mkdir -p "$root/services" "$root/site"
    cat > "$root/services/openstack-common.yaml" <<'EOF'
service:
  namespace: family-default
chart:
  repo_url: https://public.example/charts
  repo_name: public
  global_overrides: true
EOF
    cat > "$root/services/demo.yaml" <<'EOF'
service:
  name: demo
  namespace: service-default
chart:
  repo_name: service-default
  service_name: demo
EOF
    cat > "$root/site/openstack-common.yaml" <<'EOF'
service:
  namespace: site-family
chart:
  repo_name: site-family
  repo_url: https://internal.example/charts
  global_overrides: false
EOF
    cat > "$root/site/demo.yaml" <<'EOF'
chart:
  repo_name: site-service
EOF
    merged="$(load_service_config demo --log-sources 2> "$root/sources")"
    assert_eq site-family "$(printf '%s\n' "$merged" | yq '.service.namespace')" \
        "site family must override repository service defaults"
    assert_eq site-service "$(printf '%s\n' "$merged" | yq '.chart.repo_name')" \
        "site service must override site family"
    assert_eq false "$(printf '%s\n' "$merged" | yq '.chart.global_overrides')" \
        "false must survive the configuration merge"
    sources="$(sed -n 's/^ - //p' "$root/sources")"
    assert_eq "$(printf '%s\n' "$root/services/openstack-common.yaml" "$root/services/demo.yaml" "$root/site/openstack-common.yaml" "$root/site/demo.yaml")" \
        "$sources" "configuration sources must be reported in merge order"

    printf 'service:\n  family: ""\n  name: standalone\n' > "$root/services/standalone.yaml"
    printf 'chart: {repo_url: accidental}\n' > "$root/site/.yaml"
    merged="$(load_service_config standalone)"
    assert_eq null "$(printf '%s\n' "$merged" | yq '.chart.repo_url')" \
        "explicit empty family must skip all family files"
)

test_values_precedence_and_chart_rename() (
    local root config actual expected file diagnostics
    root="$(mktemp -d)"
    GENESTACK_BASE_DIR="$root/base"
    GENESTACK_OVERRIDES_DIR="$root/site"
    mkdir -p "$root/base/base-helm-configs/renamed-chart" \
        "$root/site/helm-configs/global_overrides" "$root/site/helm-configs/renamed-chart" \
        "$root/site/service-configs"
    local files=(
        "$root/base/base-helm-configs/renamed-chart/10-base.yaml"
        "$root/base/base-helm-configs/renamed-chart/20-storage settings.yaml"
        "$root/site/helm-configs/global_overrides/global.yaml"
        "$root/site/helm-configs/renamed-chart/service.yaml"
    )
    for file in "${files[@]}"; do printf '{}\n' > "$file"; done
    printf 'chart: {repo_url: https://metadata.example}\n' > "$root/site/service-configs/demo.yaml"
    config='service:
  name: demo
chart:
  service_name: renamed-chart
  global_overrides: true'
    actual="$(build_helm_args "$config" 2> "$root/values.log")"
    expected="$(printf '%s\n' "${files[@]}" | while IFS= read -r file; do printf '%s\n' '-f' "$file"; done)"
    assert_eq "$expected" "$actual" "values must retain chart-name directories, base/global/service order, and spaces"
    diagnostics="$(cat "$root/values.log")"
    expected="$(printf '%s\n' \
        "[INFO]  Including base overrides from directory: $root/base/base-helm-configs/renamed-chart" \
        " - ${files[0]}" " - ${files[1]}" \
        "[INFO]  Including global overrides from directory: $root/site/helm-configs/global_overrides" \
        " - ${files[2]}" \
        "[INFO]  Including overrides from service config directory: $root/site/helm-configs/renamed-chart" \
        " - ${files[3]}")"
    assert_eq "$expected" "$diagnostics" "values diagnostics must match loading order on stderr without changing Helm arguments"
    actual="$(build_helm_args "$(printf '%s\n' "$config" | yq '.chart.global_overrides = false')" 2> "$root/values.log")"
    assert_not_contains "$actual" global_overrides "false must exclude global values"
    assert_not_contains "$(cat "$root/values.log")" global_overrides "disabled global values must not be logged as included"
    assert_contains "$actual" "$root/site/helm-configs/renamed-chart/service.yaml" "service values must still apply"
    assert_not_contains "$actual" service-configs "chart metadata must never become Helm values"

    # Explicit nested files are inserted before site values, in caller order.
    local additional_base_values=(
        "$root/base/base-helm-configs/renamed-chart/ssl/20-tls settings.yaml"
        "$root/base/base-helm-configs/renamed-chart/rules/10-rules.yaml"
    )
    mkdir -p "${additional_base_values[0]%/*}" "${additional_base_values[1]%/*}"
    for file in "${additional_base_values[@]}"; do printf '{}\n' > "$file"; done
    actual="$(build_helm_args "$config" "${additional_base_values[@]}" 2> "$root/values.log")"
    expected="$(printf '%s\n' "${files[0]}" "${files[1]}" "${additional_base_values[@]}" "${files[2]}" "${files[3]}" |
        while IFS= read -r file; do printf '%s\n' '-f' "$file"; done)"
    assert_eq "$expected" "$actual" "additional base files must preserve caller order, spaces, and site override precedence"
    diagnostics="$(sed -n 's/^ - //p' "$root/values.log")"
    assert_eq "$(printf '%s\n' "${files[0]}" "${files[1]}" "${additional_base_values[@]}" "${files[2]}" "${files[3]}")" \
        "$diagnostics" "additional values diagnostics must match argument order"
    assert_contains "$(cat "$root/values.log")" 'Including additional base overrides:' "additional values must have a log heading"

    actual="$(build_helm_args "$(printf '%s\n' "$config" | yq '.chart.global_overrides = false')" "${additional_base_values[@]}" 2> "$root/values.log")"
    expected="$(printf '%s\n' "${files[0]}" "${files[1]}" "${additional_base_values[@]}" "${files[3]}" |
        while IFS= read -r file; do printf '%s\n' '-f' "$file"; done)"
    assert_eq "$expected" "$actual" "disabled globals must preserve additional base files and service overrides"
    assert_not_contains "$(cat "$root/values.log")" global_overrides "disabled global values must not be logged with additional files"

    additional_base_values=()
    actual="$(build_helm_args "$config" "${additional_base_values[@]}" 2> "$root/values.log")"
    expected="$(printf '%s\n' "${files[@]}" | while IFS= read -r file; do printf '%s\n' '-f' "$file"; done)"
    assert_eq "$expected" "$actual" "empty additional file lists must retain existing behavior and skip nested files"
    assert_not_contains "$(cat "$root/values.log")" 'additional base overrides' "empty additional file lists must not print an inclusion heading"

    if actual="$(build_helm_args "$config" "${files[0]}" "$root/missing.yaml" 2> "$root/values.log")"; then
        fail "an explicitly selected missing file must stop values collection"
    fi
    assert_eq '' "$actual" "missing explicit files must fail before emitting partial Helm arguments"
    assert_contains "$(cat "$root/values.log")" "$root/missing.yaml" "missing-file errors must identify the selected path"
)

test_site_chart_sources_and_versions() (
    local root source chart command
    root="$(mktemp -d)"
    export GENESTACK_BASE_DIR="$root/base" GENESTACK_OVERRIDES_DIR="$root/site"
    export GENESTACK_SERVICES_DIR="$root/services"
    export GENESTACK_SERVICE_CONFIG_OVERRIDES_DIR="$root/site/service-configs"
    export HELM_LOG_FILE="$root/helm.log" KUBECTL_LOG_FILE="$root/kubectl.log"
    export GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 KUBECTL_BIN=kubectl
    mkdir -p "$root/bin" "$root/services" "$root/site/service-configs" \
        "$root/base/base-helm-configs/demo" "$root/base/base-helm-configs/renamed" \
        "$root/base/base-helm-configs/demo-crds" "$root/site/helm-configs/renamed" \
        "$root/site/helm-configs/global_overrides"
    create_fake_installer_binaries "$root/bin"
    export PATH="$root/bin:$PATH"
    printf '{}\n' > "$root/base/base-helm-configs/renamed/base.yaml"
    printf '{}\n' > "$root/site/helm-configs/renamed/site.yaml"
    printf '{}\n' > "$root/site/helm-configs/global_overrides/global.yaml"
    cat > "$root/services/demo.yaml" <<'EOF'
service:
  name: demo
  namespace: testing
  family: ""
chart:
  repo_url: https://public.example/charts
  repo_name: public
  service_name: demo
  global_overrides: true
crd_chart: demo-crds
secrets: []
EOF
    printf 'charts: {demo: 1.0.0, renamed: 0.9.0}\n' > "$root/site/helm-chart-versions.yaml"
    for source in http oci local; do
        case "$source" in
            http) chart=internal/renamed
                printf 'chart:\n  repo_url: https://internal.example/charts\n  repo_name: internal\n' > "$root/site/service-configs/demo.yaml" ;;
            oci) chart=oci://registry.example/charts/renamed
                printf 'chart:\n  repo_url: oci://registry.example/charts/renamed\n' > "$root/site/service-configs/demo.yaml" ;;
            local) chart="$root/base/base-helm-configs/renamed"
                printf 'chart:\n  repo_url: null\n  repo_name: null\n' > "$root/site/service-configs/demo.yaml" ;;
        esac
        printf '  service_name: renamed\n  global_overrides: false\nservice:\n  version: 2.0.0\n' >> "$root/site/service-configs/demo.yaml"
        : > "$HELM_LOG_FILE"
        "${REPO_ROOT}/bin/install.sh" --service demo --dry-run > "$root/output" 2>&1 \
            || fail "$source chart install failed: $(cat "$root/output")"
        command="$(grep '^upgrade --install demo ' "$HELM_LOG_FILE")"
        assert_contains "$command" "demo $chart --version=2.0.0" "$source must use the site chart and version"
        assert_contains "$command" "-f $root/base/base-helm-configs/renamed/base.yaml -f $root/site/helm-configs/renamed/site.yaml" \
            "$source must retain existing chart-name values paths"
        assert_not_contains "$command" global_overrides "$source must honor disabled global overrides"
        assert_not_contains "$command" service-configs "$source metadata must not be passed with -f"
        assert_contains "$(cat "$HELM_LOG_FILE")" "upgrade --install demo-crds ${chart%/*}/demo-crds" \
            "$source CRD chart must follow the selected source"
        if [[ "$source" == http ]]; then
            assert_contains "$(cat "$HELM_LOG_FILE")" 'repo add --force-update internal https://internal.example/charts' \
                "HTTP must register the internal repository"
        else
            assert_not_contains "$(cat "$HELM_LOG_FILE")" 'repo ' "$source must not use HTTP repository setup"
        fi
    done
    : > "$HELM_LOG_FILE"
    "${REPO_ROOT}/bin/install.sh" --service demo --version 3.0.0 --dry-run > "$root/output" 2>&1
    assert_contains "$(cat "$HELM_LOG_FILE")" --version=3.0.0 "CLI version must win over the site pin"

    # Remove the site pin to exercise manifest lookup and strict failures.
    yq -i 'del(.service.version)' "$root/site/service-configs/demo.yaml"
    "${REPO_ROOT}/bin/install.sh" --service demo --dry-run > "$root/output" 2>&1
    assert_contains "$(tail -n1 "$HELM_LOG_FILE")" --version=1.0.0 "manifest service key must win over the chart key"
    printf 'charts: {renamed: 0.9.0}\n' > "$root/site/helm-chart-versions.yaml"
    "${REPO_ROOT}/bin/install.sh" --service demo --dry-run > "$root/output" 2>&1
    assert_contains "$(tail -n1 "$HELM_LOG_FILE")" --version=0.9.0 "manifest chart-name fallback must still work"

    for source in missing-entry missing-file; do
        if [[ "$source" == missing-entry ]]; then
            printf 'charts: {}\n' > "$root/site/helm-chart-versions.yaml"
        else
            mv "$root/site/helm-chart-versions.yaml" "$root/saved-versions.yaml"
        fi
        : > "$HELM_LOG_FILE"
        : > "$KUBECTL_LOG_FILE"
        if "${REPO_ROOT}/bin/install.sh" --service demo > "$root/output" 2>&1; then
            fail "$source must stop installation"
        fi
        assert_eq '' "$(cat "$HELM_LOG_FILE" "$KUBECTL_LOG_FILE")" \
            "$source must fail before Helm or cluster changes"
    done
)

test_chart_resolution_failures() (
    local root
    root="$(mktemp -d)"
    GENESTACK_BASE_DIR="$root"
    if resolve_helm_repo '' '' absent >/dev/null 2>&1; then
        fail "missing local chart must stop resolution"
    fi
    assert_eq '' "$HELM_CHART_PATH" "failed resolution must clear stale chart paths"
    if resolve_helm_repo https://internal.example/charts '' demo >/dev/null 2>&1; then
        fail "HTTP chart metadata must include a repository alias"
    fi
    helm() { return 1; }
    if resolve_helm_repo https://internal.example/charts internal demo >/dev/null 2>&1; then
        fail "repository registration failures must propagate"
    fi
    if helm_install_crds demo demo-crds 1.0.0 "$root/demo" testing 5m >/dev/null 2>&1; then
        fail "missing local CRD chart must fail"
    fi
)

main() {
    local tmp_root

    tmp_root="$(mktemp -d)"
    setup_test_components_file "$tmp_root"

    test_secret_arg_formatting
    test_secret_arg_token_parser
    test_base64_encode_helper
    test_service_config_repo_url_overrides
    test_config_layer_precedence
    test_values_precedence_and_chart_rename
    test_site_chart_sources_and_versions
    test_chart_resolution_failures
    test_build_post_renderer_args_tokenization
    test_gateway_config_overlay_selection
    test_ensure_kustomize_overlay_path
    test_final_helm_command_construction
    test_multi_chart_install_reuses_secret_pipeline
    test_helm_set_args_isolation
    test_rotation_ownership
    test_rotation_impacts
    test_manifest_invariants
    test_rotation_secret_shapes
    test_direct_action_handlers
    test_value_from_secret_data_happy_path
    test_check_secrets_smoke
    test_check_secrets_failures
    test_helm_timeout_propagation
    test_crd_install_honors_service_timeout
    test_install_command_path_real_service
    test_install_command_path_name_keys_real_service
    test_post_install_skipped_on_helm_failure
    test_install_gateway_config_mode
    test_service_references_and_envoy_resolution
    echo "PASS: unified installer regression checks"
}

main "$@"
