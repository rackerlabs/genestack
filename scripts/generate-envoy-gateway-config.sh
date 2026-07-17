#!/usr/bin/env bash
set -euo pipefail

RESOURCE="httproutes.gateway.networking.k8s.io"
OUTPUT_FILE="/etc/genestack/envoy-gateways.yaml"
ROUTES_FILE=""
GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-}"
INTERNAL_DOMAIN=""
ACME_EMAIL="${ACME_EMAIL:-}"
ACME_ENABLED=false
FORCE=false

EXTERNAL_GATEWAY="external"
INTERNAL_GATEWAY="internal"
EXTERNAL_NAMESPACE="envoy-gateway"
INTERNAL_NAMESPACE="envoy-gateway"
EXTERNAL_CLASS="external-eg"
INTERNAL_CLASS="internal-eg"
EXTERNAL_ISSUER="flex-gateway-issuer"
INTERNAL_ISSUER="flex-gateway-issuer"
ACME_ISSUER="letsencrypt-prod"
EXTERNAL_POOL="gateway-api-external"
INTERNAL_POOL="gateway-api-internal"
EXTERNAL_SECRET="wildcard-external-tls-secret"
INTERNAL_SECRET="wildcard-internal-tls-secret"
TEMP_ROUTES_JSON=""
TEMP_ROUTES_OUTPUT=""
TEMP_RENDERED_OUTPUT=""

usage() {
    cat <<EOF
Usage:
  $0 [OPTIONS]

Interactively build an Envoy Gateway config from current HTTPRoutes.

Options:
  -d, --domain DOMAIN
      Base gateway domain. If omitted, the script tries to infer it from
      existing route hostnames and then prompts for confirmation.

  -o, --output FILE
      Output config path. Default: /etc/genestack/envoy-gateways.yaml

  --routes-file FILE
      Read HTTPRoute inventory from a kubectl JSON file instead of the cluster.
      Useful for testing:
        kubectl get httproute -A -o json > httproutes.json

  --acme-email EMAIL
      Enable ACME for the external gateway and use letsencrypt-prod.

  --external-issuer NAME
      Issuer for the external gateway when ACME is not enabled.
      Default: flex-gateway-issuer

  --internal-issuer NAME
      Issuer for the internal gateway. Default: flex-gateway-issuer

  --external-pool NAME
      MetalLB pool for the external gateway. Default: gateway-api-external

  --internal-pool NAME
      MetalLB pool for the internal gateway. Default: gateway-api-internal

  --force
      Overwrite the output file without prompting.

  -h, --help
      Show this help.

For each discovered HTTPRoute, choose:
  I = internal only
  E = external only
  B = both internal and external
  S = skip
EOF
}

require_tools() {
    local missing=()

    if [ -z "${ROUTES_FILE}" ] && ! command -v kubectl >/dev/null 2>&1; then
        missing+=("kubectl")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Error: missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

prompt() {
    local message="$1"
    local default_value="${2:-}"
    local response

    if [ -n "${default_value}" ]; then
        read -r -p "${message} [${default_value}]: " response </dev/tty
        echo "${response:-${default_value}}"
    else
        read -r -p "${message}: " response </dev/tty
        echo "${response}"
    fi
}

prompt_yes_no() {
    local message="$1"
    local default_value="${2:-n}"
    local response default_label

    case "${default_value}" in
        y|Y|yes|YES)
            default_label="Y/n"
            default_value="y"
            ;;
        *)
            default_label="y/N"
            default_value="n"
            ;;
    esac

    while true; do
        read -r -p "${message} [${default_label}]: " response </dev/tty
        response="${response:-${default_value}}"
        case "${response}" in
            y|Y|yes|YES)
                return 0
                ;;
            n|N|no|NO)
                return 1
                ;;
            *)
                echo "Please answer y or n." >&2
                ;;
        esac
    done
}

yaml_quote() {
    jq -Rn --arg value "$1" '$value'
}

route_key_from_name() {
    local route_name="$1"

    route_name="${route_name%-external}"
    route_name="${route_name%-internal}"

    case "${route_name}" in
        internal-loki-gateway-route)
            echo "loki"
            return
            ;;
        custom-*-gateway-route)
            route_name="${route_name#custom-}"
            echo "${route_name%-gateway-route}"
            return
            ;;
        custom-*-gateway-routes)
            route_name="${route_name#custom-}"
            echo "${route_name%-gateway-routes}"
            return
            ;;
        custom-*-routes)
            route_name="${route_name#custom-}"
            echo "${route_name%-routes}"
            return
            ;;
        *-gateway-route)
            echo "${route_name%-gateway-route}"
            return
            ;;
    esac

    echo "${route_name}"
}

sanitize_route_key() {
    local route_key="$1"

    route_key=$(tr '[:upper:]' '[:lower:]' <<< "${route_key}")
    route_key=$(sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//' <<< "${route_key}")

    if [ -z "${route_key}" ]; then
        route_key="route"
    fi

    echo "${route_key}"
}

first_backend_json() {
    local route_json="$1"

    jq -c '
        [.spec.rules[]?.backendRefs[]? | select((.kind // "Service") == "Service")][0] // {}
    ' <<< "${route_json}"
}

route_has_backend() {
    local route_json="$1"

    jq -e '
        any(.spec.rules[]?.backendRefs[]?; (.kind // "Service") == "Service")
    ' <<< "${route_json}" >/dev/null
}

route_metadata_json() {
    jq -c '
        {
            name: .metadata.name,
            namespace: .metadata.namespace,
            hostnames: (.spec.hostnames // []),
            parents: [.spec.parentRefs[]? | ((.namespace // "") + "/" + .name + ":" + (.sectionName // ""))],
            sections: [.spec.parentRefs[]?.sectionName?],
            backends: [.spec.rules[]?.backendRefs[]? | select((.kind // "Service") == "Service") | ((.namespace // "") + "/" + .name + ":" + ((.port // "") | tostring))]
        }
    '
}

infer_domain() {
    local routes_json="$1"

    jq -r '
        .items[]?.spec.hostnames[]? // empty
    ' "${routes_json}" |
        sed 's/^"//; s/"$//; s/^\*\.//' |
        awk -F. '
            NF >= 3 && $0 !~ /(^|[.])cluster[.]local$/ && $0 !~ /[.]svc[.]cluster[.]local$/ {
                suffix = $2
                for (i = 3; i <= NF; i++) {
                    suffix = suffix "." $i
                }
                count[suffix]++
            }
            END {
                for (suffix in count) {
                    if (count[suffix] > max) {
                        max = count[suffix]
                        selected = suffix
                    }
                }
                if (selected != "") {
                    print selected
                }
            }
        '
}

collect_routes() {
    local routes_json="$1"

    if [ -n "${ROUTES_FILE}" ]; then
        if [ ! -f "${ROUTES_FILE}" ]; then
            echo "Error: routes file not found: ${ROUTES_FILE}" >&2
            exit 1
        fi
        cp "${ROUTES_FILE}" "${routes_json}"
    else
        kubectl get "${RESOURCE}" -A -o json > "${routes_json}"
    fi
}

route_default_choice() {
    local route_json="$1"
    local has_backend="$2"

    if [ "${has_backend}" != "true" ]; then
        echo "S"
        return
    fi

    if jq -e '
        any(.spec.hostnames[]?; test("(^|[.])internal[.]"))
    ' <<< "${route_json}" >/dev/null; then
        echo "I"
        return
    fi

    echo "E"
}

choose_route_exposure() {
    local route_json="$1"
    local has_backend="$2"
    local default_choice metadata choice

    metadata=$(route_metadata_json <<< "${route_json}")
    default_choice=$(route_default_choice "${route_json}" "${has_backend}")

    echo >&2
    jq -r '
        "Route: \(.namespace)/\(.name)",
        "  Hostnames: \((.hostnames | join(", ")) // "(none)")",
        "  Parents: \((.parents | join(", ")) // "(none)")",
        "  Backends: \((.backends | join(", ")) // "(none)")"
    ' <<< "${metadata}" >&2

    if [ "${has_backend}" != "true" ]; then
        echo "  No Service backendRefs found; defaulting to Skip." >&2
    fi

    while true; do
        read -r -p "Expose as (I)nternal, (E)xternal, (B)oth, or (S)kip [${default_choice}]: " choice </dev/tty
        choice="${choice:-${default_choice}}"
        choice=$(tr '[:lower:]' '[:upper:]' <<< "${choice}")
        case "${choice}" in
            I|INTERNAL)
                echo "internal"
                return
                ;;
            E|EXTERNAL)
                echo "external"
                return
                ;;
            B|BOTH)
                echo "both"
                return
                ;;
            S|SKIP|SKIPPED)
                echo "skip"
                return
                ;;
            *)
                echo "Please choose I, E, B, or S." >&2
                ;;
        esac
    done
}

cleanup_temp_files() {
    rm -f \
        ${TEMP_ROUTES_JSON:+"${TEMP_ROUTES_JSON}"} \
        ${TEMP_ROUTES_OUTPUT:+"${TEMP_ROUTES_OUTPUT}"} \
        ${TEMP_RENDERED_OUTPUT:+"${TEMP_RENDERED_OUTPUT}"}
}

append_route_config() {
    local route_json="$1"
    local exposure="$2"
    local routes_output="$3"
    local route_name route_namespace route_key section_name backend_json backend_name backend_namespace backend_port

    route_name=$(jq -r '.metadata.name' <<< "${route_json}")
    route_namespace=$(jq -r '.metadata.namespace' <<< "${route_json}")
    route_key=$(sanitize_route_key "$(route_key_from_name "${route_name}")")
    section_name=$(jq -r '.spec.parentRefs[0].sectionName // ""' <<< "${route_json}")
    backend_json=$(first_backend_json "${route_json}")
    backend_name=$(jq -r '.name // ""' <<< "${backend_json}")
    backend_namespace=$(jq -r --arg route_namespace "${route_namespace}" '.namespace // $route_namespace' <<< "${backend_json}")
    backend_port=$(jq -r '.port // ""' <<< "${backend_json}")

    {
        printf '  - name: %s\n' "$(yaml_quote "${route_key}")"
        printf '    exposure: %s\n' "$(yaml_quote "${exposure}")"

        if [ -n "${section_name}" ]; then
            printf '    section_name: %s\n' "$(yaml_quote "${section_name}")"
        fi

        printf '    namespace: %s\n' "$(yaml_quote "${route_namespace}")"

        if [ -n "${backend_name}" ]; then
            printf '    service: %s\n' "$(yaml_quote "${backend_name}")"
            printf '    service_namespace: %s\n' "$(yaml_quote "${backend_namespace}")"
        fi

        if [ -n "${backend_port}" ]; then
            printf '    port: %s\n' "$(yaml_quote "${backend_port}")"
        fi
    } >> "${routes_output}"
}

write_gateway_config() {
    local output_file="$1"
    local routes_output="$2"
    local external_enabled="$3"
    local internal_enabled="$4"

    {
        printf 'domain: %s\n\n' "$(yaml_quote "${GATEWAY_DOMAIN}")"

        if [ "${ACME_ENABLED}" = "true" ]; then
            cat <<EOF
acme:
  enabled: true
  email: $(yaml_quote "${ACME_EMAIL}")
  issuer: $(yaml_quote "${ACME_ISSUER}")
  gateway: $(yaml_quote "${EXTERNAL_GATEWAY}")

EOF
        fi

        cat <<EOF
gateways:
  ${EXTERNAL_GATEWAY}:
    enabled: ${external_enabled}
    namespace: $(yaml_quote "${EXTERNAL_NAMESPACE}")
    type: external
    domain: $(yaml_quote "${GATEWAY_DOMAIN}")
    gateway_class: $(yaml_quote "${EXTERNAL_CLASS}")
    issuer: $(yaml_quote "${EXTERNAL_ISSUER}")
    metallb_pool: $(yaml_quote "${EXTERNAL_POOL}")
    certificate_secret: $(yaml_quote "${EXTERNAL_SECRET}")

  ${INTERNAL_GATEWAY}:
    enabled: ${internal_enabled}
    namespace: $(yaml_quote "${INTERNAL_NAMESPACE}")
    type: internal
    domain: $(yaml_quote "${INTERNAL_DOMAIN}")
    gateway_class: $(yaml_quote "${INTERNAL_CLASS}")
    issuer: $(yaml_quote "${INTERNAL_ISSUER}")
    metallb_pool: $(yaml_quote "${INTERNAL_POOL}")
    certificate_secret: $(yaml_quote "${INTERNAL_SECRET}")

routes:
EOF

        cat "${routes_output}"
    } > "${output_file}"
}

install_output() {
    local rendered_file="$1"
    local output_file="$2"
    local output_dir

    output_dir=$(dirname "${output_file}")

    if [ -e "${output_file}" ] && [ "${FORCE}" != "true" ]; then
        if ! prompt_yes_no "Overwrite ${output_file}?" "n"; then
            echo "Not writing ${output_file}."
            exit 1
        fi
    fi

    if [ ! -d "${output_dir}" ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo mkdir -p "${output_dir}"
        else
            mkdir -p "${output_dir}"
        fi
    fi

    if [ -w "${output_dir}" ] || { [ -e "${output_file}" ] && [ -w "${output_file}" ]; }; then
        mv "${rendered_file}" "${output_file}"
    elif command -v sudo >/dev/null 2>&1; then
        sudo install -m 0644 "${rendered_file}" "${output_file}"
        rm -f "${rendered_file}"
    else
        echo "Error: cannot write ${output_file}; run as root or choose --output." >&2
        exit 1
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -d|--domain)
                GATEWAY_DOMAIN="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --routes-file)
                ROUTES_FILE="$2"
                shift 2
                ;;
            --acme-email)
                ACME_EMAIL="$2"
                ACME_ENABLED=true
                EXTERNAL_ISSUER="${ACME_ISSUER}"
                shift 2
                ;;
            --external-issuer)
                EXTERNAL_ISSUER="$2"
                shift 2
                ;;
            --internal-issuer)
                INTERNAL_ISSUER="$2"
                shift 2
                ;;
            --external-pool)
                EXTERNAL_POOL="$2"
                shift 2
                ;;
            --internal-pool)
                INTERNAL_POOL="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

main() {
    local routes_json routes_output rendered_output route_json
    local inferred_domain exposure has_backend
    local route_count=0 selected_count=0 external_enabled=false internal_enabled=false

    parse_args "$@"
    require_tools

    if [ ! -r /dev/tty ]; then
        echo "Error: this helper must be run from an interactive terminal." >&2
        exit 1
    fi

    TEMP_ROUTES_JSON=$(mktemp)
    TEMP_ROUTES_OUTPUT=$(mktemp)
    TEMP_RENDERED_OUTPUT=$(mktemp)
    routes_json="${TEMP_ROUTES_JSON}"
    routes_output="${TEMP_ROUTES_OUTPUT}"
    rendered_output="${TEMP_RENDERED_OUTPUT}"
    trap cleanup_temp_files EXIT

    collect_routes "${routes_json}"
    route_count=$(jq '.items | length' "${routes_json}")
    if [ "${route_count}" -eq 0 ]; then
        echo "No HTTPRoutes found."
        exit 1
    fi

    inferred_domain=$(infer_domain "${routes_json}")
    if [ -z "${GATEWAY_DOMAIN}" ]; then
        GATEWAY_DOMAIN=$(prompt "Gateway domain" "${inferred_domain:-cluster.local}")
    fi
    INTERNAL_DOMAIN=$(prompt "Internal gateway domain" "internal.${GATEWAY_DOMAIN}")
    OUTPUT_FILE=$(prompt "Output config file" "${OUTPUT_FILE}")

    if [ "${ACME_ENABLED}" != "true" ]; then
        if prompt_yes_no "Enable ACME/Let's Encrypt for external routes?" "n"; then
            ACME_ENABLED=true
            ACME_EMAIL=$(prompt "ACME email" "${ACME_EMAIL}")
            EXTERNAL_ISSUER="${ACME_ISSUER}"
        fi
    fi

    if [ "${ACME_ENABLED}" = "true" ] && [ -z "${ACME_EMAIL}" ]; then
        echo "Error: ACME was enabled but no email was provided." >&2
        exit 1
    fi

    echo
    echo "Found ${route_count} HTTPRoutes. Choose exposure for each route."

    while IFS= read -r route_json; do
        has_backend=false
        if route_has_backend "${route_json}"; then
            has_backend=true
        fi

        exposure=$(choose_route_exposure "${route_json}" "${has_backend}")
        if [ "${exposure}" = "skip" ]; then
            continue
        fi

        if [ "${has_backend}" != "true" ]; then
            echo "Skipping route without a Service backend." >&2
            continue
        fi

        append_route_config "${route_json}" "${exposure}" "${routes_output}"
        selected_count=$((selected_count + 1))

        case "${exposure}" in
            external)
                external_enabled=true
                ;;
            internal)
                internal_enabled=true
                ;;
            both)
                external_enabled=true
                internal_enabled=true
                ;;
        esac
    done < <(jq -c '.items[]? | select((.kind // "") == "HTTPRoute" or ((.apiVersion // "") | startswith("gateway.networking.k8s.io/"))) | .' "${routes_json}" | sort)

    if [ "${selected_count}" -eq 0 ]; then
        echo "No routes selected; no config generated."
        exit 1
    fi

    write_gateway_config "${rendered_output}" "${routes_output}" "${external_enabled}" "${internal_enabled}"
    install_output "${rendered_output}" "${OUTPUT_FILE}"

    echo
    echo "Wrote Envoy Gateway config: ${OUTPUT_FILE}"
    echo "Routes selected: ${selected_count}"
    echo "External gateway enabled: ${external_enabled}"
    echo "Internal gateway enabled: ${internal_enabled}"
}

main "$@"
