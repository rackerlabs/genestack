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

if [[ -n "${KUBECTL_SECRET_DIR:-}" ]]; then
    # In-memory store for the Barbican kek secrets: $KUBECTL_SECRET_DIR/<namespace>/<name>/<key>
    # holds the decoded value of each data key. Other secrets use the fakes below.
    _store_ns="default"
    _store_args=("$@")
    for ((_i = 0; _i < ${#_store_args[@]}; _i++)); do
        case "${_store_args[_i]}" in
            --namespace|-n) _store_ns="${_store_args[_i + 1]:-default}" ;;
        esac
    done
    if [[ "${1:-}" == "get" && "${2:-}" == "secret" ]] &&
       [[ "${3:-}" == "barbican-simple-crypto-kek" || "${3:-}" == "barbican-etc" || "${3:-}" == "barbican-hsm-credentials" ]]; then
        if [[ "${KUBECTL_STORE_API_ERROR:-}" == "1" || "${KUBECTL_STORE_API_ERROR:-}" == "${3}" ]]; then
            echo "Unable to connect to the server: dial tcp 10.0.0.1:6443: connect: connection refused" >&2
            exit 1
        fi
        _store_dir="${KUBECTL_SECRET_DIR}/${_store_ns}/${3}"
        if [[ ! -d "$_store_dir" ]]; then
            echo "Error from server (NotFound): secrets \"${3}\" not found" >&2
            exit 1
        fi
        for _a in "$@"; do
            case "$_a" in
                "jsonpath={.data['"*)
                    _k="${_a#"jsonpath={.data['"}"
                    _k="${_k%"']}"}"
                    _k="${_k//\\\\./.}"
                    _k="${_k//\\./.}"
                    if [[ -f "${_store_dir}/${_k}" ]]; then
                        base64 < "${_store_dir}/${_k}" | tr -d '\n'
                    fi
                    exit 0
                    ;;
            esac
        done
        if [[ " $* " == *" json "* ]]; then
            _json="{"
            for _f in "${_store_dir}"/*; do
                [[ -f "$_f" ]] || continue
                _json+="\"$(basename "$_f")\":\"$(base64 < "$_f" | tr -d '\n')\","
            done
            printf '{"data":%s}\n' "${_json%,}}"
            exit 0
        fi
        echo "secret/${3}"
        exit 0
    fi
    if [[ "${1:-}" == "create" && "${2:-}" == "secret" && "${3:-}" == "generic" && "${4:-}" == "barbican-hsm-credentials" ]]; then
        # secret_ensure: record the literal so later lookups see it.
        mkdir -p "${KUBECTL_SECRET_DIR}/${_store_ns}/${4}"
        for _a in "$@"; do
            case "$_a" in
                --from-literal=*) _kv="${_a#--from-literal=}"; printf '%s' "${_kv#*=}" > "${KUBECTL_SECRET_DIR}/${_store_ns}/${4}/${_kv%%=*}" ;;
            esac
        done
        exit 0
    fi
    if [[ " $* " == *" apply "* && " $* " == *" -f - "* ]]; then
        _manifest="$(cat)"
        _name="$(yq e '.metadata.name' - <<< "$_manifest")"
        _mns="$(yq e '.metadata.namespace // "default"' - <<< "$_manifest")"
        mkdir -p "${KUBECTL_SECRET_DIR}/${_mns}/${_name}"
        while IFS='|' read -r _dk _dv; do
            [[ -n "$_dk" ]] || continue
            printf '%s' "$_dv" | base64 -d > "${KUBECTL_SECRET_DIR}/${_mns}/${_name}/${_dk}"
        done < <(yq e '.data | to_entries | .[] | .key + "|" + .value' - <<< "$_manifest")
        echo "secret/${_name} configured"
        exit 0
    fi
fi

lookup_secret() {
    local namespace="$1"
    local secret_name="$2"
    local data_key="$3"
    case "${namespace}/${secret_name}:${data_key}" in
        openstack/nova-ssh:public-key) printf '%s' "ssh-ed25519 AAAANOVA" ;;
        openstack/nova-ssh:private-key) printf '%s' "NOVA_PRIVATE_KEY" ;;
        testing/synthetic-multi-keypair:private-key) printf '%s' "MULTI_PRIVATE_KEY" ;;
        kube-system/kube-ovn-tls:cert)
            if [[ -n "${KUBECTL_TLS_CERT_FILE:-}" ]]; then
                cat "$KUBECTL_TLS_CERT_FILE"
            else
                printf '%s' "${secret_name}-${data_key}-value"
            fi
            ;;
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

    if [[ "${KUBECTL_SECRET_GET_ERROR:-0}" == "1" ]]; then
        echo "Unable to connect to the server: dial tcp 10.0.0.1:6443: connect: connection refused" >&2
        exit 1
    fi

    if secret_is_missing "$namespace" "$secret_name"; then
        echo "Error from server (NotFound): secrets \"${secret_name}\" not found" >&2
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
        if [[ "${KUBECTL_SECRET_JSON_EMPTY:-0}" == "1" ]]; then _sk_out="{}"; fi
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

if [[ "${1:-}" == "create" && "${2:-}" == "secret" && -n "${KUBECTL_CAPTURE_DIR:-}" ]]; then
    # Keep the files a secret is built from; the installer deletes its own copies.
    for _arg in "$@"; do
        if [[ "$_arg" == --from-file=* ]]; then
            _kv="${_arg#--from-file=}"
            cp "${_kv#*=}" "${KUBECTL_CAPTURE_DIR}/${_kv%%=*}"
        fi
    done
    exit 0
fi

if [[ "${1:-}" == "apply" ]]; then
    # Like the real kubectl, report what was applied.
    echo "secret/applied"
    exit 0
fi

if [[ "${KUBECTL_FAIL_ANNOTATE:-0}" == "1" ]]; then
    for _arg in "$@"; do
        [[ "$_arg" == "annotate" ]] && exit 1
    done
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
    if [[ "${KUBECTL_DEPLOY_GET_ERROR:-0}" == "1" ]]; then
        echo "Unable to connect to the server: dial tcp 10.0.0.1:6443: connect: connection refused" >&2
        exit 1
    fi
    if [[ "${KUBECTL_DEPLOY_NOT_FOUND:-0}" == "1" ]]; then
        echo 'Error from server (NotFound): deployments.apps "ovn-central" not found' >&2
        exit 1
    fi
    echo "${KUBECTL_ENABLE_SSL:-false}"
    exit 0
fi

if [[ "${1:-}" == "get" && "${2:-}" == "service" && "${KUBECTL_NO_OVN_SERVICES:-0}" == "1" ]]; then
    exit 1
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
    [[ "${KUBECTL_NO_NODES:-0}" == "1" ]] || printf '10.0.0.21\n10.0.0.22\n'
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

# Record what a post-renderer started by helm would inherit.
if [[ -n "${HELM_ENV_LOG_FILE:-}" && "${1:-}" == "upgrade" ]]; then
    printf 'SSL=%s\n' "${GENESTACK_KUBE_OVN_ENABLE_SSL:-unset}" >> "${HELM_ENV_LOG_FILE}"
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
                    ovn_tls_values)
                        [[ -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | .file // \"\"" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" ]] ||
                            failures+="${svc}:${action_path}:${type}:file-required"$'\n'
                        ;;
                    secret_sync_directory)
                        [[ -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | (.secret_name // \"\") + (.directory // \"\")" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" &&
                           -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | .secret_name // \"\"" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" &&
                           -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | .directory // \"\"" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" ]] ||
                            failures+="${svc}:${action_path}:${type}:secret_name-and-directory-required"$'\n'
                        ;;
                    barbican_simple_crypto_kek)
                        ;;
                    barbican_hsm_setup|barbican_hsm_init)
                        ;;
                    cluster_name_site_value)
                        [[ -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | .helm_key // \"\"" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" ]] ||
                            failures+="${svc}:${action_path}:${type}:helm_key-required"$'\n'
                        ;;
                    kube_ovn_tls_secret)
                        [[ -n "$(yq e "${action_path}[]? | select(.type == \"${type}\") | .dns_names[]? // \"\"" "$f" 2>/dev/null | sed '/^$/d;/^null$/d')" ]] ||
                            failures+="${svc}:${action_path}:${type}:dns_names-required"$'\n'
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

# ovn_tls_values appends its values file to additional_base_values only when
# Kube-OVN uses SSL (CONNECTION_STRING=ssl), and fails on bad input.
test_ovn_tls_values_action() {
    local tmp_root svc_yaml no_file_yaml expected rc output
    local GENESTACK_BASE_DIR CONNECTION_STRING
    local additional_base_values=()
    tmp_root="$(mktemp -d)"
    GENESTACK_BASE_DIR="${tmp_root}/base"
    expected="${GENESTACK_BASE_DIR}/base-helm-configs/tls-demo/ssl/demo-ovn-tls-overrides.yaml"
    mkdir -p "${expected%/*}"
    printf '{}\n' > "$expected"
    svc_yaml="$(cat <<'EOF'
service:
  name: tls-demo
pre_install_check_actions:
  - type: ovn_tls_values
    file: ssl/demo-ovn-tls-overrides.yaml
EOF
)"
    no_file_yaml="$(cat <<'EOF'
service:
  name: tls-demo
pre_install_check_actions:
  - type: ovn_tls_values
EOF
)"

    CONNECTION_STRING=ssl
    additional_base_values=()
    run_service_actions "$svc_yaml" '.pre_install_check_actions' tls-demo 2>/dev/null ||
        fail "ovn_tls_values must succeed when the TLS file exists"
    assert_eq "$expected" "${additional_base_values[*]:-}" "ssl must add the TLS values file"

    for CONNECTION_STRING in tcp ""; do
        additional_base_values=()
        run_service_actions "$svc_yaml" '.pre_install_check_actions' tls-demo 2>/dev/null ||
            fail "ovn_tls_values must succeed without SSL"
        assert_eq "" "${additional_base_values[*]:-}" "the TLS file must not be added without SSL (CONNECTION_STRING='${CONNECTION_STRING}')"
    done

    for CONNECTION_STRING in ssl tcp; do
        rc=0
        output="$(run_service_actions "$no_file_yaml" '.pre_install_check_actions' tls-demo 2>&1)" || rc=$?
        assert_eq "1" "$rc" "ovn_tls_values without a file must fail (CONNECTION_STRING=${CONNECTION_STRING})"
        assert_contains "$output" "Missing file for ovn_tls_values" "a missing file field must be reported"
    done

    CONNECTION_STRING=ssl
    rm -f "$expected"
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_check_actions' tls-demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "ssl with a missing TLS file must fail instead of installing without certificates"
    assert_contains "$output" "Kube-OVN TLS values file not found" "a missing TLS file must be reported"
}

# install.sh --service neutron|octavia must pass the OVN TLS values file to
# Helm only when Kube-OVN uses SSL, after the base values and before the
# global and site overrides.
test_install_ovn_tls_values() {
    local service ssl fakebin tmp_root tmp_base tmp_overrides helm_log kubectl_log cmd tls_file before after
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    for service in neutron octavia; do
        for ssl in true false; do
            tmp_root="$(mktemp -d)"
            tmp_base="${tmp_root}/base"
            tmp_overrides="${tmp_root}/overrides"
            helm_log="${tmp_root}/helm.log"
            kubectl_log="${tmp_root}/kubectl.log"
            tls_file="${tmp_base}/base-helm-configs/${service}/ssl/${service}-ovn-tls-overrides.yaml"
            mkdir -p "${tmp_base}/base-helm-configs" "${tmp_overrides}/kustomize" \
                "${tmp_overrides}/helm-configs/global_overrides" "${tmp_overrides}/helm-configs/${service}"
            cp -R "${REPO_ROOT}/base-helm-configs/${service}" "${tmp_base}/base-helm-configs/"
            mkdir -p "${tmp_base}/base-kustomize"
            [[ ! -d "${REPO_ROOT}/base-kustomize/${service}" ]] || cp -R "${REPO_ROOT}/base-kustomize/${service}" "${tmp_base}/base-kustomize/"
            : > "${tmp_overrides}/helm-configs/global_overrides/global.yaml"
            : > "${tmp_overrides}/helm-configs/${service}/site.yaml"
            printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
            chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
            printf 'charts:\n  %s: 1.0.0\n' "$service" > "${tmp_overrides}/helm-chart-versions.yaml"

            PATH="${fakebin}:$PATH" \
                KUBECTL_BIN=kubectl \
                KUBECTL_ENABLE_SSL="$ssl" \
                KUBECTL_LOG_FILE="$kubectl_log" \
                HELM_LOG_FILE="$helm_log" \
                HELM_ENV_LOG_FILE="${tmp_root}/helm-env.log" \
                GENESTACK_BASE_DIR="$tmp_base" \
                GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
                GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
                GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
                "${REPO_ROOT}/bin/install.sh" --service "$service" --dry-run >/dev/null 2>&1 ||
                fail "install.sh --service ${service} must succeed (ENABLE_SSL=${ssl})"
            cmd="$(grep '^upgrade --install' "$helm_log")"

            # Octavia runs its own post-renderer, which needs to know whether
            # Kube-OVN uses SSL; Neutron keeps the generic kustomize post-renderer.
            assert_contains "$(cat "${tmp_root}/helm-env.log")" "SSL=${ssl}" \
                "helm must inherit GENESTACK_KUBE_OVN_ENABLE_SSL=${ssl} for ${service}"
            if [[ "$service" == "octavia" ]]; then
                assert_contains "$cmd" \
                    "--post-renderer ${tmp_base}/base-kustomize/octavia/post-renderer.sh --post-renderer-args octavia/overlay" \
                    "octavia must use its own post-renderer script"
            else
                assert_contains "$cmd" \
                    "--post-renderer ${tmp_overrides}/kustomize/kustomize.sh --post-renderer-args ${service}/overlay" \
                    "${service} must keep the generic kustomize post-renderer"
            fi

            # Neutron's metadata agent has its own OVN connection settings.
            if [[ "$service" == "neutron" ]]; then
                assert_contains "$cmd" "conf.ovn_metadata_agent.ovn.ovn_nb_connection=" \
                    "neutron must set the metadata agent northbound connection"
                assert_contains "$cmd" "conf.ovn_metadata_agent.ovn.ovn_sb_connection=" \
                    "neutron must set the metadata agent southbound connection"
            fi
            # The client copy of the Kube-OVN secret exists only for ssl: connections.
            if [[ "$ssl" == "true" ]]; then
                assert_contains "$(cat "$kubectl_log")" "apply --namespace openstack" \
                    "${service} must sync openstack/ovn-client-tls when Kube-OVN uses SSL"
            else
                assert_not_contains "$(cat "$kubectl_log")" "apply --namespace openstack" \
                    "${service} must not copy the Kube-OVN private key when Kube-OVN does not use SSL"
            fi
            if [[ "$ssl" == "true" ]]; then
                assert_contains "$cmd" "ssl:" "${service} must use ssl OVN connections when Kube-OVN uses SSL"
                assert_contains "$cmd" "-f ${tls_file}" "${service} must pass its OVN TLS values file when Kube-OVN uses SSL"
                before="${cmd%%-f ${tls_file}*}"
                after="${cmd#*-f ${tls_file}}"
                assert_contains "$before" "${service}-helm-overrides.yaml" "the TLS values must come after the base values"
                assert_contains "$after" "global_overrides/global.yaml" "the TLS values must come before the global overrides"
                assert_contains "$after" "helm-configs/${service}/site.yaml" "the TLS values must come before the site overrides"
            else
                assert_not_contains "$cmd" "ssl/${service}-ovn-tls-overrides.yaml" \
                    "${service} must not pass the OVN TLS values file when Kube-OVN does not use SSL"
            fi
        done
    done
}

# kustomize.post_renderer swaps the post-renderer script (relative to
# GENESTACK_BASE_DIR) and rejects missing, non-executable and unsafe paths.
test_custom_post_renderer() {
    local tmp_root svc_yaml args rc output
    local HELM_KUSTOMIZE_CMD GENESTACK_BASE_DIR
    tmp_root="$(mktemp -d)"
    GENESTACK_BASE_DIR="${tmp_root}/base"
    HELM_KUSTOMIZE_CMD="${tmp_root}/kustomize.sh"
    mkdir -p "${GENESTACK_BASE_DIR}/base-kustomize/demo"
    printf '#!/bin/bash\nexit 0\n' > "$HELM_KUSTOMIZE_CMD"
    printf '#!/bin/bash\nexit 0\n' > "${GENESTACK_BASE_DIR}/base-kustomize/demo/post-renderer.sh"
    chmod +x "$HELM_KUSTOMIZE_CMD" "${GENESTACK_BASE_DIR}/base-kustomize/demo/post-renderer.sh"

    svc_yaml="$(cat <<'EOF'
service:
  name: demo
kustomize:
  enabled: true
  overlay_path: ${service_name}/overlay
  post_renderer: base-kustomize/demo/post-renderer.sh
EOF
)"
    args="$(build_post_renderer_args "$svc_yaml" demo)"
    assert_eq $'--post-renderer\n'"${GENESTACK_BASE_DIR}/base-kustomize/demo/post-renderer.sh"$'\n--post-renderer-args\ndemo/overlay' "$args" \
        "a service post_renderer must replace kustomize.sh and keep the overlay argument"

    chmod -x "${GENESTACK_BASE_DIR}/base-kustomize/demo/post-renderer.sh"
    rc=0
    output="$(build_post_renderer_args "$svc_yaml" demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a non-executable post-renderer must fail"
    assert_contains "$output" "not found or not executable" "a non-executable post-renderer must be reported"

    rm -f "${GENESTACK_BASE_DIR}/base-kustomize/demo/post-renderer.sh"
    rc=0
    output="$(build_post_renderer_args "$svc_yaml" demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a missing post-renderer must fail instead of falling back to kustomize.sh"

    for unsafe in /usr/bin/helm ../outside.sh; do
        rc=0
        output="$(build_post_renderer_args "$(printf '%s\n' "$svc_yaml" | yq ".kustomize.post_renderer = \"${unsafe}\"")" demo 2>&1)" || rc=$?
        assert_eq "1" "$rc" "post_renderer '${unsafe}' must be rejected"
        assert_contains "$output" "must be a path relative to" "an unsafe post_renderer path must be reported"
    done
}

# Run the real Octavia post-renderer against a sample manifest: with SSL it
# adds the ovn-tls mount to the octavia-agent sidecar (which only exists after
# kustomize), without SSL it removes every ovn-tls volume and mount.
test_octavia_post_renderer_ssl_wiring() {
    local tmp_root overrides script out rc output sidecar_mounts total_mounts volumes
    tmp_root="$(mktemp -d)"
    overrides="${tmp_root}/overrides"
    script="${REPO_ROOT}/base-kustomize/octavia/post-renderer.sh"
    mkdir -p "${overrides}/kustomize"
    cat > "${tmp_root}/rendered.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: octavia-api
spec:
  template:
    spec:
      containers:
        - name: octavia-api
          volumeMounts:
            - name: ovn-tls
              mountPath: /etc/octavia/ovn
        - name: octavia-agent
          volumeMounts:
            - name: pod-run-octavia
              mountPath: /var/run/octavia
      volumes:
        - name: ovn-tls
          secret:
            secretName: ovn-client-tls
EOF
    printf '#!/bin/bash\ncat "%s/rendered.yaml"\n' "$tmp_root" > "${overrides}/kustomize/kustomize.sh"
    chmod +x "${overrides}/kustomize/kustomize.sh"

    out="${tmp_root}/out.yaml"
    GENESTACK_OVERRIDES_DIR="$overrides" GENESTACK_KUBE_OVN_ENABLE_SSL=true "$script" octavia/overlay > "$out" ||
        fail "the octavia post-renderer must succeed with SSL"
    sidecar_mounts="$(yq e '.spec.template.spec.containers[] | select(.name == "octavia-agent") | .volumeMounts[] | select(.name == "ovn-tls") | .mountPath' "$out")"
    assert_eq "/etc/octavia/ovn" "$sidecar_mounts" "with SSL the octavia-agent sidecar must get the ovn-tls mount"
    volumes="$(yq e '[.spec.template.spec.volumes[] | select(.name == "ovn-tls")] | length' "$out")"
    assert_eq "1" "$volumes" "with SSL the ovn-tls volume must be kept"

    for state in false unset; do
        if [[ "$state" == unset ]]; then
            GENESTACK_OVERRIDES_DIR="$overrides" env -u GENESTACK_KUBE_OVN_ENABLE_SSL "$script" octavia/overlay > "$out" ||
                fail "the octavia post-renderer must succeed without the SSL variable"
        else
            GENESTACK_OVERRIDES_DIR="$overrides" GENESTACK_KUBE_OVN_ENABLE_SSL=false "$script" octavia/overlay > "$out" ||
                fail "the octavia post-renderer must succeed without SSL"
        fi
        total_mounts="$(yq e '[.spec.template.spec.containers[].volumeMounts[]? | select(.name == "ovn-tls")] | length' "$out")"
        volumes="$(yq e '[.spec.template.spec.volumes[]? | select(.name == "ovn-tls")] | length' "$out")"
        assert_eq "0/0" "${total_mounts}/${volumes}" "without SSL (${state}) every ovn-tls mount and volume must be removed"
    done

    # With SSL the sidecar must exist; a missing one is a hard error.
    yq -i 'del(.spec.template.spec.containers[] | select(.name == "octavia-agent"))' "${tmp_root}/rendered.yaml"
    rc=0
    output="$(GENESTACK_OVERRIDES_DIR="$overrides" GENESTACK_KUBE_OVN_ENABLE_SSL=true "$script" octavia/overlay 2>&1)" || rc=$?
    [[ "$rc" -ne 0 ]] || fail "with SSL a missing octavia-agent sidecar must fail the post-renderer"
    assert_contains "$output" "Unable to find the Octavia OVN driver-agent sidecar" "a missing sidecar must be reported"
}

# cluster_name_site_value mirrors the old install-mariadb-operator.sh: with a
# custom CLUSTER_NAME it records the domain in the service's site values file;
# with the default it leaves the site files alone.
test_cluster_name_site_value() {
    local tmp_root svc_yaml nested_yaml site_file nested_file rc output
    local GENESTACK_OVERRIDES_DIR CLUSTER_NAME
    tmp_root="$(mktemp -d)"
    GENESTACK_OVERRIDES_DIR="${tmp_root}/overrides"
    site_file="${GENESTACK_OVERRIDES_DIR}/helm-configs/cn-demo/cn-demo-helm-overrides.yaml"
    nested_file="${GENESTACK_OVERRIDES_DIR}/helm-configs/cn-nested/cn-nested-helm-overrides.yaml"
    svc_yaml="$(cat <<'EOF'
service:
  name: cn-demo
pre_install_actions:
  - type: cluster_name_site_value
    helm_key: clusterName
EOF
)"
    nested_yaml="$(cat <<'EOF'
service:
  name: cn-nested
pre_install_actions:
  - type: cluster_name_site_value
    helm_key: redisOperator.serviceDNSDomain
EOF
)"

    # Default or unset: nothing is written.
    for CLUSTER_NAME in "" cluster.local; do
        run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null ||
            fail "the action must succeed for CLUSTER_NAME='${CLUSTER_NAME}'"
        [[ ! -e "$site_file" ]] || fail "CLUSTER_NAME='${CLUSTER_NAME}' must not create a site file"
    done

    # Custom domain, no site file yet: the file is created.
    CLUSTER_NAME=my.cluster.domain
    run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null ||
        fail "the action must succeed for a custom CLUSTER_NAME"
    assert_eq "my.cluster.domain" "$(yq e '.clusterName' "$site_file")" "a custom CLUSTER_NAME must be written to the site file"

    # Existing site file: other settings and comments are kept, the key is replaced.
    printf '# site tuning\nreplicas: 3\nclusterName: old.domain\n' > "$site_file"
    run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null ||
        fail "the action must succeed for an existing site file"
    assert_eq "my.cluster.domain" "$(yq e '.clusterName' "$site_file")" "an existing clusterName must be replaced"
    assert_eq "3" "$(yq e '.replicas' "$site_file")" "other site settings must be kept"
    assert_contains "$(cat "$site_file")" "# site tuning" "site file comments must be kept"

    # Existing site file without the key: it is added.
    printf 'replicas: 3\n' > "$site_file"
    run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null ||
        fail "the action must succeed when the key is missing"
    assert_eq "my.cluster.domain/3" "$(yq e '.clusterName' "$site_file")/$(yq e '.replicas' "$site_file")" \
        "a missing clusterName must be added next to the existing settings"

    # Running again changes nothing.
    cp "$site_file" "${site_file}.before"
    run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null
    cmp -s "$site_file" "${site_file}.before" || fail "rerunning the action must not change the site file"

    # A dotted key is set at its nested position.
    run_service_actions "$nested_yaml" '.pre_install_actions' cn-nested 2>/dev/null ||
        fail "a dotted helm_key must be accepted"
    assert_eq "my.cluster.domain" "$(yq e '.redisOperator.serviceDNSDomain' "$nested_file")" "a dotted helm_key must be written nested"

    # Bad input fails instead of writing anything.
    CLUSTER_NAME='bad domain; rm -rf /'
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an invalid CLUSTER_NAME must fail"
    assert_contains "$output" "not a valid DNS domain" "an invalid CLUSTER_NAME must be reported"
    CLUSTER_NAME=my.cluster.domain
    rc=0
    output="$(run_service_actions "$(printf '%s\n' "$svc_yaml" | yq '.pre_install_actions[0].helm_key = "a b"')" '.pre_install_actions' cn-demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an invalid helm_key must fail"
    rc=0
    output="$(run_service_actions "$(printf '%s\n' "$svc_yaml" | yq 'del(.pre_install_actions[0].helm_key)')" '.pre_install_actions' cn-demo 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a missing helm_key must fail"

    # A domain set by hand in an existing site file is left byte-identical when
    # CLUSTER_NAME is unset or the default, for plain and dotted keys.
    printf '# site tuning\nreplicas: 3\nclusterName: site.domain\n' > "$site_file"
    printf '# site tuning\nreplicas: 3\nredisOperator:\n  serviceDNSDomain: site.domain\n' > "$nested_file"
    cp "$site_file" "${site_file}.before"
    cp "$nested_file" "${nested_file}.before"
    for CLUSTER_NAME in "" cluster.local; do
        run_service_actions "$svc_yaml" '.pre_install_actions' cn-demo 2>/dev/null ||
            fail "the action must succeed with a hand-written domain (CLUSTER_NAME='${CLUSTER_NAME}')"
        run_service_actions "$nested_yaml" '.pre_install_actions' cn-nested 2>/dev/null ||
            fail "the action must succeed with a hand-written dotted domain (CLUSTER_NAME='${CLUSTER_NAME}')"
        cmp -s "$site_file" "${site_file}.before" ||
            fail "CLUSTER_NAME='${CLUSTER_NAME}' must leave a hand-written clusterName untouched"
        cmp -s "$nested_file" "${nested_file}.before" ||
            fail "CLUSTER_NAME='${CLUSTER_NAME}' must leave a hand-written dotted domain untouched"
    done
    assert_eq "site.domain" "$(yq e '.clusterName' "$site_file")" "the hand-written clusterName must survive"
    assert_eq "site.domain" "$(yq e '.redisOperator.serviceDNSDomain' "$nested_file")" "the hand-written dotted domain must survive"
}

# install.sh --service mariadb-operator passes the site file written for
# CLUSTER_NAME to Helm, after the base values.
test_install_mariadb_cluster_name() {
    local fakebin tmp_root tmp_base tmp_overrides helm_log cmd site_file custom
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    for custom in my.cluster.domain ""; do
        tmp_root="$(mktemp -d)"
        tmp_base="${tmp_root}/base"
        tmp_overrides="${tmp_root}/overrides"
        helm_log="${tmp_root}/helm.log"
        site_file="${tmp_overrides}/helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml"
        mkdir -p "${tmp_base}/base-helm-configs" "${tmp_overrides}/kustomize"
        cp -R "${REPO_ROOT}/base-helm-configs/mariadb-operator" "${tmp_base}/base-helm-configs/"
        printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
        chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
        printf 'charts:\n  mariadb-operator: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"

        PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            CLUSTER_NAME="$custom" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service mariadb-operator --dry-run >/dev/null 2>&1 ||
            fail "install.sh --service mariadb-operator must succeed (CLUSTER_NAME='${custom}')"
        cmd="$(grep '^upgrade --install mariadb-operator ' "$helm_log")"

        if [[ -n "$custom" ]]; then
            assert_eq "$custom" "$(yq e '.clusterName' "$site_file")" "the site file must carry CLUSTER_NAME"
            assert_contains "$cmd" "-f ${site_file}" "Helm must load the site file written for CLUSTER_NAME"
            assert_contains "${cmd#*overrides.yaml}" "${site_file}" "the site file must come after the base values"
        else
            [[ ! -e "$site_file" ]] || fail "without CLUSTER_NAME no site file may be written"
            assert_not_contains "$cmd" "${tmp_overrides}/helm-configs/mariadb-operator" "without CLUSTER_NAME no site values file may be passed"
        fi
    done
}

# install.sh --service redis-operator records CLUSTER_NAME as
# redisOperator.serviceDNSDomain in the site values file; the chart passes it
# to the operator as SERVICE_DNS_DOMAIN.
test_install_redis_operator_cluster_name() {
    local fakebin tmp_root tmp_base tmp_overrides helm_log cmd site_file custom
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"

    for custom in my.cluster.domain ""; do
        tmp_root="$(mktemp -d)"
        tmp_base="${tmp_root}/base"
        tmp_overrides="${tmp_root}/overrides"
        helm_log="${tmp_root}/helm.log"
        site_file="${tmp_overrides}/helm-configs/redis-operator/redis-operator-helm-overrides.yaml"
        mkdir -p "${tmp_base}/base-helm-configs" "${tmp_overrides}/kustomize"
        cp -R "${REPO_ROOT}/base-helm-configs/redis-operator" "${tmp_base}/base-helm-configs/"
        printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
        chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
        printf 'charts:\n  redis-operator: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"

        PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            CLUSTER_NAME="$custom" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service redis-operator --dry-run >/dev/null 2>&1 ||
            fail "install.sh --service redis-operator must succeed (CLUSTER_NAME='${custom}')"
        cmd="$(grep '^upgrade --install redis-operator ' "$helm_log")"

        if [[ -n "$custom" ]]; then
            assert_eq "$custom" "$(yq e '.redisOperator.serviceDNSDomain' "$site_file")" \
                "the site file must carry CLUSTER_NAME as redisOperator.serviceDNSDomain"
            assert_contains "$cmd" "-f ${site_file}" "Helm must load the site file written for CLUSTER_NAME"
        else
            [[ ! -e "$site_file" ]] || fail "without CLUSTER_NAME no site file may be written"
            assert_not_contains "$cmd" "${tmp_overrides}/helm-configs/redis-operator" "without CLUSTER_NAME no site values file may be passed"
        fi
    done
}

# kube_ovn_tls_secret mirrors the old install-kube-ovn.sh: a missing
# kube-system/kube-ovn-tls is created with a private CA and a certificate that
# carries the OVN service DNS names, then annotated and labelled for Helm. An
# existing secret is left alone.
test_kube_ovn_tls_secret() (
    local fakebin tmp_root capture log svc_yaml regen_yaml cert name rc output
    # The suite stubs secret_exists and secret_get; this test needs the real
    # ones, and runs in a subshell so the stubs stay in place for other tests.
    # shellcheck source=../bin/helpers.sh
    source "${REPO_ROOT}/bin/helpers.sh"
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    capture="${tmp_root}/capture"
    log="${tmp_root}/kubectl.log"
    mkdir -p "$capture"
    PATH="${fakebin}:$PATH"
    KUBECTL_BIN=kubectl
    export PATH KUBECTL_BIN KUBECTL_LOG_FILE="$log" KUBECTL_CAPTURE_DIR="$capture"
    # Use the action exactly as kube-ovn.yaml ships it.
    svc_yaml="$(yq e '{"service": .service, "pre_install_actions": [.pre_install_actions[] | select(.type == "kube_ovn_tls_secret")]}' \
        "${REPO_ROOT}/bin/services/kube-ovn.yaml")"
    [[ "$(yq e '.pre_install_actions | length' - <<< "$svc_yaml")" == "1" ]] ||
        fail "kube-ovn.yaml must carry one kube_ovn_tls_secret action"

    # Existing secret: nothing is generated or changed.
    export MISSING_SECRET_REFS=""
    : > "$log"
    run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>/dev/null ||
        fail "the action must succeed when the secret exists"
    [[ -z "$(ls -A "$capture")" ]] || fail "an existing kube-ovn-tls must not be regenerated"
    assert_not_contains "$(cat "$log")" "create secret" "an existing kube-ovn-tls must not be recreated"
    assert_not_contains "$(cat "$log")" "annotate" "an existing kube-ovn-tls must not be annotated"

    # Missing secret: created with the DNS names, signed by its own CA.
    export MISSING_SECRET_REFS="kube-system/kube-ovn-tls"
    : > "$log"
    run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>/dev/null ||
        fail "the action must succeed when the secret is missing"
    for name in cacert cert key; do
        [[ -s "${capture}/${name}" ]] || fail "kube-ovn-tls must carry ${name}"
    done
    # The SAN entries, as ",DNS:a,DNS:b,...," so each name matches as a whole.
    cert=",$(openssl x509 -in "${capture}/cert" -noout -text | { grep -A1 'Subject Alternative Name' || true; } | tail -n 1 | tr -d ' '),"
    for name in ovn ovn-nb ovn-nb.kube-system.svc ovn-sb ovn-sb.kube-system.svc ovn-northd ovn-northd.kube-system.svc; do
        assert_contains "$cert" ",DNS:${name}," "the certificate must list DNS:${name}"
    done
    openssl verify -CAfile "${capture}/cacert" "${capture}/cert" >/dev/null 2>&1 ||
        fail "the certificate must verify against the cacert in the secret"
    [[ "$(openssl x509 -in "${capture}/cert" -noout -pubkey)" == "$(openssl pkey -in "${capture}/key" -pubout)" ]] ||
        fail "the key in the secret must match the certificate"
    openssl x509 -in "${capture}/cert" -noout -checkend $((3649 * 86400)) >/dev/null ||
        fail "the certificate must be valid for about 3650 days"
    ! openssl x509 -in "${capture}/cert" -noout -checkend $((3651 * 86400)) >/dev/null ||
        fail "the certificate must not outlive 3650 days"
    assert_contains "$(cat "$log")" "create secret generic kube-ovn-tls --namespace kube-system" \
        "the secret must be created in kube-system"
    assert_contains "$(cat "$log")" \
        "annotate secret kube-ovn-tls --overwrite meta.helm.sh/release-name=kube-ovn meta.helm.sh/release-namespace=kube-system" \
        "the secret must carry the Helm release annotations"
    assert_contains "$(cat "$log")" "label secret kube-ovn-tls --overwrite app.kubernetes.io/managed-by=Helm" \
        "the secret must carry the Helm managed-by label"

    # A kept secret reports the validity of its certificate so the operator can
    # decide whether to regenerate.
    cp "${capture}/cert" "${tmp_root}/existing-cert.pem"
    export MISSING_SECRET_REFS=""
    export KUBECTL_TLS_CERT_FILE="${tmp_root}/existing-cert.pem"
    : > "$log"
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" ||
        fail "the action must succeed for an existing secret"
    assert_contains "$output" "Existing kube-system/kube-ovn-tls certificate" "a kept secret must report its certificate"
    assert_contains "$output" "valid from" "the report must show the validity period"
    assert_contains "$output" "days left" "the report must show the days left"
    assert_contains "$output" "DNS:ovn-nb.kube-system.svc" "the report must list the DNS names"
    assert_contains "$output" "KUBE_OVN_REGENERATE_CERTS=true" "the report must say how to regenerate"
    assert_contains "$output" "service-configs/kube-ovn.yaml" "the report must name the service-configs file"
    assert_not_contains "$output" "PRIVATE KEY" "the report must never print key material"
    assert_not_contains "$(cat "$log")" "create secret" "reporting must not write anything"

    # A short-lived certificate without DNS names is flagged.
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "${tmp_root}/short.key" -out "${tmp_root}/short.pem" \
        -days 5 -subj "/CN=ovn" >/dev/null 2>&1
    export KUBECTL_TLS_CERT_FILE="${tmp_root}/short.pem"
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" ||
        fail "the action must succeed for a short-lived certificate"
    assert_contains "$output" "certificate expires within 30 days" "a certificate close to expiry must be flagged"
    assert_contains "$output" "DNS names: none" "a certificate without DNS names must be reported as such"

    # An unreadable certificate is a warning, not a failure.
    printf 'not a certificate\n' > "${tmp_root}/bad.pem"
    export KUBECTL_TLS_CERT_FILE="${tmp_root}/bad.pem"
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" ||
        fail "an unreadable certificate must not fail the action"
    assert_contains "$output" "Could not read a certificate" "an unreadable certificate must be reported"
    unset KUBECTL_TLS_CERT_FILE
    export MISSING_SECRET_REFS="kube-system/kube-ovn-tls"
    rm -f "${capture}"/*
    : > "$log"

    # Marking it for Helm fails: the secret is kept (never deleted) and the
    # error says how to mark it by hand.
    rm -f "${capture}"/*
    : > "$log"
    export KUBECTL_FAIL_ANNOTATE=1
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    unset KUBECTL_FAIL_ANNOTATE
    assert_eq "1" "$rc" "a failed annotate must fail the action"
    assert_not_contains "$(cat "$log")" "delete secret" "the secret must not be deleted when it cannot be marked for Helm"
    assert_contains "$output" "annotate secret kube-ovn-tls --overwrite" "the error must say how to mark the secret by hand"

    # kubectl cannot say whether the secret exists (not NotFound): nothing is
    # generated or written, so a live secret can never be overwritten.
    rm -f "${capture}"/*
    : > "$log"
    export KUBECTL_SECRET_GET_ERROR=1
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    unset KUBECTL_SECRET_GET_ERROR
    assert_eq "1" "$rc" "an API error while looking up the secret must fail the action"
    assert_contains "$output" "Cannot tell whether kube-system/kube-ovn-tls exists" "the lookup error must be reported"
    assert_contains "$output" "connection refused" "the kubectl error must be shown"
    [[ -z "$(ls -A "$capture")" ]] || fail "nothing may be generated when the lookup fails"
    assert_not_contains "$(cat "$log")" "create secret" "nothing may be created when the lookup fails"
    assert_not_contains "$(cat "$log")" "delete secret" "nothing may be deleted when the lookup fails"

    # regenerate_certs is false by default, so existing environments keep
    # their secret on every reinstall and upgrade.
    assert_eq "false" "$(yq e '.regenerate_certs' "${REPO_ROOT}/bin/services/kube-ovn.yaml")" \
        "kube-ovn.yaml must ship regenerate_certs: false"
    export MISSING_SECRET_REFS=""
    for name in unset false; do
        : > "$log"
        regen_yaml="$svc_yaml"
        [[ "$name" == "unset" ]] || regen_yaml="$(yq e '.regenerate_certs = false' - <<< "$svc_yaml")"
        run_service_actions "$regen_yaml" '.pre_install_actions' kube-ovn >/dev/null 2>&1 ||
            fail "the action must succeed with regenerate_certs ${name}"
        assert_not_contains "$(cat "$log")" "create secret" "regenerate_certs ${name} must keep the existing secret"
    done

    # regenerate_certs: true replaces the existing secret, never deletes it,
    # and tells the operator what to restart.
    rm -f "${capture}"/*
    : > "$log"
    regen_yaml="$(yq e '.regenerate_certs = true' - <<< "$svc_yaml")"
    output="$(run_service_actions "$regen_yaml" '.pre_install_actions' kube-ovn 2>&1)" ||
        fail "the action must succeed with regenerate_certs: true"
    assert_contains "$(cat "$log")" "create secret generic kube-ovn-tls" "regenerate_certs: true must write a new secret"
    assert_contains "$(cat "$log")" "annotate secret kube-ovn-tls --overwrite" "a regenerated secret must be re-marked for Helm"
    assert_not_contains "$(cat "$log")" "delete secret" "a regenerated secret must not be deleted"
    for name in cacert cert key; do
        [[ -s "${capture}/${name}" ]] || fail "the regenerated secret must carry ${name}"
    done
    assert_contains "$output" "Regenerating kube-system/kube-ovn-tls" "regeneration must be announced"
    assert_contains "$output" "Restart the Kube-OVN and OVN components" "regeneration must say what to restart"
    assert_contains "$output" "Set regenerate_certs back to false" "regeneration must remind the operator to switch it off"

    # The environment variable opts in for one run without editing any file,
    # and wins over the YAML value in both directions.
    rm -f "${capture}"/*
    : > "$log"
    output="$(KUBE_OVN_REGENERATE_CERTS=true run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" ||
        fail "the action must succeed with KUBE_OVN_REGENERATE_CERTS=true"
    assert_contains "$(cat "$log")" "create secret generic kube-ovn-tls" "KUBE_OVN_REGENERATE_CERTS=true must replace the secret"
    assert_contains "$output" "Set regenerate_certs back to false (and unset KUBE_OVN_REGENERATE_CERTS)" \
        "regeneration must remind the operator to unset the variable"
    : > "$log"
    KUBE_OVN_REGENERATE_CERTS=false run_service_actions "$regen_yaml" '.pre_install_actions' kube-ovn >/dev/null 2>&1 ||
        fail "the action must succeed with KUBE_OVN_REGENERATE_CERTS=false"
    assert_not_contains "$(cat "$log")" "create secret" "KUBE_OVN_REGENERATE_CERTS=false must win over regenerate_certs: true"
    : > "$log"
    rc=0
    output="$(KUBE_OVN_REGENERATE_CERTS=maybe run_service_actions "$svc_yaml" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an invalid KUBE_OVN_REGENERATE_CERTS must fail"
    assert_contains "$output" "KUBE_OVN_REGENERATE_CERTS must be true or false" "an invalid variable must be reported"
    assert_not_contains "$(cat "$log")" "create secret" "an invalid variable must not create a secret"

    # A value other than true or false is rejected before anything happens.
    : > "$log"
    rc=0
    output="$(run_service_actions "$(yq e '.regenerate_certs = "maybe"' - <<< "$svc_yaml")" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an invalid regenerate_certs must fail"
    assert_contains "$output" "regenerate_certs must be true or false" "an invalid switch must be reported"
    assert_not_contains "$(cat "$log")" "create secret" "an invalid switch must not create a secret"

    # A missing secret is still generated without the switch.
    export MISSING_SECRET_REFS="kube-system/kube-ovn-tls"
    rm -f "${capture}"/*
    : > "$log"

    # Bad input fails before anything is created.
    : > "$log"
    rc=0
    output="$(run_service_actions "$(yq e 'del(.pre_install_actions[0].dns_names)' - <<< "$svc_yaml")" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    assert_eq "1" "$rc" "missing dns_names must fail"
    assert_contains "$output" "Missing dns_names" "missing dns_names must be reported"
    rc=0
    output="$(run_service_actions "$(yq e '.pre_install_actions[0].dns_names[0] = "bad name;x"' - <<< "$svc_yaml")" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    assert_eq "1" "$rc" "an invalid DNS name must fail"
    assert_contains "$output" "Invalid DNS name" "an invalid DNS name must be reported"
    rc=0
    output="$(run_service_actions "$(yq e '.pre_install_actions[0].days = "abc"' - <<< "$svc_yaml")" '.pre_install_actions' kube-ovn 2>&1)" || rc=$?
    assert_eq "1" "$rc" "invalid days must fail"
    assert_not_contains "$(cat "$log")" "create secret" "invalid input must not create a secret"
    rm -rf "$tmp_root" "$fakebin"
)

# install.sh --service kube-ovn creates the TLS secret before Helm runs.
test_install_kube_ovn_tls_secret() {
    local fakebin tmp_root tmp_base tmp_overrides helm_log kubectl_log install_out ns_line secret_line regen rc
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    tmp_base="${tmp_root}/base"
    tmp_overrides="${tmp_root}/overrides"
    helm_log="${tmp_root}/helm.log"
    kubectl_log="${tmp_root}/kubectl.log"
    mkdir -p "${tmp_base}/base-helm-configs" "${tmp_overrides}/kustomize" "${tmp_root}/capture"
    [[ ! -d "${REPO_ROOT}/base-helm-configs/kube-ovn" ]] || cp -R "${REPO_ROOT}/base-helm-configs/kube-ovn" "${tmp_base}/base-helm-configs/"
    printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
    chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
    printf 'charts:\n  kube-ovn: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"

    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        KUBECTL_LOG_FILE="$kubectl_log" \
        KUBECTL_CAPTURE_DIR="${tmp_root}/capture" \
        MISSING_SECRET_REFS="kube-system/kube-ovn-tls" \
        HELM_LOG_FILE="$helm_log" \
        GENESTACK_BASE_DIR="$tmp_base" \
        GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
        GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --service kube-ovn --dry-run >"${tmp_root}/install.out" 2>&1 ||
        fail "install.sh --service kube-ovn must succeed"
    install_out="$(cat "${tmp_root}/install.out")"
    # The namespace is ensured before the pre-install hooks create the secret.
    ns_line="$(grep -n '^get namespace kube-system' "$kubectl_log" | head -n 1 | cut -d: -f1)"
    secret_line="$(grep -n '^create secret generic kube-ovn-tls' "$kubectl_log" | head -n 1 | cut -d: -f1)"
    [[ -n "$ns_line" && -n "$secret_line" && "$ns_line" -lt "$secret_line" ]] ||
        fail "the namespace must be ensured before kube-ovn-tls is created (namespace line '${ns_line}', secret line '${secret_line}')"
    assert_contains "$install_out" "Namespace 'kube-system' already exists." "install.sh must report the namespace"
    [[ "${install_out%%Namespace \'kube-system\' already exists.*}" != *"Running pre-install hook"* ]] ||
        fail "the namespace message must come before the pre-install hook header"
    assert_contains "$(cat "$kubectl_log")" "create secret generic kube-ovn-tls" "install.sh must create kube-ovn-tls"
    assert_contains "$(cat "$kubectl_log")" "annotate secret kube-ovn-tls" "install.sh must annotate kube-ovn-tls for Helm"
    assert_contains "$(openssl x509 -in "${tmp_root}/capture/cert" -noout -text)" "DNS:ovn-nb.kube-system.svc" \
        "install.sh must generate the certificate with the OVN DNS names"
    grep -q '^upgrade --install kube-ovn ' "$helm_log" || fail "Helm must run for kube-ovn"

    # Reinstall or upgrade with the secret in place: kept by default, and only
    # replaced when a service-configs override turns regenerate_certs on.
    for regen in default override env; do
        : > "$kubectl_log"
        rm -f "${tmp_root}/capture"/*
        mkdir -p "${tmp_overrides}/service-configs"
        rm -f "${tmp_overrides}/service-configs/kube-ovn.yaml"
        [[ "$regen" != "override" ]] || printf 'regenerate_certs: true\n' > "${tmp_overrides}/service-configs/kube-ovn.yaml"
        PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_LOG_FILE="$kubectl_log" \
            KUBECTL_CAPTURE_DIR="${tmp_root}/capture" \
            MISSING_SECRET_REFS="" \
            KUBE_OVN_REGENERATE_CERTS="$([[ "$regen" == env ]] && echo true || true)" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service kube-ovn --dry-run >"${tmp_root}/install.out" 2>&1 ||
            fail "install.sh --service kube-ovn must succeed on a reinstall (${regen})"
        if [[ "$regen" == "default" ]]; then
            assert_not_contains "$(cat "$kubectl_log")" "create secret" "a reinstall must keep the existing kube-ovn-tls"
            assert_contains "$(cat "${tmp_root}/install.out")" "Secret kube-system/kube-ovn-tls already exists" \
                "a reinstall must report the existing kube-ovn-tls"
        else
            assert_contains "$(cat "$kubectl_log")" "create secret generic kube-ovn-tls" \
                "regenerate_certs (service-configs or KUBE_OVN_REGENERATE_CERTS) must replace the existing kube-ovn-tls"
            assert_not_contains "$(cat "$kubectl_log")" "delete secret" "regeneration must not delete the secret"
        fi
    done
        # The TLS action can stop the install: when kubectl cannot say whether the
    # secret exists, install.sh must fail and must not run Helm.
    : > "$kubectl_log"
    : > "$helm_log"
    rm -f "${tmp_overrides}/service-configs/kube-ovn.yaml"
    rc=0
    PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        KUBECTL_LOG_FILE="$kubectl_log" \
        KUBECTL_CAPTURE_DIR="${tmp_root}/capture" \
        KUBECTL_SECRET_GET_ERROR=1 \
        HELM_LOG_FILE="$helm_log" \
        GENESTACK_BASE_DIR="$tmp_base" \
        GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
        GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "${REPO_ROOT}/bin/install.sh" --service kube-ovn --dry-run >"${tmp_root}/install.out" 2>&1 || rc=$?
    [[ "$rc" -ne 0 ]] || fail "install.sh --service kube-ovn must fail when the secret lookup fails"
    assert_contains "$(cat "${tmp_root}/install.out")" "Cannot tell whether kube-system/kube-ovn-tls exists" \
        "the lookup failure must be reported"
    assert_contains "$(cat "${tmp_root}/install.out")" "not running Helm" "the install must say Helm was not run"
    assert_not_contains "$(cat "$helm_log")" "upgrade --install" "Helm must not run after a failed TLS hook"
    assert_not_contains "$(cat "$kubectl_log")" "create secret" "nothing may be created after a failed lookup"
    rm -rf "$tmp_root" "$fakebin"
}

# Runs install.sh for a service with a deliberately broken pre-install hook and
# checks that it fails, says why, and never reaches Helm.
#   $1 service, $2 text the output must contain, $3 file (relative to the base
#   directory) to delete first, or "" for none; the rest are env assignments.
run_install_expect_hook_failure() {
    local svc="$1" expect="$2" break_file="$3"
    shift 3
    local fakebin tmp_root tmp_base tmp_overrides helm_log out rc=0
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    tmp_base="${tmp_root}/base"
    tmp_overrides="${tmp_root}/overrides"
    helm_log="${tmp_root}/helm.log"
    mkdir -p "${tmp_base}/base-helm-configs" "${tmp_base}/base-kustomize" "${tmp_overrides}/kustomize"
    cp -R "${REPO_ROOT}/base-helm-configs/${svc}" "${tmp_base}/base-helm-configs/"
    [[ ! -d "${REPO_ROOT}/base-kustomize/${svc}" ]] || cp -R "${REPO_ROOT}/base-kustomize/${svc}" "${tmp_base}/base-kustomize/"
    printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
    chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
    printf 'charts:\n  %s: 1.0.0\n' "$svc" > "${tmp_overrides}/helm-chart-versions.yaml"
    [[ -z "$break_file" ]] || rm -f "${tmp_base}/${break_file}"
    : > "$helm_log"

    out="$(env PATH="${fakebin}:$PATH" \
        KUBECTL_BIN=kubectl \
        HELM_LOG_FILE="$helm_log" \
        GENESTACK_BASE_DIR="$tmp_base" \
        GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
        GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
        GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
        "$@" \
        "${REPO_ROOT}/bin/install.sh" --service "$svc" --dry-run 2>&1)" || rc=$?
    [[ "$rc" -ne 0 ]] || fail "install.sh --service ${svc} must fail (${expect})"
    assert_contains "$out" "$expect" "install.sh --service ${svc} must report: ${expect}"
    assert_contains "$out" "not running Helm" "install.sh --service ${svc} must say Helm was not run"
    assert_not_contains "$(cat "$helm_log")" "upgrade --install" "install.sh --service ${svc} must not run Helm after a failed hook"
    rm -rf "$tmp_root" "$fakebin"
}

# Any failing pre_install_actions or pre_install_check_actions entry stops the
# install before Helm runs.
test_install_hook_failures_stop_install() {
    # pre_install_actions
    run_install_expect_hook_failure mariadb-operator "is not a valid DNS domain" "" CLUSTER_NAME="bad domain"
    run_install_expect_hook_failure redis-operator "is not a valid DNS domain" "" CLUSTER_NAME="bad;domain"
    run_install_expect_hook_failure kube-ovn "No nodes found labeled" "" KUBECTL_NO_NODES=1
    run_install_expect_hook_failure kube-ovn "must be true or false" "" KUBE_OVN_REGENERATE_CERTS=maybe

    # pre_install_check_actions
    local svc
    run_install_expect_hook_failure nova "Cannot read the kube-system/ovn-central deployment" "" KUBECTL_DEPLOY_GET_ERROR=1
    for svc in neutron octavia; do
        run_install_expect_hook_failure "$svc" "must contain cacert, cert, and key" "" KUBECTL_SECRET_JSON_EMPTY=1 KUBECTL_ENABLE_SSL=true
        run_install_expect_hook_failure "$svc" "Pre-install checks for '${svc}' failed" "" KUBECTL_SECRET_JSON_EMPTY=1 KUBECTL_ENABLE_SSL=true
        run_install_expect_hook_failure "$svc" "Kube-OVN TLS values file not found" \
            "base-helm-configs/${svc}/ssl/${svc}-ovn-tls-overrides.yaml" KUBECTL_ENABLE_SSL=true
        run_install_expect_hook_failure "$svc" "Cannot read the kube-system/ovn-central deployment" "" KUBECTL_DEPLOY_GET_ERROR=1
        run_install_expect_hook_failure "$svc" "ovn-nb and ovn-sb services could not be resolved" "" KUBECTL_NO_OVN_SERVICES=1
        run_install_expect_hook_failure "$svc" "Kube-OVN uses SSL but kube-system/kube-ovn-tls was not found" "" \
            KUBECTL_ENABLE_SSL=true MISSING_SECRET_REFS=kube-system/kube-ovn-tls
    done
}

# secret_sync_directory mirrors the old install-keystone.sh: with the federation
# base in the Keystone overlay it syncs the Shibboleth directory into
# keystone-shibd-etc, and it stops the install when files are missing.
test_secret_sync_directory() (
    local fakebin tmp_root svc_yaml log output rc name overlay shib other
    local GENESTACK_OVERRIDES_DIR GENESTACK_BASE_DIR
    # shellcheck source=../bin/helpers.sh
    source "${REPO_ROOT}/bin/helpers.sh"
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    GENESTACK_OVERRIDES_DIR="${tmp_root}/etc"
    GENESTACK_BASE_DIR="$REPO_ROOT"
    # Earlier tests leave extra Helm arguments (such as --dry-run) behind.
    CL_EXTRA_HELM_ARGS=()
    log="${tmp_root}/kubectl.log"
    overlay="${GENESTACK_OVERRIDES_DIR}/kustomize/keystone/overlay"
    shib="${GENESTACK_OVERRIDES_DIR}/keystone-sp/shibboleth"
    other="${tmp_root}/other-shibboleth"
    mkdir -p "$overlay" "$shib" "$other"
    PATH="${fakebin}:$PATH"
    export PATH KUBECTL_BIN=kubectl KUBECTL_LOG_FILE="$log"
    svc_yaml="$(yq e '{"service": .service, "pre_install_actions": .pre_install_actions}' "${REPO_ROOT}/bin/services/keystone.yaml")"
    [[ "$(yq e '.pre_install_actions[0].type' - <<< "$svc_yaml")" == "secret_sync_directory" ]] ||
        fail "keystone.yaml must carry the secret_sync_directory action"

    # No federation base in the overlay: nothing is synced, even without files.
    printf 'kind: Kustomization\nresources:\n  - ../base\n' > "${overlay}/kustomization.yaml"
    : > "$log"
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" ||
        fail "the action must succeed without the federation base"
    assert_contains "$output" "does not include 'federation'" "the skip must be reported"
    assert_not_contains "$(cat "$log")" "create secret" "no secret may be synced without federation"

    # Federation base but no directory: the install stops.
    printf 'kind: Kustomization\nresources:\n  - ../federation\n' > "${overlay}/kustomization.yaml"
    rm -rf "$shib"
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a missing Shibboleth directory must fail"
    assert_contains "$output" "Directory for secret openstack/keystone-shibd-etc not found" "the missing directory must be reported"

    # Directory without the required files: each missing file is listed.
    mkdir -p "$shib"
    printf 'x' > "${shib}/shibboleth2.xml"
    printf 'x' > "${shib}/sp-cert.pem"
    rc=0
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" || rc=$?
    assert_eq "1" "$rc" "missing required files must fail"
    assert_contains "$output" "  - sp-key.pem" "sp-key.pem must be listed as missing"
    assert_contains "$output" "  - idp-metadata.xml" "idp-metadata.xml must be listed as missing"
    assert_not_contains "$output" "  - shibboleth2.xml" "a present file must not be listed"
    assert_not_contains "$(cat "$log")" "create secret" "nothing may be synced when files are missing"

    # Everything present: the directory is synced on every run.
    printf 'x' > "${shib}/sp-key.pem"
    printf 'x' > "${shib}/idp-metadata.xml"
    for name in first second; do
        : > "$log"
        output="$(run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" ||
            fail "the action must succeed with all files present (${name} run)"
        assert_contains "$output" "Syncing secret openstack/keystone-shibd-etc from ${shib}" "the sync must be announced (${name} run)"
        assert_contains "$(cat "$log")" "create secret generic keystone-shibd-etc --namespace openstack --from-file=${shib}" \
            "the directory must be synced into keystone-shibd-etc (${name} run)"
        assert_contains "$(cat "$log")" "apply --namespace openstack" "the secret must be applied (${name} run)"
    done

    # KEYSTONE_SHIBBOLETH_DIR replaces the directory.
    for name in shibboleth2.xml sp-cert.pem sp-key.pem idp-metadata.xml; do printf 'y' > "${other}/${name}"; done
    : > "$log"
    output="$(KEYSTONE_SHIBBOLETH_DIR="$other" run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" ||
        fail "the action must succeed with KEYSTONE_SHIBBOLETH_DIR"
    assert_contains "$(cat "$log")" "--from-file=${other}" "KEYSTONE_SHIBBOLETH_DIR must replace the directory"

    # SKIP_SHIBBOLETH_SECRET=1 and --dry-run skip the sync.
    : > "$log"
    output="$(SKIP_SHIBBOLETH_SECRET=1 run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" ||
        fail "the action must succeed with SKIP_SHIBBOLETH_SECRET=1"
    assert_contains "$output" "SKIP_SHIBBOLETH_SECRET=1 is set" "the skip must be reported"
    CL_EXTRA_HELM_ARGS=(--dry-run)
    output="$(run_service_actions "$svc_yaml" '.pre_install_actions' keystone 2>&1)" ||
        fail "the action must succeed with --dry-run"
    assert_contains "$output" "--dry-run is set" "the --dry-run skip must be reported"
    CL_EXTRA_HELM_ARGS=()
    assert_not_contains "$(cat "$log")" "create secret" "a skipped sync must not touch the secret"

    # Bad configuration is rejected.
    rc=0
    output="$(run_service_actions "$(yq e '.pre_install_actions[0].directory = "../etc"' - <<< "$svc_yaml")" '.pre_install_actions' keystone 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a directory outside the overrides directory must be rejected"
    rc=0
    output="$(run_service_actions "$(yq e 'del(.pre_install_actions[0].secret_name)' - <<< "$svc_yaml")" '.pre_install_actions' keystone 2>&1)" || rc=$?
    assert_eq "1" "$rc" "a missing secret_name must be rejected"
    rm -rf "$tmp_root" "$fakebin"
)

# install.sh --service keystone syncs the Shibboleth secret before Helm when the
# overlay includes the federation base, and stops before Helm when it cannot.
test_install_keystone_shibboleth_secret() {
    local fakebin tmp_root tmp_base tmp_overrides helm_log kubectl_log overlay shib mode rc out name
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    for mode in plain federation federation-missing skip; do
        tmp_root="$(mktemp -d)"
        tmp_base="${tmp_root}/base"
        tmp_overrides="${tmp_root}/overrides"
        helm_log="${tmp_root}/helm.log"
        kubectl_log="${tmp_root}/kubectl.log"
        overlay="${tmp_overrides}/kustomize/keystone/overlay"
        shib="${tmp_overrides}/keystone-sp/shibboleth"
        mkdir -p "${tmp_base}/base-helm-configs" "${tmp_base}/base-kustomize" "$overlay" "$shib"
        cp -R "${REPO_ROOT}/base-helm-configs/keystone" "${tmp_base}/base-helm-configs/"
        printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
        chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
        printf 'charts:\n  keystone: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"
        : > "$helm_log"
        : > "$kubectl_log"
        if [[ "$mode" == plain ]]; then
            printf 'kind: Kustomization\nresources:\n  - ../base\n' > "${overlay}/kustomization.yaml"
        else
            printf 'kind: Kustomization\nresources:\n  - ../federation\n' > "${overlay}/kustomization.yaml"
        fi
        if [[ "$mode" != federation-missing ]]; then
            for name in shibboleth2.xml sp-cert.pem sp-key.pem idp-metadata.xml; do printf 'x' > "${shib}/${name}"; done
        fi
        rc=0
        out="$(env PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_LOG_FILE="$kubectl_log" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            SKIP_SHIBBOLETH_SECRET="$([[ "$mode" == skip ]] && echo 1 || true)" \
            "${REPO_ROOT}/bin/install.sh" --service keystone 2>&1)" || rc=$?
        case "$mode" in
            plain|skip)
                assert_eq "0" "$rc" "keystone install must succeed (${mode})"
                assert_not_contains "$(cat "$kubectl_log")" "create secret generic keystone-shibd-etc" \
                    "keystone-shibd-etc must not be synced (${mode})"
                grep -q '^upgrade --install keystone ' "$helm_log" || fail "Helm must run for keystone (${mode})"
                ;;
            federation)
                assert_eq "0" "$rc" "keystone install must succeed (federation)"
                assert_contains "$(cat "$kubectl_log")" "create secret generic keystone-shibd-etc --namespace openstack --from-file=${shib}" \
                    "keystone-shibd-etc must be synced from the Shibboleth directory"
                grep -q '^upgrade --install keystone ' "$helm_log" || fail "Helm must run for keystone (federation)"
                ;;
            federation-missing)
                [[ "$rc" -ne 0 ]] || fail "keystone install must fail when Shibboleth files are missing"
                assert_contains "$out" "these required files are missing" "the missing files must be reported"
                assert_contains "$out" "not running Helm" "the install must say Helm was not run"
                assert_not_contains "$(cat "$helm_log")" "upgrade --install" "Helm must not run without the Shibboleth files"
                ;;
        esac
        rm -rf "$tmp_root"
    done
    rm -rf "$fakebin"
}

# barbican_simple_crypto_kek is a port of the kek handling in the old
# install-barbican.sh. These tests run its cases against an in-memory secret
# store: a new install generates a kek, an existing deployment adopts the kek it
# already runs, a staged rotation is allowed and an impossible rewrap is refused.
test_barbican_simple_crypto_kek() (
    local fakebin tmp_root store etc svc_yaml log rc output kek_a kek_b kek_c well_known conf
    local GENESTACK_OVERRIDES_DIR GENESTACK_BASE_DIR
    # shellcheck source=../bin/helpers.sh
    source "${REPO_ROOT}/bin/helpers.sh"
    # shellcheck source=../bin/lib/barbican.sh
    source "${REPO_ROOT}/bin/lib/barbican.sh"
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    store="${tmp_root}/store"
    etc="${tmp_root}/etc"
    log="${tmp_root}/kubectl.log"
    GENESTACK_OVERRIDES_DIR="$etc"
    GENESTACK_BASE_DIR="$REPO_ROOT"
    mkdir -p "$store" "${etc}/helm-configs/barbican"
    CL_EXTRA_HELM_ARGS=()
    PATH="${fakebin}:$PATH"
    export PATH KUBECTL_BIN=kubectl KUBECTL_LOG_FILE="$log" KUBECTL_SECRET_DIR="$store"
    # Only the kek action: the SoftHSM actions have their own test.
    svc_yaml="$(yq e '{"service": .service, "chart": .chart, "pre_install_actions": [.pre_install_actions[] | select(.type == "barbican_simple_crypto_kek")]}' "${REPO_ROOT}/bin/services/barbican.yaml")"
    [[ "$(yq e '.pre_install_actions[0].type' - <<< "$svc_yaml")" == "barbican_simple_crypto_kek" ]] ||
        fail "barbican.yaml must carry the barbican_simple_crypto_kek action"

    new_key() { head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_'; }
    put() { mkdir -p "${store}/$1/$2"; printf '%s' "$4" > "${store}/$1/$2/$3"; }
    get() { cat "${store}/$1/$2/$3" 2>/dev/null || true; }
    reset() { rm -rf "$store"; mkdir -p "$store"; rm -f "${etc}/helm-configs/barbican/"*.yaml; }
    run_kek() {
        helm_set_args=()
        : > "$log"
        rc=0
        run_service_actions "$svc_yaml" '.pre_install_actions' barbican >"${tmp_root}/out" 2>&1 || rc=$?
        output="$(cat "${tmp_root}/out")"
    }
    conf_with() { printf '[DEFAULT]\ndebug = true\n[simple_crypto_plugin]\nplugin_name = Software Only Crypto\nkek = %s\n[other]\nkek = not-this-one\n' "$1"; }

    kek_a="$(new_key)"; kek_b="$(new_key)"; kek_c="$(new_key)"
    well_known="$(barbican_kek_well_known)"
    [[ "$well_known" != "$kek_a" ]] || fail "test keys must differ from the default"
    assert_eq "44" "${#well_known}" "the well-known default must be a 44-char key"

    # Case 4: new install. A random kek is generated, stored and injected.
    reset
    run_kek
    assert_eq "0" "$rc" "a new install must succeed"
    assert_contains "$output" "generating a fresh kek" "a new install must say it generates a kek"
    kek_new="$(get openstack barbican-simple-crypto-kek kek)"
    barbican_kek_format_ok "$kek_new" || fail "the generated kek must be a valid Fernet key"
    assert_eq "" "$(get openstack barbican-simple-crypto-kek old_keks)" "a new install has no old keks"
    assert_eq "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_new}" "${helm_set_args[*]}" \
        "the generated kek must be injected as the only argument"
    assert_not_contains "$(cat "$log")" "$kek_new" "the kek must never appear on a kubectl command line"
    assert_contains "$(cat "$log")" "apply -f -" "the secret must be written over stdin"

    # Rerun after the release exists: nothing is rewrapped and nothing is rewritten.
    put openstack barbican-etc barbican.conf "$(conf_with "$kek_new")"
    run_kek
    assert_eq "0" "$rc" "a rerun must succeed"
    assert_contains "$output" "Secret kek matches the deployed kek" "a rerun must find the kek unchanged"
    assert_eq "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_new}" "${helm_set_args[*]}" "a rerun must inject the same kek"
    assert_not_contains "$(cat "$log")" "apply" "a rerun must not rewrite the secret"
    assert_eq "$kek_new" "$(get openstack barbican-simple-crypto-kek kek)" "a rerun must keep the stored kek"

    # Case 3: an existing deployment without the secret adopts the kek it runs.
    reset
    put openstack barbican-etc barbican.conf "$(conf_with "$kek_a")"
    run_kek
    assert_eq "0" "$rc" "adopting the deployed kek must succeed"
    assert_contains "$output" "adopting the deployed simple_crypto kek" "the adoption must be announced"
    assert_eq "$kek_a" "$(get openstack barbican-simple-crypto-kek kek)" "the deployed kek must be stored"
    assert_eq "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_a}" "${helm_set_args[*]}" "the adopted kek must be injected"
    assert_not_contains "$output" "generating a fresh kek" "an existing deployment must never get a random kek"

    # Case 3, pre-Gazpacho: no kek line means the upstream default, adopted with a warning.
    reset
    put openstack barbican-etc barbican.conf "$(printf '[DEFAULT]\ndebug = true\n[simple_crypto_plugin]\nplugin_name = Software Only Crypto\n')"
    run_kek
    assert_eq "0" "$rc" "adopting the implicit default kek must succeed"
    assert_contains "$output" "WELL-KNOWN DEFAULT SIMPLE_CRYPTO KEK" "the default kek must be flagged loudly"
    assert_eq "$well_known" "$(get openstack barbican-simple-crypto-kek kek)" "the implicit default must be adopted, not replaced"

    # Case 3 with an unusable deployed kek: refuse, write nothing.
    reset
    put openstack barbican-etc barbican.conf "$(conf_with "too-short")"
    run_kek
    assert_eq "1" "$rc" "an invalid deployed kek must stop the install"
    assert_contains "$output" "refusing to replace it with a random value" "the refusal must be explained"
    [[ ! -d "${store}/openstack/barbican-simple-crypto-kek" ]] || fail "nothing may be written for an invalid deployed kek"

    # barbican-etc exists but barbican.conf is unreadable: never guess "new install".
    reset
    put openstack barbican-etc other.conf "x"
    run_kek
    assert_eq "1" "$rc" "an unreadable barbican.conf must stop the install"
    assert_contains "$output" "barbican.conf could not be read" "the unreadable conf must be reported"
    [[ ! -d "${store}/openstack/barbican-simple-crypto-kek" ]] || fail "no kek may be generated over an unreadable deployment"

    # Case 1: a kek in a values file is deployed as is.
    reset
    printf 'conf:\n  barbican:\n    simple_crypto_plugin:\n      kek: %s\n' "$kek_a" > "${etc}/helm-configs/barbican/barbican-helm-overrides.yaml"
    put openstack barbican-simple-crypto-kek kek "$kek_b"
    run_kek
    assert_eq "0" "$rc" "an override kek must succeed"
    assert_contains "$output" "deploying it as is" "the override must be announced"
    assert_contains "$output" "NOTICE: barbican-simple-crypto-kek exists but is ignored" "the ignored secret must be noted"
    assert_eq "0" "${#helm_set_args[@]}" "an override kek must inject nothing"
    assert_not_contains "$(cat "$log")" "apply" "an override kek must write no secret"
    printf 'conf:\n  barbican:\n    simple_crypto_plugin:\n      kek: %s\n' "$well_known" > "${etc}/helm-configs/barbican/barbican-helm-overrides.yaml"
    run_kek
    assert_contains "$output" "WELL-KNOWN DEFAULT SIMPLE_CRYPTO KEK" "an override with the default kek must be flagged"

    # Case 2: the secret is not a Fernet key.
    reset
    put openstack barbican-simple-crypto-kek kek "not-a-fernet-key"
    run_kek
    assert_eq "1" "$rc" "an invalid secret kek must stop the install"
    assert_contains "$output" "not a 44-char Fernet key" "the invalid kek must be reported"
    assert_eq "0" "${#helm_set_args[@]}" "an invalid kek must not be injected"

    # Case 2: a secret holding the default kek is flagged.
    reset
    put openstack barbican-simple-crypto-kek kek "$well_known"
    run_kek
    assert_eq "0" "$rc" "the default kek in the secret must still deploy"
    assert_contains "$output" "WELL-KNOWN DEFAULT SIMPLE_CRYPTO KEK" "the default kek in the secret must be flagged"

    # Guard: a staged rotation. The deployed kek is in old_keks, so the rewrap can succeed.
    reset
    put openstack barbican-simple-crypto-kek kek "$kek_b"
    put openstack barbican-simple-crypto-kek old_keks "${kek_a},${kek_c}"
    put openstack barbican-etc barbican.conf "$(conf_with "$kek_a")"
    run_kek
    assert_eq "0" "$rc" "a staged rotation must succeed"
    assert_contains "$output" "ONE-WAY rewrap" "a staged rotation must warn about the rewrap"
    assert_contains "$output" "Back up the barbican DB first" "a staged rotation must say to back up the database"
    assert_eq "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_b} --set-string conf.simple_crypto_kek_rewrap.old_kek=${kek_a}\\,${kek_c}" \
        "${helm_set_args[*]}" "a staged rotation must inject the kek and the comma-escaped history"
    assert_not_contains "$(cat "$log")" "apply" "a staged rotation must not rewrite the secret"

    # Guard: the deployed kek is not in old_keks, so the rewrap could not succeed.
    reset
    put openstack barbican-simple-crypto-kek kek "$kek_b"
    put openstack barbican-simple-crypto-kek old_keks "$kek_c"
    put openstack barbican-etc barbican.conf "$(conf_with "$kek_a")"
    run_kek
    assert_eq "1" "$rc" "an impossible rewrap must stop the install"
    assert_contains "$output" "the db-sync rewrap could not unwrap the existing project" "the refusal must be explained"
    assert_contains "$output" "rotate-barbican-kek.py --stage" "the refusal must point at the rotation tool"
    assert_eq "0" "${#helm_set_args[@]}" "nothing may be injected when the rewrap is impossible"

    # Guard: no release yet.
    reset
    put openstack barbican-simple-crypto-kek kek "$kek_b"
    run_kek
    assert_eq "0" "$rc" "a secret without a release must deploy"
    assert_contains "$output" "no barbican release yet" "the missing release must be reported"

    # kubectl cannot answer: never act on a guess. Each lookup is broken on its own,
    # because either one alone must stop the install.
    reset
    put openstack barbican-simple-crypto-kek kek "$kek_a"
    export KUBECTL_STORE_API_ERROR=barbican-simple-crypto-kek
    run_kek
    unset KUBECTL_STORE_API_ERROR
    assert_eq "1" "$rc" "an API error on the kek secret must stop the install"
    assert_contains "$output" "Cannot tell whether openstack/barbican-simple-crypto-kek exists" "the API error must be reported"
    assert_not_contains "$(cat "$log")" "apply" "nothing may be written after an API error"
    assert_eq "$kek_a" "$(get openstack barbican-simple-crypto-kek kek)" "the stored kek must be untouched"
    reset
    put openstack barbican-etc barbican.conf "$(conf_with "$kek_a")"
    export KUBECTL_STORE_API_ERROR=barbican-etc
    run_kek
    unset KUBECTL_STORE_API_ERROR
    assert_eq "1" "$rc" "an API error on barbican-etc must stop the install"
    assert_contains "$output" "Cannot tell whether openstack/barbican-etc exists" "the barbican-etc API error must be reported"
    assert_not_contains "$output" "generating a fresh kek" "an API error must never lead to a random kek"
    [[ ! -d "${store}/openstack/barbican-simple-crypto-kek" ]] || fail "no secret may be written after a barbican-etc API error"

    # An existing secret with no readable kek is never overwritten.
    reset
    put openstack barbican-simple-crypto-kek old_keks "$kek_a"
    run_kek
    assert_eq "1" "$rc" "a secret without a kek must stop the install"
    assert_contains "$output" "refusing to overwrite it" "the refusal must be explained"
    assert_eq "$kek_a" "$(get openstack barbican-simple-crypto-kek old_keks)" "the existing secret must be untouched"
    rm -rf "$tmp_root" "$fakebin"
)

# install.sh --service barbican injects the kek, and stops before Helm when the
# rewrap could not succeed.
test_install_barbican_kek() {
    local fakebin tmp_root tmp_base tmp_overrides store helm_log out rc mode kek_a kek_b
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    kek_a="$(head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')"
    kek_b="$(head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')"
    for mode in new brownfield rotation refused; do
        tmp_root="$(mktemp -d)"
        tmp_base="${tmp_root}/base"
        tmp_overrides="${tmp_root}/overrides"
        store="${tmp_root}/store"
        helm_log="${tmp_root}/helm.log"
        mkdir -p "${tmp_base}/base-helm-configs" "${tmp_base}/base-kustomize" "${tmp_overrides}/kustomize" "$store"
        cp -R "${REPO_ROOT}/base-helm-configs/barbican" "${tmp_base}/base-helm-configs/"
        # SoftHSM key initialization has its own test; here it only has to succeed.
        mkdir -p "${tmp_base}/scripts/lib"
        printf 'initBarbicanHSMKeys() { return 0; }\n' > "${tmp_base}/scripts/lib/hyperconverged-common.sh"
        printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
        chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
        printf 'charts:\n  barbican: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"
        : > "$helm_log"
        case "$mode" in
            brownfield)
                mkdir -p "${store}/openstack/barbican-etc"
                printf '[simple_crypto_plugin]\nkek = %s\n' "$kek_a" > "${store}/openstack/barbican-etc/barbican.conf"
                ;;
            rotation|refused)
                mkdir -p "${store}/openstack/barbican-etc" "${store}/openstack/barbican-simple-crypto-kek"
                printf '[simple_crypto_plugin]\nkek = %s\n' "$kek_a" > "${store}/openstack/barbican-etc/barbican.conf"
                printf '%s' "$kek_b" > "${store}/openstack/barbican-simple-crypto-kek/kek"
                if [[ "$mode" == rotation ]]; then
                    printf '%s' "$kek_a" > "${store}/openstack/barbican-simple-crypto-kek/old_keks"
                else
                    printf '' > "${store}/openstack/barbican-simple-crypto-kek/old_keks"
                fi
                ;;
        esac
        rc=0
        out="$(env PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_SECRET_DIR="$store" \
            HELM_LOG_FILE="$helm_log" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service barbican 2>&1)" || rc=$?
        case "$mode" in
            new)
                assert_eq "0" "$rc" "a new barbican install must succeed"
                assert_contains "$(cat "$helm_log")" "--set-string conf.barbican.simple_crypto_plugin.kek=$(cat "${store}/openstack/barbican-simple-crypto-kek/kek")" \
                    "Helm must receive the generated kek"
                assert_not_contains "$(cat "$helm_log")" "old_kek" "a new install has no old_kek"
                ;;
            brownfield)
                assert_eq "0" "$rc" "a brownfield barbican install must succeed"
                assert_contains "$(cat "$helm_log")" "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_a}" \
                    "Helm must receive the kek the deployment already runs"
                ;;
            rotation)
                assert_eq "0" "$rc" "a staged rotation must succeed"
                assert_contains "$(cat "$helm_log")" "--set-string conf.barbican.simple_crypto_plugin.kek=${kek_b}" "Helm must receive the new kek"
                assert_contains "$(cat "$helm_log")" "--set-string conf.simple_crypto_kek_rewrap.old_kek=${kek_a}" "Helm must receive the old kek"
                ;;
            refused)
                [[ "$rc" -ne 0 ]] || fail "an impossible rewrap must stop the barbican install"
                assert_contains "$out" "Pre-install hook for 'barbican' failed; not running Helm." "the stop must be reported"
                assert_not_contains "$(cat "$helm_log")" "upgrade --install" "Helm must not run when the rewrap could not succeed"
                ;;
        esac
        rm -rf "$tmp_root"
    done
    rm -rf "$fakebin"
}

# barbican_hsm_setup and barbican_hsm_init are a port of the SoftHSM handling in
# the old install-barbican.sh: the PIN secret is created once and never changed,
# the PIN is injected whenever the secret holds one, the lab overlay is generated
# only when no site file exists, and the keys are initialized after Helm.
test_barbican_hsm() (
    local fakebin tmp_root store etc base svc_yaml log rc output pin_a pin_b site
    local GENESTACK_OVERRIDES_DIR GENESTACK_BASE_DIR
    # shellcheck source=../bin/helpers.sh
    source "${REPO_ROOT}/bin/helpers.sh"
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    tmp_root="$(mktemp -d)"
    store="${tmp_root}/store"
    etc="${tmp_root}/etc"
    base="${tmp_root}/base"
    log="${tmp_root}/kubectl.log"
    site="${etc}/helm-configs/barbican/barbican-helm-overrides.yaml"
    GENESTACK_OVERRIDES_DIR="$etc"
    GENESTACK_BASE_DIR="$base"
    mkdir -p "$store" "${etc}/helm-configs/barbican" "${base}/base-helm-configs" "${base}/scripts/lib"
    cp -R "${REPO_ROOT}/base-helm-configs/barbican" "${base}/base-helm-configs/"
    # Stand-in for the lab library: record the calls, fail on request.
    cat > "${base}/scripts/lib/hyperconverged-common.sh" <<'EOS'
writeServiceHelmOverrides() { printf 'overlay %s\n' "$1" >> "${HSM_CALL_LOG}"; mkdir -p "$1/barbican"; : > "$1/barbican/barbican-helm-overrides.yaml"; }
initBarbicanHSMKeys() { printf 'init\n' >> "${HSM_CALL_LOG}"; [[ "${HSM_INIT_FAIL:-0}" != "1" ]]; }
EOS
    export HSM_CALL_LOG="${tmp_root}/hsm-calls.log"
    CL_EXTRA_HELM_ARGS=()
    PATH="${fakebin}:$PATH"
    export PATH KUBECTL_BIN=kubectl KUBECTL_LOG_FILE="$log" KUBECTL_SECRET_DIR="$store"
    svc_yaml="$(yq e '{"service": .service, "chart": .chart, "pre_install_actions": .pre_install_actions, "post_install_actions": .post_install_actions}' "${REPO_ROOT}/bin/services/barbican.yaml")"
    [[ "$(yq e '.pre_install_actions[0].type' - <<< "$svc_yaml")" == "barbican_hsm_setup" ]] ||
        fail "barbican.yaml must run barbican_hsm_setup first, as the old script did"
    [[ "$(yq e '.post_install_actions[0].type' - <<< "$svc_yaml")" == "barbican_hsm_init" ]] ||
        fail "barbican.yaml must carry the barbican_hsm_init post-install action"
    assert_eq "true" "$(yq e '.post_install_fatal' "${REPO_ROOT}/bin/services/barbican.yaml")" \
        "barbican.yaml must fail the install when the SoftHSM initialization fails"

    put() { mkdir -p "${store}/$1/$2"; printf '%s' "$4" > "${store}/$1/$2/$3"; }
    get() { cat "${store}/$1/$2/$3" 2>/dev/null || true; }
    reset() {
        rm -rf "$store" "${etc}/helm-configs" "$HSM_CALL_LOG"
        mkdir -p "$store" "${etc}/helm-configs/barbican"
        unset BARBICAN_HSM_ENABLED HYPERCONVERGED_BARBICAN_HSM GENESTACK_BARBICAN_SOFTHSM_P11 HSM_INIT_FAIL
    }
    run_setup() {
        helm_set_args=()
        : > "$log"
        rc=0
        run_service_action "$svc_yaml" '.pre_install_actions' 0 barbican >"${tmp_root}/out" 2>&1 || rc=$?
        output="$(cat "${tmp_root}/out")"
    }
    run_init() {
        : > "$log"
        rc=0
        run_service_action "$svc_yaml" '.post_install_actions' 0 barbican >"${tmp_root}/out" 2>&1 || rc=$?
        output="$(cat "${tmp_root}/out")"
    }
    pin_a="pinAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1"
    pin_b="pinBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB2"

    # p11 is on through the base values: a missing PIN secret is created once and injected.
    reset
    run_setup
    assert_eq "0" "$rc" "a new SoftHSM setup must succeed"
    assert_contains "$output" "Creating barbican-hsm-credentials" "a missing PIN secret must be created"
    assert_contains "$(cat "$log")" "create secret generic barbican-hsm-credentials --namespace openstack --from-literal=pin=" \
        "the PIN secret must be created with a pin"
    pin_new="$(get openstack barbican-hsm-credentials pin)"
    assert_eq "32" "${#pin_new}" "the generated PIN must be 32 characters"
    assert_eq "--set conf.barbican.p11_crypto_plugin.login=${pin_new}" "${helm_set_args[*]}" "the PIN must be injected with --set"
    assert_eq "true" "$GENESTACK_BARBICAN_SOFTHSM_P11" "p11 must be reported as enabled for the post-install step"
    assert_contains "$output" "HSM credentials found - injecting p11_crypto_plugin.login" "the injection must be announced"

    # Rerun: the existing PIN is left alone and injected again.
    run_setup
    assert_eq "0" "$rc" "a rerun must succeed"
    assert_contains "$output" "already present — leaving PIN unchanged" "an existing PIN must be left alone"
    assert_not_contains "$(cat "$log")" "create secret" "an existing PIN secret must not be recreated"
    assert_eq "$pin_new" "$(get openstack barbican-hsm-credentials pin)" "an existing PIN must never change"
    assert_eq "--set conf.barbican.p11_crypto_plugin.login=${pin_new}" "${helm_set_args[*]}" "the existing PIN must be injected"

    # p11 off (values without it): nothing is created, but an existing PIN is still injected.
    rm -rf "${base}/base-helm-configs/barbican"; mkdir -p "${base}/base-helm-configs/barbican"
    printf 'conf:\n  barbican:\n    DEFAULT:\n      debug: true\n' > "${base}/base-helm-configs/barbican/barbican-helm-overrides.yaml"
    reset
    run_setup
    assert_eq "0" "$rc" "a setup without p11 must succeed"
    assert_eq "0" "${#helm_set_args[@]}" "no PIN may be injected when none exists and p11 is off"
    [[ ! -d "${store}/openstack/barbican-hsm-credentials" ]] || fail "no PIN secret may be created when p11 is off"
    assert_eq "false" "$GENESTACK_BARBICAN_SOFTHSM_P11" "p11 must be reported as off"
    put openstack barbican-hsm-credentials pin "$pin_a"
    run_setup
    assert_eq "--set conf.barbican.p11_crypto_plugin.login=${pin_a}" "${helm_set_args[*]}" "an existing PIN is injected even when p11 is off"
    # ...and the post-install step is skipped.
    run_init
    assert_eq "0" "$rc" "the init must be a no-op when p11 is off"
    [[ ! -s "$HSM_CALL_LOG" ]] || fail "SoftHSM keys must not be initialized when p11 is off"
    rm -rf "${base}/base-helm-configs/barbican"; cp -R "${REPO_ROOT}/base-helm-configs/barbican" "${base}/base-helm-configs/"

    # Lab flags: the overlay is generated only when no site file exists.
    for flag in BARBICAN_HSM_ENABLED HYPERCONVERGED_BARBICAN_HSM; do
        reset
        export "${flag}=true"
        run_setup
        assert_eq "0" "$rc" "${flag}=true must succeed"
        assert_contains "$output" "Generating SoftHSM overlay" "${flag}=true must generate the overlay when the site file is missing"
        assert_contains "$(cat "$HSM_CALL_LOG")" "overlay ${etc}/helm-configs" "the overlay must be written under helm-configs"
        rm -f "$HSM_CALL_LOG"
        printf '# existing site values\n' > "$site"
        run_setup
        [[ ! -s "$HSM_CALL_LOG" ]] || fail "${flag}=true must never regenerate an existing site file"
        assert_eq "# existing site values" "$(cat "$site")" "an existing site file must stay untouched"
    done
    reset
    run_setup
    [[ ! -s "$HSM_CALL_LOG" ]] || fail "no overlay may be generated without the lab flags"

    # kubectl cannot say whether the PIN secret exists: never act on a guess.
    reset
    put openstack barbican-hsm-credentials pin "$pin_a"
    export KUBECTL_STORE_API_ERROR=barbican-hsm-credentials
    run_setup
    unset KUBECTL_STORE_API_ERROR
    assert_eq "1" "$rc" "an API error on the PIN secret must stop the install"
    assert_contains "$output" "Cannot tell whether openstack/barbican-hsm-credentials exists" "the API error must be reported"
    assert_not_contains "$(cat "$log")" "create secret" "no PIN may be created after an API error"
    assert_eq "$pin_a" "$(get openstack barbican-hsm-credentials pin)" "the stored PIN must be untouched"

    # Post-install key initialization.
    reset
    export GENESTACK_BARBICAN_SOFTHSM_P11=true
    run_init
    assert_eq "0" "$rc" "the key initialization must succeed"
    assert_eq "init" "$(cat "$HSM_CALL_LOG")" "initBarbicanHSMKeys must run when p11 is enabled"
    rm -f "$HSM_CALL_LOG"
    export HSM_INIT_FAIL=1
    run_init
    assert_eq "1" "$rc" "a failing key initialization must fail the action"
    unset HSM_INIT_FAIL
    rm -f "$HSM_CALL_LOG"
    CL_EXTRA_HELM_ARGS=(--dry-run)
    run_init
    CL_EXTRA_HELM_ARGS=()
    assert_eq "0" "$rc" "--dry-run must skip the key initialization"
    assert_contains "$output" "--dry-run is set" "the --dry-run skip must be reported"
    [[ ! -s "$HSM_CALL_LOG" ]] || fail "SoftHSM keys must not be initialized for --dry-run"
    mv "${base}/scripts/lib/hyperconverged-common.sh" "${base}/scripts/lib/hyperconverged-common.sh.off"
    run_init
    mv "${base}/scripts/lib/hyperconverged-common.sh.off" "${base}/scripts/lib/hyperconverged-common.sh"
    assert_eq "1" "$rc" "a missing initBarbicanHSMKeys must fail the action"
    assert_contains "$output" "initBarbicanHSMKeys not found" "the missing function must be reported"
    rm -rf "$tmp_root" "$fakebin"
)

# install.sh --service barbican injects the PIN, initializes the SoftHSM keys
# after Helm, and fails when the initialization fails.
test_install_barbican_hsm() {
    local fakebin tmp_root tmp_base tmp_overrides store helm_log order_log out rc mode
    fakebin="$(mktemp -d)"
    create_fake_installer_binaries "$fakebin"
    for mode in ok init-fails helm-fails dry-run; do
        tmp_root="$(mktemp -d)"
        tmp_base="${tmp_root}/base"
        tmp_overrides="${tmp_root}/overrides"
        store="${tmp_root}/store"
        helm_log="${tmp_root}/helm.log"
        order_log="${tmp_root}/order.log"
        mkdir -p "${tmp_base}/base-helm-configs" "${tmp_base}/base-kustomize" "${tmp_base}/scripts/lib" "${tmp_overrides}/kustomize" "$store/openstack/barbican-hsm-credentials"
        cp -R "${REPO_ROOT}/base-helm-configs/barbican" "${tmp_base}/base-helm-configs/"
        printf 'existing-pin-0123456789abcdef0123' > "${store}/openstack/barbican-hsm-credentials/pin"
        mkdir -p "${store}/openstack/barbican-etc"
        printf '[simple_crypto_plugin]\nkek = %s\n' "$(head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')" > "${store}/openstack/barbican-etc/barbican.conf"
        cat > "${tmp_base}/scripts/lib/hyperconverged-common.sh" <<EOS
initBarbicanHSMKeys() {
    if grep -q '^upgrade --install' "${helm_log}"; then echo init-after-helm >> "${order_log}"; else echo init-before-helm >> "${order_log}"; fi
    [[ "\${HSM_INIT_FAIL:-0}" != "1" ]]
}
EOS
        printf '#!/bin/bash\nexit 0\n' > "${tmp_overrides}/kustomize/kustomize.sh"
        chmod +x "${tmp_overrides}/kustomize/kustomize.sh"
        printf 'charts:\n  barbican: 1.0.0\n' > "${tmp_overrides}/helm-chart-versions.yaml"
        : > "$helm_log"
        : > "$order_log"
        rc=0
        out="$(env PATH="${fakebin}:$PATH" \
            KUBECTL_BIN=kubectl \
            KUBECTL_SECRET_DIR="$store" \
            HELM_LOG_FILE="$helm_log" \
            HSM_INIT_FAIL="$([[ "$mode" == init-fails ]] && echo 1 || echo 0)" \
            HELM_FAIL_UPGRADE="$([[ "$mode" == helm-fails ]] && echo 1 || echo 0)" \
            GENESTACK_BASE_DIR="$tmp_base" \
            GENESTACK_OVERRIDES_DIR="$tmp_overrides" \
            GENESTACK_SERVICES_DIR="${REPO_ROOT}/bin/services" \
            GENESTACK_SKIP_DEFAULT_PASSWORD_SCAN=1 \
            "${REPO_ROOT}/bin/install.sh" --service barbican $([[ "$mode" == dry-run ]] && echo --dry-run) 2>&1)" || rc=$?
        case "$mode" in
            ok)
                assert_eq "0" "$rc" "barbican install must succeed"
                assert_contains "$(cat "$helm_log")" "--set conf.barbican.p11_crypto_plugin.login=existing-pin-0123456789abcdef0123" \
                    "Helm must receive the SoftHSM PIN"
                assert_eq "init-after-helm" "$(cat "$order_log")" "the SoftHSM keys must be initialized after Helm"
                ;;
            init-fails)
                [[ "$rc" -ne 0 ]] || fail "a failing SoftHSM initialization must fail the install"
                assert_contains "$out" "Post-install hook for 'barbican' failed." "the failure must be reported"
                ;;
            helm-fails)
                [[ "$rc" -ne 0 ]] || fail "a failing Helm upgrade must fail the install"
                assert_eq "" "$(cat "$order_log")" "the SoftHSM keys must not be initialized after a failed Helm upgrade"
                ;;
            dry-run)
                assert_eq "0" "$rc" "barbican --dry-run must succeed"
                assert_eq "" "$(cat "$order_log")" "the SoftHSM keys must not be initialized for --dry-run"
                ;;
        esac
        rm -rf "$tmp_root"
    done
    rm -rf "$fakebin"
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
    test_ovn_tls_values_action
    test_install_ovn_tls_values
    test_custom_post_renderer
    test_octavia_post_renderer_ssl_wiring
    test_cluster_name_site_value
    test_install_mariadb_cluster_name
    test_install_redis_operator_cluster_name
    test_kube_ovn_tls_secret
    test_install_kube_ovn_tls_secret
    test_install_hook_failures_stop_install
    test_secret_sync_directory
    test_install_keystone_shibboleth_secret
    test_barbican_simple_crypto_kek
    test_install_barbican_kek
    test_barbican_hsm
    test_install_barbican_hsm
    echo "PASS: unified installer regression checks"
}

main "$@"
