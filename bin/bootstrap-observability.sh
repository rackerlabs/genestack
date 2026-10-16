#!/usr/bin/env bash

set -euo pipefail

GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
GENESTACK_OBSERVABILITY_DIR="${GENESTACK_OBSERVABILITY_DIR:-/opt/genestack-observability}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"

GENESTACK_OBSERVABILITY_REPO="${GENESTACK_OBSERVABILITY_REPO:-git@github.com:rackerlabs/genestack-observability.git}"

HELM_SOURCE="${GENESTACK_OBSERVABILITY_DIR}/helm-configs"
HELM_TARGET="${GENESTACK_DIR}/base-helm-configs/observability"
HELM_SITE_DIR="${GENESTACK_CONFIG_DIR}/helm-configs/observability"

KUSTOMIZE_SOURCE="${GENESTACK_OBSERVABILITY_DIR}/kustomize"
KUSTOMIZE_TARGET="${GENESTACK_DIR}/base-kustomize/observability"
KUSTOMIZE_SITE_ROOT="${GENESTACK_CONFIG_DIR}/kustomize"
KUSTOMIZE_SITE_DIR="${KUSTOMIZE_SITE_ROOT}/observability"
KUSTOMIZE_RENDERER_SOURCE="${GENESTACK_DIR}/base-kustomize/kustomize.sh"
KUSTOMIZE_RENDERER_TARGET="${KUSTOMIZE_SITE_ROOT}/kustomize.sh"

GATEWAY_ROUTE_SOURCE_DIR="${GENESTACK_OBSERVABILITY_DIR}/etc/gateway-api/routes"
GATEWAY_ROUTE_TARGET_DIR="${GENESTACK_CONFIG_DIR}/gateway-api/routes"
GATEWAY_LISTENER_SOURCE_DIR="${GENESTACK_OBSERVABILITY_DIR}/etc/gateway-api/listeners"
GATEWAY_LISTENER_FALLBACK_DIR="${GENESTACK_DIR}/etc/gateway-api/listeners"
GATEWAY_LISTENER_TARGET_DIR="${GENESTACK_CONFIG_DIR}/gateway-api/listeners"

RUN_INSTALL=true
UPDATE_REPO=true
MANAGE_ROUTES=true

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Bootstrap genestack-observability on a Genestack overseer.

Options:
  --no-install    Configure the repository and links but do not install services.
  --no-update     Do not git pull when the repository already exists.
  --no-routes     Do not seed or apply observability Gateway API routes.
  -h, --help      Show this help.

Environment:
  GENESTACK_DIR                  Default: /opt/genestack
  GENESTACK_OBSERVABILITY_DIR    Default: /opt/genestack-observability
  GENESTACK_CONFIG_DIR           Default: /etc/genestack
  GENESTACK_OBSERVABILITY_REPO   Default:
                                 git@github.com:rackerlabs/genestack-observability.git
  GENESTACK_OBSERVABILITY_OWNER  Repository owner. Defaults to SUDO_USER when
                                 available, otherwise the invoking user.
  GENESTACK_OBSERVABILITY_GROUP  Repository group. Defaults to the owner's
                                 primary group.
  OBSERVABILITY_GATEWAY_DOMAIN   Optional domain used when rendering missing
                                 route templates containing your.domain.tld.
                                 Falls back to GATEWAY_DOMAIN, envoy-gateways.yaml,
                                 or a wildcard Gateway listener.

Observability route templates are sourced from:
  /opt/genestack-observability/etc/gateway-api/routes

Rendered/site-specific routes live under:
  /etc/genestack/gateway-api/routes

Lab-only service configuration seeding:
  Helm source:       /opt/genestack-observability/helm-configs
  Helm site target:  /etc/genestack/helm-configs/observability
  Kustomize source:  /opt/genestack-observability/kustomize
  Kustomize target:  /etc/genestack/kustomize/observability

Existing site service directories are never overwritten or merged.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-install)
            RUN_INSTALL=false
            shift
            ;;
        --no-update)
            UPDATE_REPO=false
            shift
            ;;
        --no-routes)
            MANAGE_ROUTES=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ ! -d "${GENESTACK_DIR}" ]]; then
    echo "ERROR: Genestack directory does not exist: ${GENESTACK_DIR}"
    exit 1
fi

for path in \
    "${GENESTACK_DIR}/base-helm-configs" \
    "${GENESTACK_DIR}/base-kustomize"
do
    if [[ ! -d "${path}" ]]; then
        echo "ERROR: Expected Genestack directory does not exist: ${path}"
        exit 1
    fi
done

GENESTACK_OBSERVABILITY_OWNER="${GENESTACK_OBSERVABILITY_OWNER:-${SUDO_USER:-$(id -un)}}"

if ! id "${GENESTACK_OBSERVABILITY_OWNER}" >/dev/null 2>&1; then
    echo "ERROR: Repository owner does not exist: ${GENESTACK_OBSERVABILITY_OWNER}"
    exit 1
fi

GENESTACK_OBSERVABILITY_GROUP="${GENESTACK_OBSERVABILITY_GROUP:-$(id -gn "${GENESTACK_OBSERVABILITY_OWNER}")}"

run_privileged() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is required to prepare ${GENESTACK_OBSERVABILITY_DIR}."
        exit 1
    fi

    sudo "$@"
}

run_as_repo_owner() {
    local owner_uid

    owner_uid="$(id -u "${GENESTACK_OBSERVABILITY_OWNER}")"

    if [[ "${EUID}" -eq "${owner_uid}" ]]; then
        "$@"
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is required to run repository operations as ${GENESTACK_OBSERVABILITY_OWNER}."
        exit 1
    fi

    sudo -H -u "${GENESTACK_OBSERVABILITY_OWNER}" -- "$@"
}

ensure_repo_directory() {
    if [[ -L "${GENESTACK_OBSERVABILITY_DIR}" ]]; then
        echo "ERROR: Refusing to use a symlink as the observability repository root:"
        echo "  ${GENESTACK_OBSERVABILITY_DIR}"
        exit 1
    fi

    if [[ -e "${GENESTACK_OBSERVABILITY_DIR}" && ! -d "${GENESTACK_OBSERVABILITY_DIR}" ]]; then
        echo "ERROR: Observability repository path exists but is not a directory:"
        echo "  ${GENESTACK_OBSERVABILITY_DIR}"
        exit 1
    fi

    if [[ ! -d "${GENESTACK_OBSERVABILITY_DIR}" ]]; then
        echo "Creating observability repository directory:"
        echo "  ${GENESTACK_OBSERVABILITY_DIR}"

        run_privileged mkdir -p "${GENESTACK_OBSERVABILITY_DIR}"
    fi

    # /opt is normally root-owned. Bootstrap only uses privilege here to
    # prepare the repository path; Git operations themselves run as the
    # non-root repository owner.
    run_privileged chown \
        "${GENESTACK_OBSERVABILITY_OWNER}:${GENESTACK_OBSERVABILITY_GROUP}" \
        "${GENESTACK_OBSERVABILITY_DIR}"
}

ensure_repo_ownership() {
    local mismatched_path

    mismatched_path="$(
        find "${GENESTACK_OBSERVABILITY_DIR}" \
            -xdev \
            \( \
                ! -user "${GENESTACK_OBSERVABILITY_OWNER}" \
                -o \
                ! -group "${GENESTACK_OBSERVABILITY_GROUP}" \
            \) \
            -print \
            -quit \
            2>/dev/null || true
    )"

    if [[ -z "${mismatched_path}" ]]; then
        return
    fi

    echo "Correcting observability repository ownership:"
    echo "  ${GENESTACK_OBSERVABILITY_DIR}"
    echo "  owner: ${GENESTACK_OBSERVABILITY_OWNER}:${GENESTACK_OBSERVABILITY_GROUP}"

    run_privileged chown -R \
        "${GENESTACK_OBSERVABILITY_OWNER}:${GENESTACK_OBSERVABILITY_GROUP}" \
        "${GENESTACK_OBSERVABILITY_DIR}"
}

ensure_repo_directory

if [[ ! -d "${GENESTACK_OBSERVABILITY_DIR}/.git" ]]; then
    if find "${GENESTACK_OBSERVABILITY_DIR}" \
        -mindepth 1 \
        -maxdepth 1 \
        -print \
        -quit | grep -q .; then
        echo "ERROR: ${GENESTACK_OBSERVABILITY_DIR} exists but is not an empty Git checkout target."
        echo "Refusing to delete or overwrite existing content."
        exit 1
    fi

    echo "Cloning genestack-observability as ${GENESTACK_OBSERVABILITY_OWNER}..."
    run_as_repo_owner git clone \
        --recurse-submodules \
        "${GENESTACK_OBSERVABILITY_REPO}" \
        "${GENESTACK_OBSERVABILITY_DIR}"
else
    ensure_repo_ownership

    if [[ "${UPDATE_REPO}" == "true" ]]; then
        echo "Updating genestack-observability as ${GENESTACK_OBSERVABILITY_OWNER}..."
        run_as_repo_owner git \
            -C "${GENESTACK_OBSERVABILITY_DIR}" \
            pull --ff-only

        echo "Synchronizing and updating submodules..."
        run_as_repo_owner git \
            -C "${GENESTACK_OBSERVABILITY_DIR}" \
            submodule sync --recursive

        run_as_repo_owner git \
            -C "${GENESTACK_OBSERVABILITY_DIR}" \
            submodule update \
            --init \
            --recursive
    fi
fi

for source in "${HELM_SOURCE}" "${KUSTOMIZE_SOURCE}"; do
    if [[ ! -d "${source}" ]]; then
        echo "ERROR: Required observability directory does not exist: ${source}"
        exit 1
    fi
done

ensure_symlink() {
    local source="$1"
    local target="$2"

    if [[ -L "${target}" ]]; then
        ln -sfn "${source}" "${target}"
        echo "Updated symlink: ${target} -> ${source}"
        return
    fi

    if [[ -e "${target}" ]]; then
        echo "ERROR: Refusing to replace existing non-symlink path:"
        echo "  ${target}"
        echo "Reconcile or remove it before rerunning bootstrap."
        exit 1
    fi

    ln -s "${source}" "${target}"
    echo "Created symlink: ${target} -> ${source}"
}

ensure_symlink "${HELM_SOURCE}" "${HELM_TARGET}"
ensure_symlink "${KUSTOMIZE_SOURCE}" "${KUSTOMIZE_TARGET}"

mkdir -p "${GENESTACK_CONFIG_DIR}"

seed_helm_service_configs() {
    local source_dir
    local service_name
    local target_dir
    local found=0
    local created=0
    local kept=0

    mkdir -p "${HELM_SITE_DIR}"

    shopt -s nullglob
    for source_dir in "${HELM_SOURCE}"/*; do
        [[ -d "${source_dir}" ]] || continue

        found=1
        service_name="$(basename "${source_dir}")"
        target_dir="${HELM_SITE_DIR}/${service_name}"

        # /etc/genestack is site/operator-owned. If the service directory
        # already exists in any form, leave the complete tree untouched.
        if [[ -e "${target_dir}" || -L "${target_dir}" ]]; then
            echo "Keeping existing Helm service configuration: ${target_dir}"
            kept=$((kept + 1))
            continue
        fi

        cp -a -- "${source_dir}" "${target_dir}"
        echo "Created Helm service configuration: ${target_dir}"
        created=$((created + 1))
    done
    shopt -u nullglob

    if [[ "${found}" -eq 0 ]]; then
        echo "No observability Helm service directories found under:"
        echo "  ${HELM_SOURCE}"
    else
        echo "Helm service configuration: created=${created} existing=${kept}"
    fi
}

ensure_kustomize_renderer() {
    mkdir -p "${KUSTOMIZE_SITE_ROOT}" "${KUSTOMIZE_SITE_DIR}"

    # The Genestack post-renderer itself remains core-owned. If a site copy or
    # link already exists, do not touch it.
    if [[ -e "${KUSTOMIZE_RENDERER_TARGET}" || -L "${KUSTOMIZE_RENDERER_TARGET}" ]]; then
        echo "Keeping existing Kustomize post-renderer: ${KUSTOMIZE_RENDERER_TARGET}"
        return 0
    fi

    if [[ ! -f "${KUSTOMIZE_RENDERER_SOURCE}" ]]; then
        echo "ERROR: Genestack Kustomize post-renderer is missing:"
        echo "  ${KUSTOMIZE_RENDERER_SOURCE}"
        return 1
    fi

    ln -s "${KUSTOMIZE_RENDERER_SOURCE}" "${KUSTOMIZE_RENDERER_TARGET}"
    echo "Created Kustomize post-renderer link:"
    echo "  ${KUSTOMIZE_RENDERER_TARGET} -> ${KUSTOMIZE_RENDERER_SOURCE}"
}

seed_kustomize_service_configs() {
    local source_dir
    local service_name
    local target_dir
    local source_base
    local target_base
    local target_overlay
    local found=0
    local created_services=0
    local created_bases=0
    local created_overlays=0

    ensure_kustomize_renderer
    mkdir -p "${KUSTOMIZE_SITE_DIR}"

    shopt -s nullglob
    for source_dir in "${KUSTOMIZE_SOURCE}"/*; do
        [[ -d "${source_dir}" ]] || continue

        found=1
        service_name="$(basename "${source_dir}")"
        target_dir="${KUSTOMIZE_SITE_DIR}/${service_name}"
        source_base="${source_dir}/base"
        target_base="${target_dir}/base"
        target_overlay="${target_dir}/overlay"

        if [[ ! -e "${target_dir}" && ! -L "${target_dir}" ]]; then
            mkdir "${target_dir}"
            echo "Created Kustomize service directory: ${target_dir}"
            created_services=$((created_services + 1))
        elif [[ ! -d "${target_dir}" ]]; then
            echo "WARNING: Existing Kustomize service path is not a directory; leaving it untouched:"
            echo "  ${target_dir}"
            continue
        fi

        # The observability repository owns the base. Seed it only when the
        # site path does not already exist. Never merge into or replace an
        # existing /etc/genestack base.
        if [[ -d "${source_base}" ]]; then
            if [[ -e "${target_base}" || -L "${target_base}" ]]; then
                echo "Keeping existing Kustomize base: ${target_base}"
            else
                cp -a -- "${source_base}" "${target_base}"
                echo "Created Kustomize base: ${target_base}"
                created_bases=$((created_bases + 1))
            fi
        else
            echo "Info: Observability Kustomize source has no base directory for ${service_name}:"
            echo "  ${source_base}"
        fi

        # The overlay is site-owned and intentionally does not exist in the
        # observability repository. For a fresh lab build, create the minimal
        # overlay expected by the shared Genestack post-renderer.
        if [[ -e "${target_overlay}" || -L "${target_overlay}" ]]; then
            echo "Keeping existing Kustomize overlay: ${target_overlay}"
        else
            mkdir "${target_overlay}"
            cat > "${target_overlay}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
EOF
            echo "Created Kustomize overlay: ${target_overlay}"
            created_overlays=$((created_overlays + 1))
        fi
    done
    shopt -u nullglob

    if [[ "${found}" -eq 0 ]]; then
        echo "No observability Kustomize service directories found under:"
        echo "  ${KUSTOMIZE_SOURCE}"
    else
        echo "Kustomize service configuration:"
        echo "  created service dirs=${created_services}"
        echo "  created base dirs=${created_bases}"
        echo "  created overlays=${created_overlays}"
    fi
}

echo
echo "Seeding missing observability Helm service configuration..."
seed_helm_service_configs

echo
echo "Seeding missing observability Kustomize service configuration..."
seed_kustomize_service_configs

resolve_gateway_domain() {
    local domain=""

    if [[ -n "${OBSERVABILITY_GATEWAY_DOMAIN:-}" ]]; then
        printf '%s\n' "${OBSERVABILITY_GATEWAY_DOMAIN}"
        return 0
    fi

    if [[ -n "${GATEWAY_DOMAIN:-}" ]]; then
        printf '%s\n' "${GATEWAY_DOMAIN}"
        return 0
    fi

    if command -v yq >/dev/null 2>&1 && \
       [[ -f "${GENESTACK_CONFIG_DIR}/envoy-gateways.yaml" ]]; then
        domain="$(
            yq eval -r '.domain // ""' \
                "${GENESTACK_CONFIG_DIR}/envoy-gateways.yaml" 2>/dev/null || true
        )"
        if [[ -n "${domain}" && "${domain}" != "null" ]]; then
            printf '%s\n' "${domain}"
            return 0
        fi
    fi

    if command -v kubectl >/dev/null 2>&1; then
        domain="$(
            kubectl get gateway -A \
                -o jsonpath='{range .items[*].spec.listeners[*]}{.hostname}{"\n"}{end}' \
                2>/dev/null |
            sed -n 's/^\*\.//p' |
            head -n1
        )"
        if [[ -n "${domain}" ]]; then
            printf '%s\n' "${domain}"
            return 0
        fi
    fi

    return 1
}

gateway_config_mode_enabled() {
    local config_file="${GENESTACK_CONFIG_DIR}/envoy-gateways.yaml"
    local gateway_count="0"

    [[ -f "${config_file}" ]] || return 1
    command -v yq >/dev/null 2>&1 || return 1

    gateway_count="$(
        yq eval -r '(.gateways // {}) | length' "${config_file}" 2>/dev/null || true
    )"

    [[ "${gateway_count}" =~ ^[0-9]+$ ]] && [[ "${gateway_count}" -gt 0 ]]
}

route_is_observability() {
    local route_file="$1"
    local kind
    local route_namespace
    local backend_namespaces

    command -v yq >/dev/null 2>&1 || return 1

    kind="$(yq eval -r '.kind // ""' "${route_file}" 2>/dev/null || true)"
    [[ "${kind}" == "HTTPRoute" ]] || return 1

    route_namespace="$(
        yq eval -r '.metadata.namespace // ""' "${route_file}" 2>/dev/null || true
    )"

    if [[ "${route_namespace}" == "monitoring" ]]; then
        return 0
    fi

    backend_namespaces="$(
        yq eval -r '.spec.rules[]?.backendRefs[]?.namespace // ""' \
            "${route_file}" 2>/dev/null || true
    )"

    grep -qx 'monitoring' <<< "${backend_namespaces}"
}

find_listener_template() {
    local listener_name="$1"
    local source_dir
    local candidate
    local candidate_listener_name

    for source_dir in \
        "${GATEWAY_LISTENER_SOURCE_DIR}" \
        "${GATEWAY_LISTENER_FALLBACK_DIR}"; do
        [[ -d "${source_dir}" ]] || continue

        # Prefer conventional filenames when present.
        for candidate in \
            "${source_dir}/${listener_name}.json" \
            "${source_dir}/${listener_name}-https.json" \
            "${source_dir}/${listener_name}-listener.json"; do
            if [[ -f "${candidate}" ]]; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        done

        # Listener patch filenames do not have to match the sectionName.
        # Inspect the JSON patch content and match .[0].value.name.
        while IFS= read -r -d '' candidate; do
            candidate_listener_name="$(
                yq eval -r '.[0].value.name // ""' \
                    "${candidate}" 2>/dev/null || true
            )"

            if [[ "${candidate_listener_name}" == "${listener_name}" ]]; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        done < <(
            find "${source_dir}" \
                -maxdepth 1 \
                -type f \
                -name '*.json' \
                -print0 |
            sort -z
        )
    done

    return 1
}

seed_listener_template() {
    local listener_name="$1"
    local gateway_domain="$2"
    local source_file=""
    local target_file=""
    local temp_file=""

    source_file="$(find_listener_template "${listener_name}" || true)"
    [[ -n "${source_file}" ]] || return 0

    mkdir -p "${GATEWAY_LISTENER_TARGET_DIR}"
    target_file="${GATEWAY_LISTENER_TARGET_DIR}/$(basename "${source_file}")"

    if [[ -e "${target_file}" ]]; then
        echo "Keeping existing Gateway listener: ${target_file}"
        return 0
    fi

    if grep -q 'your\.domain\.tld' "${source_file}"; then
        if [[ -z "${gateway_domain}" ]]; then
            echo "WARNING: Cannot render missing listener ${listener_name} without a gateway domain:"
            echo "  ${source_file}"
            return 0
        fi

        temp_file="$(mktemp)"
        sed "s/your\\.domain\\.tld/${gateway_domain}/g" \
            "${source_file}" > "${temp_file}"
        mv "${temp_file}" "${target_file}"
    else
        cp "${source_file}" "${target_file}"
    fi

    echo "Created Gateway listener: ${target_file}"
}

seed_observability_routes() {
    local route_template
    local target_file
    local gateway_domain=""
    local temp_file
    local listener_name

    if gateway_config_mode_enabled; then
        echo "Envoy multi-gateway config mode detected:"
        echo "  ${GENESTACK_CONFIG_DIR}/envoy-gateways.yaml"
        echo "Skipping legacy observability route seeding; config mode owns route rendering."
        return 0
    fi

    if [[ ! -d "${GATEWAY_ROUTE_SOURCE_DIR}" ]]; then
        echo "Observability Gateway route template directory not found; skipping route seeding:"
        echo "  ${GATEWAY_ROUTE_SOURCE_DIR}"
        return 0
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "WARNING: yq is not available; skipping observability route discovery."
        return 0
    fi

    mkdir -p "${GATEWAY_ROUTE_TARGET_DIR}"
    gateway_domain="$(resolve_gateway_domain || true)"

    while IFS= read -r -d '' route_template; do
        route_is_observability "${route_template}" || continue

        target_file="${GATEWAY_ROUTE_TARGET_DIR}/$(basename "${route_template}")"

        # genestack-observability owns the route templates; /etc/genestack is the
        # site-owned rendered/override location. Never replace an existing route.
        if [[ -e "${target_file}" ]]; then
            echo "Keeping existing observability route: ${target_file}"
        elif grep -q 'your\.domain\.tld' "${route_template}"; then
            if [[ -z "${gateway_domain}" ]]; then
                echo "WARNING: Cannot render missing observability route without a gateway domain:"
                echo "  ${route_template}"
                echo "Set OBSERVABILITY_GATEWAY_DOMAIN or GATEWAY_DOMAIN and rerun bootstrap."
                continue
            fi

            temp_file="$(mktemp)"
            sed "s/your\\.domain\\.tld/${gateway_domain}/g" \
                "${route_template}" > "${temp_file}"
            mv "${temp_file}" "${target_file}"
            echo "Created observability route: ${target_file}"
        else
            cp "${route_template}" "${target_file}"
            echo "Created observability route: ${target_file}"
        fi

        # Seed only listener templates referenced by the observability route.
        while IFS= read -r listener_name; do
            [[ -n "${listener_name}" && "${listener_name}" != "null" ]] || continue
            seed_listener_template "${listener_name}" "${gateway_domain}"
        done < <(
            yq eval -r '.spec.parentRefs[]?.sectionName // ""' \
                "${target_file}" 2>/dev/null |
            sed '/^$/d' |
            sort -u
        )
    done < <(
        find "${GATEWAY_ROUTE_SOURCE_DIR}" \
            -maxdepth 1 \
            -type f \
            \( -name '*.yaml' -o -name '*.yml' \) \
            -print0 |
        sort -z
    )
}

listener_file_for_section() {
    local listener_name="$1"
    local candidate
    local candidate_listener_name

    [[ -d "${GATEWAY_LISTENER_TARGET_DIR}" ]] || return 1

    # Prefer conventional filenames when present.
    for candidate in \
        "${GATEWAY_LISTENER_TARGET_DIR}/${listener_name}.json" \
        "${GATEWAY_LISTENER_TARGET_DIR}/${listener_name}-https.json" \
        "${GATEWAY_LISTENER_TARGET_DIR}/${listener_name}-listener.json"; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    # Fall back to matching the listener name inside each JSON patch.
    while IFS= read -r -d '' candidate; do
        candidate_listener_name="$(
            yq eval -r '.[0].value.name // ""' \
                "${candidate}" 2>/dev/null || true
        )"

        if [[ "${candidate_listener_name}" == "${listener_name}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done < <(
        find "${GATEWAY_LISTENER_TARGET_DIR}" \
            -maxdepth 1 \
            -type f \
            -name '*.json' \
            -print0 |
        sort -z
    )

    return 1
}

gateway_listener_exists() {
    local gateway_name="$1"
    local gateway_namespace="$2"
    local listener_name="$3"

    command -v jq >/dev/null 2>&1 || return 1

    kubectl -n "${gateway_namespace}" get gateway "${gateway_name}" -o json \
        2>/dev/null \
        | jq -e --arg name "${listener_name}" \
            '.spec.listeners[]? | select(.name == $name)' \
            >/dev/null 2>&1
}

ensure_gateway_listener() {
    local gateway_name="$1"
    local gateway_namespace="$2"
    local listener_file="$3"
    local listener_name
    local desired_listener
    local existing_listener
    local gateway_json
    local existing_index
    local patch_file

    command -v jq >/dev/null 2>&1 || {
        echo "WARNING: jq is not available; skipping optional Gateway listener management for ${listener_file}"
        return 0
    }

    if ! kubectl -n "${gateway_namespace}" get gateway "${gateway_name}" \
        >/dev/null 2>&1; then
        echo "WARNING: Gateway ${gateway_namespace}/${gateway_name} does not exist; skipping optional listener patch:"
        echo "  ${listener_file}"
        return 0
    fi

    listener_name="$(jq -r '.[0].value.name // ""' "${listener_file}" 2>/dev/null || true)"
    if [[ -z "${listener_name}" ]]; then
        echo "WARNING: Listener patch does not contain .[0].value.name; skipping:"
        echo "  ${listener_file}"
        return 0
    fi

    desired_listener="$(
        jq -c '.[0].value | {name, port, protocol, hostname, tls, allowedRoutes}' \
            "${listener_file}" 2>/dev/null || true
    )"

    if [[ -z "${desired_listener}" || "${desired_listener}" == "null" ]]; then
        echo "WARNING: Could not parse listener patch; skipping:"
        echo "  ${listener_file}"
        return 0
    fi

    gateway_json="$(
        kubectl -n "${gateway_namespace}" get gateway "${gateway_name}" -o json
    )"
    existing_listener="$(
        jq -c --arg name "${listener_name}" \
            '.spec.listeners[]? |
             select(.name == $name) |
             {name, port, protocol, hostname, tls, allowedRoutes}' \
            <<< "${gateway_json}"
    )"

    if [[ -n "${existing_listener}" ]]; then
        if [[ "${existing_listener}" != "${desired_listener}" ]]; then
            echo "WARNING: Gateway listener ${gateway_namespace}/${gateway_name}:${listener_name}"
            echo "already exists and differs from ${listener_file}; leaving the live listener unchanged."
        else
            echo "Gateway listener ${gateway_namespace}/${gateway_name}:${listener_name} already present."
        fi
        return 0
    fi

    # Preserve the special handling used by the Genestack gateway setup:
    # http-wildcard-listener replaces the legacy cluster-http listener.
    if [[ "${listener_name}" == "http-wildcard-listener" ]]; then
        existing_index="$(
            jq -r '
                .spec.listeners
                | to_entries[]
                | select(.value.name == "cluster-http")
                | .key
            ' <<< "${gateway_json}"
        )"

        if [[ -n "${existing_index}" ]]; then
            patch_file="$(mktemp)"
            jq -n \
                --argjson index "${existing_index}" \
                --argjson listener "${desired_listener}" \
                '[{"op":"replace","path":("/spec/listeners/" + ($index|tostring)),"value":$listener}]' \
                > "${patch_file}"

            echo "Replacing cluster-http with ${listener_name} on ${gateway_namespace}/${gateway_name}"
            if ! kubectl -n "${gateway_namespace}" patch gateway "${gateway_name}" \
                --type='json' \
                --patch-file "${patch_file}"; then
                echo "WARNING: Failed to apply optional Gateway listener patch for ${listener_name}."
            fi
            rm -f "${patch_file}"
            return 0
        fi
    fi

    echo "Adding optional Gateway listener ${listener_name} to ${gateway_namespace}/${gateway_name}"
    if ! kubectl -n "${gateway_namespace}" patch gateway "${gateway_name}" \
        --type='json' \
        --patch-file "${listener_file}"; then
        echo "WARNING: Failed to apply optional Gateway listener patch for ${listener_name}."
    fi

    return 0
}

ensure_route_listeners() {
    local route_file="$1"
    local gateway_name
    local gateway_namespace
    local listener_name
    local listener_file

    while IFS=$'\t' read -r gateway_name gateway_namespace listener_name; do
        [[ -n "${gateway_name}" && -n "${listener_name}" ]] || continue
        gateway_namespace="${gateway_namespace:-envoy-gateway}"

        # Site-owned Gateway configuration wins. If the live Gateway already
        # provides the listener referenced by the route, there is nothing for
        # observability bootstrap to manage.
        if gateway_listener_exists \
            "${gateway_name}" \
            "${gateway_namespace}" \
            "${listener_name}"; then
            echo "Gateway listener already present: ${gateway_namespace}/${gateway_name}:${listener_name}"
            continue
        fi

        listener_file="$(listener_file_for_section "${listener_name}" || true)"

        # Listener patches are optional. A route may intentionally reference a
        # listener owned by site configuration, or the listener may be created
        # later. Do not block route creation when no observability patch exists.
        if [[ -z "${listener_file}" ]]; then
            echo "WARNING: No observability listener patch found for ${gateway_namespace}/${gateway_name}:${listener_name}; applying the route without managing that listener."
            continue
        fi

        echo "Ensuring optional Gateway listener ${gateway_namespace}/${gateway_name}:${listener_name}"
        echo "  patch: ${listener_file}"

        ensure_gateway_listener \
            "${gateway_name}" \
            "${gateway_namespace}" \
            "${listener_file}"
    done < <(
        yq eval -r '
            .spec.parentRefs[]? |
            [
                (.name // ""),
                (.namespace // "envoy-gateway"),
                (.sectionName // "")
            ] |
            @tsv
        ' "${route_file}" 2>/dev/null || true
    )
}

apply_observability_routes() {
    local route_file
    local route_namespace
    local applied=0

    if gateway_config_mode_enabled; then
        echo "Envoy multi-gateway config mode detected; skipping legacy route apply."
        return 0
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        echo "WARNING: kubectl is not available; skipping observability route apply."
        return 0
    fi

    if ! kubectl get crd httproutes.gateway.networking.k8s.io \
        >/dev/null 2>&1; then
        echo "Gateway API HTTPRoute CRD is not installed; skipping observability route apply."
        return 0
    fi

    [[ -d "${GATEWAY_ROUTE_TARGET_DIR}" ]] || return 0

    while IFS= read -r -d '' route_file; do
        route_is_observability "${route_file}" || continue

        route_namespace="$(
            yq eval -r '.metadata.namespace // "default"' \
                "${route_file}" 2>/dev/null || true
        )"

        if ! kubectl get namespace "${route_namespace}" >/dev/null 2>&1; then
            echo "Route namespace ${route_namespace} does not exist yet; skipping:"
            echo "  ${route_file}"
            continue
        fi

        ensure_route_listeners "${route_file}"

        echo "Applying observability route: ${route_file}"
        kubectl apply -f "${route_file}"
        applied=$((applied + 1))
    done < <(
        find "${GATEWAY_ROUTE_TARGET_DIR}" \
            -maxdepth 1 \
            -type f \
            \( -name '*.yaml' -o -name '*.yml' \) \
            -print0 |
        sort -z
    )

    if [[ "${applied}" -eq 0 ]]; then
        echo "No observability Gateway API routes were applied."
    fi
}

ensure_monitoring_namespace_for_routes() {
    if ! command -v kubectl >/dev/null 2>&1; then
        return 0
    fi

    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        echo "Creating monitoring namespace before applying observability routes..."
        kubectl create namespace monitoring
    fi
}

if [[ "${MANAGE_ROUTES}" == "true" ]]; then
    echo
    echo "Preparing observability Gateway API routes..."
    seed_observability_routes

    # Some observability components, notably loki-rules, discover their endpoint
    # from an HTTPRoute during installation. Apply the routes before running the
    # component installer so a fresh bootstrap does not depend on routes that
    # would otherwise only be created after installation completes.
    ensure_monitoring_namespace_for_routes

    echo
    echo "Applying observability Gateway API routes before component installation..."
    apply_observability_routes
else
    echo "Skipping observability Gateway API routes (--no-routes)."
fi

echo
echo "Observability repository:"
echo "  ${GENESTACK_OBSERVABILITY_DIR}"
echo
echo "Genestack links:"
echo "  ${HELM_TARGET} -> $(readlink "${HELM_TARGET}")"
echo "  ${KUSTOMIZE_TARGET} -> $(readlink "${KUSTOMIZE_TARGET}")"
echo

if [[ "${RUN_INSTALL}" == "true" ]]; then
    INSTALL_SCRIPT="${GENESTACK_OBSERVABILITY_DIR}/bin/install-observability.sh"

    if [[ ! -x "${INSTALL_SCRIPT}" ]]; then
        echo "ERROR: Unified observability installer is missing or not executable:"
        echo "  ${INSTALL_SCRIPT}"
        exit 1
    fi

    "${INSTALL_SCRIPT}"

    if [[ "${MANAGE_ROUTES}" == "true" ]]; then
        echo
        echo "Reconciling observability Gateway API routes after component installation..."
        apply_observability_routes
    fi
else
    echo "Skipping observability installation (--no-install)."
fi
