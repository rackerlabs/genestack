#!/usr/bin/env bash
set -euo pipefail

RESOURCE="httproutes.gateway.networking.k8s.io"
SNAPSHOT_FILE=""
DRY_RUN=true
FORCE=false
LEGACY_GATEWAYS=("flex-gateway")

usage() {
    cat <<EOF
Usage:
  $0 snapshot --output FILE [--force]
  $0 cleanup --snapshot FILE [--legacy-gateway NAME] [--execute]

Capture and clean up HTTPRoutes during an Envoy Gateway cutover.

Commands:
  snapshot
      Capture all current HTTPRoutes before cutover.

  cleanup
      Delete pre-cutover HTTPRoutes that still exist with the same UID and still
      reference the legacy Gateway after cutover.

Options:
  -o, --output FILE
      Snapshot output path for the snapshot command.

  -f, --snapshot FILE
      Snapshot input path for the cleanup command.

  --legacy-gateway NAME
      Gateway name considered legacy. Can be specified more than once.
      Default: flex-gateway

  --execute
      Actually delete matching legacy routes. Without this flag, cleanup is a
      dry run.

  --force
      Overwrite an existing snapshot file.

Examples:
  $0 snapshot --output /etc/genestack/envoy-httproutes-before-cutover.json
  $0 cleanup --snapshot /etc/genestack/envoy-httproutes-before-cutover.json
  $0 cleanup --snapshot /etc/genestack/envoy-httproutes-before-cutover.json --execute
EOF
}

require_tools() {
    local missing=()

    for tool in kubectl jq; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing+=("${tool}")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Error: missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

legacy_gateways_json() {
    jq -cn '$ARGS.positional' --args "${LEGACY_GATEWAYS[@]}"
}

route_references_legacy_gateway() {
    local route_json="$1"
    local legacy_json="$2"

    jq -e --argjson legacy_gateways "${legacy_json}" '
        [.spec.parentRefs[]?.name] as $parent_names |
        any($parent_names[]?; . as $parent_name | any($legacy_gateways[]; . == $parent_name))
    ' <<< "${route_json}" >/dev/null
}

snapshot_routes() {
    local output_file="$1"
    local tmp_file

    if [ -z "${output_file}" ]; then
        echo "Error: snapshot requires --output FILE" >&2
        exit 1
    fi

    if [ -e "${output_file}" ] && [ "${FORCE}" != "true" ]; then
        echo "Error: snapshot file already exists: ${output_file}" >&2
        echo "Use --force to overwrite it." >&2
        exit 1
    fi

    tmp_file=$(mktemp)
    kubectl get "${RESOURCE}" -A -o json > "${tmp_file}"
    mv "${tmp_file}" "${output_file}"

    echo "Captured HTTPRoute snapshot: ${output_file}"
    jq -r '"Routes captured: \(.items | length)"' "${output_file}"
}

cleanup_routes() {
    local snapshot_file="$1"
    local legacy_json route
    local namespace name snapshot_uid current_json current_uid
    local examined=0 missing_count=0 recreated=0 not_legacy=0 skipped=0 deleted=0 matched=0

    if [ -z "${snapshot_file}" ]; then
        echo "Error: cleanup requires --snapshot FILE" >&2
        exit 1
    fi

    if [ ! -f "${snapshot_file}" ]; then
        echo "Error: snapshot file not found: ${snapshot_file}" >&2
        exit 1
    fi

    legacy_json=$(legacy_gateways_json)

    echo "Snapshot: ${snapshot_file}"
    echo "Legacy gateways: ${LEGACY_GATEWAYS[*]}"
    if [ "${DRY_RUN}" = "true" ]; then
        echo "Mode: dry run (use --execute to delete matching routes)"
    else
        echo "Mode: execute"
    fi
    echo

    while IFS= read -r route; do
        examined=$((examined + 1))

        if ! route_references_legacy_gateway "${route}" "${legacy_json}"; then
            skipped=$((skipped + 1))
            continue
        fi

        namespace=$(jq -r '.metadata.namespace' <<< "${route}")
        name=$(jq -r '.metadata.name' <<< "${route}")
        snapshot_uid=$(jq -r '.metadata.uid' <<< "${route}")

        if ! current_json=$(kubectl -n "${namespace}" get "${RESOURCE}" "${name}" -o json 2>/dev/null); then
            echo "SKIP missing: ${namespace}/${name}"
            missing_count=$((missing_count + 1))
            continue
        fi

        current_uid=$(jq -r '.metadata.uid' <<< "${current_json}")
        if [ "${current_uid}" != "${snapshot_uid}" ]; then
            echo "SKIP recreated: ${namespace}/${name}"
            recreated=$((recreated + 1))
            continue
        fi

        if ! route_references_legacy_gateway "${current_json}" "${legacy_json}"; then
            echo "SKIP no longer references legacy gateway: ${namespace}/${name}"
            not_legacy=$((not_legacy + 1))
            continue
        fi

        matched=$((matched + 1))
        if [ "${DRY_RUN}" = "true" ]; then
            echo "WOULD DELETE: ${namespace}/${name}"
        else
            echo "DELETE: ${namespace}/${name}"
            kubectl -n "${namespace}" delete "${RESOURCE}" "${name}"
            deleted=$((deleted + 1))
        fi
    done < <(jq -c '.items[]?' "${snapshot_file}")

    echo
    echo "Summary:"
    echo "  Examined: ${examined}"
    echo "  Matched legacy routes: ${matched}"
    echo "  Deleted: ${deleted}"
    echo "  Missing: ${missing_count}"
    echo "  Recreated with same name: ${recreated}"
    echo "  No longer legacy: ${not_legacy}"
    echo "  Skipped non-legacy snapshot routes: ${skipped}"
}

main() {
    local command="${1:-}"

    if [ -z "${command}" ] || [ "${command}" = "-h" ] || [ "${command}" = "--help" ]; then
        usage
        exit 0
    fi
    shift

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o|--output)
                SNAPSHOT_FILE="$2"
                shift 2
                ;;
            -f|--snapshot)
                SNAPSHOT_FILE="$2"
                shift 2
                ;;
            --legacy-gateway)
                if [ "${#LEGACY_GATEWAYS[@]}" -eq 1 ] && [ "${LEGACY_GATEWAYS[0]}" = "flex-gateway" ]; then
                    LEGACY_GATEWAYS=()
                fi
                LEGACY_GATEWAYS+=("$2")
                shift 2
                ;;
            --execute)
                DRY_RUN=false
                shift
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

    require_tools

    case "${command}" in
        snapshot)
            snapshot_routes "${SNAPSHOT_FILE}"
            ;;
        cleanup)
            cleanup_routes "${SNAPSHOT_FILE}"
            ;;
        *)
            echo "Error: unknown command: ${command}" >&2
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
