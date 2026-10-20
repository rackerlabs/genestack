#!/usr/bin/env bash

set -euo pipefail

GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
GENESTACK_OBSERVABILITY_DIR="${GENESTACK_OBSERVABILITY_DIR:-/opt/genestack-observability}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"

DEFAULT_COMPONENTS_FILE="${GENESTACK_OBSERVABILITY_DIR}/bin/observability-components.yaml"
SITE_COMPONENTS_FILE="${GENESTACK_CONFIG_DIR}/observability-components.yaml"

HELM_SITE_ROOT="${GENESTACK_CONFIG_DIR}/helm-configs/observability"
KUSTOMIZE_SITE_ROOT="${GENESTACK_CONFIG_DIR}/kustomize/observability"
KUSTOMIZE_RENDERER_SOURCE="${GENESTACK_DIR}/base-kustomize/kustomize.sh"
KUSTOMIZE_RENDERER_TARGET="${GENESTACK_CONFIG_DIR}/kustomize/kustomize.sh"

if [[ -n "${OBSERVABILITY_COMPONENTS_FILE:-}" ]]; then
    COMPONENTS_FILE="${OBSERVABILITY_COMPONENTS_FILE}"
elif [[ -f "${SITE_COMPONENTS_FILE}" ]]; then
    COMPONENTS_FILE="${SITE_COMPONENTS_FILE}"
else
    COMPONENTS_FILE="${DEFAULT_COMPONENTS_FILE}"
fi

usage() {
    cat <<EOF
Usage:
  $0
  $0 <component> [component...]
  $0 --list
  $0 -h|--help

Behavior:
  No component arguments:
    Install all components enabled in the component configuration, using
    install_order.

  One or more component arguments:
    Install only the named components, in the order provided. Explicitly
    requested components are installed even if disabled in the component
    configuration.

Examples:
  $0
  $0 loki
  $0 prometheus-rules loki-rules
  $0 grafana tempo
  $0 --list

Environment:
  GENESTACK_DIR
    Default: /opt/genestack

  GENESTACK_OBSERVABILITY_DIR
    Default: /opt/genestack-observability

  GENESTACK_CONFIG_DIR
    Default: /etc/genestack

  OBSERVABILITY_COMPONENTS_FILE
    Optional explicit component configuration file.
EOF
}

command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq is required but was not found in PATH."
    exit 1
}

if [[ ! -d "${GENESTACK_OBSERVABILITY_DIR}" ]]; then
    echo "ERROR: genestack-observability is not installed:"
    echo "  ${GENESTACK_OBSERVABILITY_DIR}"
    echo "Run bootstrap-observability.sh first."
    exit 1
fi

if [[ ! -f "${COMPONENTS_FILE}" ]]; then
    echo "ERROR: Observability components file not found:"
    echo "  ${COMPONENTS_FILE}"
    exit 1
fi

mapfile -t CONFIGURED_COMPONENTS < <(
    yq eval -r '.components | keys | .[]' "${COMPONENTS_FILE}"
)

mapfile -t INSTALL_ORDER < <(
    yq eval -r '.install_order[]' "${COMPONENTS_FILE}"
)

if [[ "${#CONFIGURED_COMPONENTS[@]}" -eq 0 ]]; then
    echo "ERROR: No components are defined in ${COMPONENTS_FILE}"
    exit 1
fi

if [[ "${#INSTALL_ORDER[@]}" -eq 0 ]]; then
    echo "ERROR: install_order is empty in ${COMPONENTS_FILE}"
    exit 1
fi

component_exists() {
    local requested="$1"
    local component

    for component in "${CONFIGURED_COMPONENTS[@]}"; do
        if [[ "${component}" == "${requested}" ]]; then
            return 0
        fi
    done

    return 1
}

component_enabled() {
    local component="$1"
    local enabled

    enabled="$(
        yq eval -r \
            ".components.\"${component}\" // false" \
            "${COMPONENTS_FILE}"
    )"

    [[ "${enabled}" == "true" ]]
}

component_script() {
    local component="$1"

    case "${component}" in
        monitoring-rgw-storage)
            printf '%s\n' \
                "${GENESTACK_OBSERVABILITY_DIR}/bin/setup-monitoring-rgw-storage.sh"
            ;;
        loki-rules)
            printf '%s\n' \
                "${GENESTACK_OBSERVABILITY_DIR}/bin/loki-sync-rules.sh"
            ;;
        *)
            printf '%s\n' \
                "${GENESTACK_OBSERVABILITY_DIR}/bin/install-${component}.sh"
            ;;
    esac
}

component_config_name() {
    local component="$1"

    case "${component}" in
        openstack-exporter)
            printf '%s\n' "openstack-api-exporter-chart"
            ;;
        *)
            printf '%s\n' "${component}"
            ;;
    esac
}

ensure_component_dependencies() {
    local component="$1"

    case "${component}" in
        loki-rules)
            if ! command -v lokitool >/dev/null 2>&1; then
                local installer="${GENESTACK_OBSERVABILITY_DIR}/bin/install-lokitool.sh"

                if [[ ! -x "${installer}" ]]; then
                    echo "ERROR: lokitool is required for loki-rules and the installer is missing:"
                    echo "  ${installer}"
                    exit 1
                fi

                echo "lokitool not found; installing the pinned version..."
                "${installer}"
            fi

            if ! command -v lokitool >/dev/null 2>&1; then
                echo "ERROR: lokitool installation completed but lokitool is still not available in PATH." >&2
                exit 1
            fi
            ;;
    esac
}

ensure_kustomize_renderer() {
    mkdir -p "${GENESTACK_CONFIG_DIR}/kustomize"

    if [[ -e "${KUSTOMIZE_RENDERER_TARGET}" || -L "${KUSTOMIZE_RENDERER_TARGET}" ]]; then
        return 0
    fi

    if [[ ! -f "${KUSTOMIZE_RENDERER_SOURCE}" ]]; then
        echo "ERROR: Genestack Kustomize post-renderer is missing:"
        echo "  ${KUSTOMIZE_RENDERER_SOURCE}"
        exit 1
    fi

    ln -s "${KUSTOMIZE_RENDERER_SOURCE}" "${KUSTOMIZE_RENDERER_TARGET}"
    echo "Created Kustomize post-renderer:"
    echo "  ${KUSTOMIZE_RENDERER_TARGET} -> ${KUSTOMIZE_RENDERER_SOURCE}"
}

ensure_component_site_config() {
    local component="$1"
    local config_name
    local helm_source
    local helm_target
    local kustomize_source
    local kustomize_target
    local kustomize_base_source
    local kustomize_base_target
    local kustomize_overlay_target

    config_name="$(component_config_name "${component}")"

    helm_source="${GENESTACK_OBSERVABILITY_DIR}/helm-configs/${config_name}"
    helm_target="${HELM_SITE_ROOT}/${config_name}"
    kustomize_source="${GENESTACK_OBSERVABILITY_DIR}/kustomize/${config_name}"
    kustomize_target="${KUSTOMIZE_SITE_ROOT}/${config_name}"
    kustomize_base_source="${kustomize_source}/base"
    kustomize_base_target="${kustomize_target}/base"
    kustomize_overlay_target="${kustomize_target}/overlay"

    mkdir -p "${HELM_SITE_ROOT}" "${KUSTOMIZE_SITE_ROOT}"

    if [[ -d "${helm_source}" ]]; then
        if [[ -e "${helm_target}" || -L "${helm_target}" ]]; then
            echo "Keeping existing Helm service configuration: ${helm_target}"
        else
            cp -a -- "${helm_source}" "${helm_target}"
            echo "Created Helm service configuration: ${helm_target}"
        fi
    fi

    if [[ -d "${kustomize_source}" ]]; then
        if [[ ! -e "${kustomize_target}" && ! -L "${kustomize_target}" ]]; then
            mkdir "${kustomize_target}"
            echo "Created Kustomize service directory: ${kustomize_target}"
        elif [[ ! -d "${kustomize_target}" ]]; then
            echo "WARNING: Existing Kustomize service path is not a directory; leaving it untouched:"
            echo "  ${kustomize_target}"
            ensure_kustomize_renderer
            return 0
        fi

        if [[ -d "${kustomize_base_source}" ]]; then
            if [[ -e "${kustomize_base_target}" || -L "${kustomize_base_target}" ]]; then
                echo "Keeping existing Kustomize base: ${kustomize_base_target}"
            else
                cp -a -- "${kustomize_base_source}" "${kustomize_base_target}"
                echo "Created Kustomize base: ${kustomize_base_target}"
            fi
        fi

        if [[ -e "${kustomize_overlay_target}" || -L "${kustomize_overlay_target}" ]]; then
            echo "Keeping existing Kustomize overlay: ${kustomize_overlay_target}"
        else
            mkdir "${kustomize_overlay_target}"
            cat > "${kustomize_overlay_target}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
EOF
            echo "Created Kustomize overlay: ${kustomize_overlay_target}"
        fi
    fi

    ensure_kustomize_renderer
}

list_components() {
    local component
    local state

    printf '%-32s %s\n' "COMPONENT" "ENABLED"
    printf '%-32s %s\n' "--------------------------------" "-------"

    for component in "${INSTALL_ORDER[@]}"; do
        if component_enabled "${component}"; then
            state="true"
        else
            state="false"
        fi

        printf '%-32s %s\n' "${component}" "${state}"
    done
}

install_component() {
    local component="$1"
    local script
    local config_name
    local kustomize_post_renderer_args

    if ! component_exists "${component}"; then
        echo "ERROR: Unknown observability component: ${component}"
        echo
        list_components
        exit 1
    fi

    script="$(component_script "${component}")"

    if [[ ! -x "${script}" ]]; then
        echo "ERROR: Component '${component}' has no executable implementation:"
        echo "  ${script}"
        exit 1
    fi

    ensure_component_dependencies "${component}"
    ensure_component_site_config "${component}"

    config_name="$(component_config_name "${component}")"
    kustomize_post_renderer_args="observability/${config_name}/overlay"

    echo
    echo "============================================================"
    echo "Installing observability component: ${component}"
    echo "Implementation: ${script}"
    echo "Configuration: ${config_name}"
    echo "============================================================"
    echo

    KUSTOMIZE_POST_RENDERER_ARGS="${kustomize_post_renderer_args}" \
        "${script}"
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --list)
            if [[ $# -ne 1 ]]; then
                echo "ERROR: --list cannot be combined with component names."
                exit 1
            fi

            list_components
            exit 0
            ;;
        --*)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
fi

echo "Genestack Observability"
echo "  Repository: ${GENESTACK_OBSERVABILITY_DIR}"
echo "  Components: ${COMPONENTS_FILE}"
echo

if [[ $# -gt 0 ]]; then
    echo "Installing explicitly requested component(s): $*"

    for component in "$@"; do
        install_component "${component}"
    done
else
    echo "Installing enabled components in configured install order."

    for component in "${INSTALL_ORDER[@]}"; do
        if ! component_enabled "${component}"; then
            echo "Skipping disabled observability component: ${component}"
            continue
        fi

        install_component "${component}"
    done
fi

echo
echo "Requested observability installation completed successfully."
