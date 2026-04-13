#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/monitoring-common.sh"

ROOK_NAMESPACE="${ROOK_NAMESPACE:-rook-ceph}"
RGW_STORE_NAME="${RGW_STORE_NAME:-s3}"
RGW_TOOLBOX_DEPLOYMENT="${RGW_TOOLBOX_DEPLOYMENT:-rook-ceph-tools}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-monitoring}"
RGW_USER="${RGW_USER:-monitoring-telemetry}"
RGW_REGION="${RGW_REGION:-us-east-1}"
RGW_LOCAL_PORT="${RGW_LOCAL_PORT:-39000}"

LOKI_CHUNKS_BUCKET="${LOKI_CHUNKS_BUCKET:-loki-chunks}"
LOKI_RULER_BUCKET="${LOKI_RULER_BUCKET:-loki-ruler}"
LOKI_ADMIN_BUCKET="${LOKI_ADMIN_BUCKET:-loki-admin}"
TEMPO_BUCKET="${TEMPO_BUCKET:-tempo-traces}"

ROOK_SERVICE="rook-ceph-rgw-${RGW_STORE_NAME}"
ROOK_SERVICE_PORT="$(kubectl -n "${ROOK_NAMESPACE}" get svc "${ROOK_SERVICE}" -o jsonpath='{.spec.ports[0].port}')"

if [[ "${ROOK_SERVICE_PORT}" == "443" ]]; then
    RGW_SCHEME="https"
else
    RGW_SCHEME="http"
fi

RGW_ENDPOINT="${ROOK_SERVICE}.${ROOK_NAMESPACE}.svc.cluster.local:${ROOK_SERVICE_PORT}"
RGW_SECRET_NAME="monitoring-rgw-s3"

toolbox_exec() {
    kubectl -n "${ROOK_NAMESPACE}" exec deployment/"${RGW_TOOLBOX_DEPLOYMENT}" -- "$@"
}

detect_mc_url() {
    local os arch

    os="$(uname -s)"
    arch="$(uname -m)"

    case "${os}:${arch}" in
        Linux:x86_64)
            echo "https://dl.min.io/client/mc/release/linux-amd64/mc"
            ;;
        Linux:aarch64|Linux:arm64)
            echo "https://dl.min.io/client/mc/release/linux-arm64/mc"
            ;;
        Darwin:x86_64)
            echo "https://dl.min.io/client/mc/release/darwin-amd64/mc"
            ;;
        Darwin:arm64)
            echo "https://dl.min.io/client/mc/release/darwin-arm64/mc"
            ;;
        *)
            echo "Unsupported platform for mc download: ${os}:${arch}" >&2
            return 1
            ;;
    esac
}

ensure_mc() {
    if command -v mc >/dev/null 2>&1; then
        MC_BIN="$(command -v mc)"
        return 0
    fi

    local mc_url mc_dir
    mc_url="$(detect_mc_url)"
    mc_dir="$(mktemp -d)"
    MC_BIN="${mc_dir}/mc"
    curl -fsSL "${mc_url}" -o "${MC_BIN}"
    chmod +x "${MC_BIN}"
}

start_port_forward() {
    local log_file

    log_file="$(mktemp)"
    kubectl -n "${ROOK_NAMESPACE}" port-forward svc/"${ROOK_SERVICE}" "${RGW_LOCAL_PORT}:${ROOK_SERVICE_PORT}" >"${log_file}" 2>&1 &
    PORT_FORWARD_PID=$!

    for _ in $(seq 1 30); do
        if grep -q "Forwarding from" "${log_file}" 2>/dev/null; then
            rm -f "${log_file}"
            return 0
        fi
        sleep 1
    done

    cat "${log_file}" >&2 || true
    rm -f "${log_file}"
    return 1
}

create_buckets_with_mc() {
    ensure_mc
    start_port_forward

    "${MC_BIN}" alias set monitoring-rgw "http://127.0.0.1:${RGW_LOCAL_PORT}" "${RGW_ACCESS_KEY_ID}" "${RGW_SECRET_ACCESS_KEY}" >/dev/null
    "${MC_BIN}" mb --ignore-existing "monitoring-rgw/${LOKI_CHUNKS_BUCKET}" >/dev/null
    "${MC_BIN}" mb --ignore-existing "monitoring-rgw/${LOKI_RULER_BUCKET}" >/dev/null
    "${MC_BIN}" mb --ignore-existing "monitoring-rgw/${LOKI_ADMIN_BUCKET}" >/dev/null
    "${MC_BIN}" mb --ignore-existing "monitoring-rgw/${TEMPO_BUCKET}" >/dev/null
}

create_rgw_user() {
    local user_json

    if user_json="$(toolbox_exec radosgw-admin user info --uid "${RGW_USER}" --format json 2>/dev/null)"; then
        printf '%s\n' "${user_json}"
        return 0
    fi

    toolbox_exec radosgw-admin user create \
        --uid "${RGW_USER}" \
        --display-name "${RGW_USER}" \
        --format json
}

write_override_files() {
    mkdir -p \
        "${GENESTACK_OVERRIDES_DIR}/helm-configs/loki" \
        "${GENESTACK_OVERRIDES_DIR}/helm-configs/tempo"

    cat > "${GENESTACK_OVERRIDES_DIR}/helm-configs/loki/20-rook-rgw-overrides.yaml" <<EOF
---
loki:
  storage:
    bucketNames:
      chunks: ${LOKI_CHUNKS_BUCKET}
      ruler: ${LOKI_RULER_BUCKET}
      admin: ${LOKI_ADMIN_BUCKET}
    type: s3
    s3:
      endpoint: ${RGW_ENDPOINT}
      region: ${RGW_REGION}
      accessKeyId: ${RGW_ACCESS_KEY_ID}
      secretAccessKey: ${RGW_SECRET_ACCESS_KEY}
      s3ForcePathStyle: true
      insecure: true
  schemaConfig:
    configs:
      - from: 2024-04-01
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: index_
          period: 24h
EOF

    cat > "${GENESTACK_OVERRIDES_DIR}/helm-configs/tempo/20-rook-rgw-overrides.yaml" <<EOF
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: ${TEMPO_BUCKET}
        endpoint: ${RGW_ENDPOINT}
        access_key: ${RGW_ACCESS_KEY_ID}
        secret_key: ${RGW_SECRET_ACCESS_KEY}
        insecure: true
EOF
}

monitoring_ensure_namespace "${TARGET_NAMESPACE}"
monitoring_label_namespace_for_talos "${TARGET_NAMESPACE}"

RGW_USER_JSON="$(create_rgw_user)"
RGW_ACCESS_KEY_ID="$(
    USER_JSON="${RGW_USER_JSON}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["USER_JSON"])
print(data["keys"][0]["access_key"])
PY
)"
RGW_SECRET_ACCESS_KEY="$(
    USER_JSON="${RGW_USER_JSON}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["USER_JSON"])
print(data["keys"][0]["secret_key"])
PY
)"

trap '[[ -n "${PORT_FORWARD_PID:-}" ]] && kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true; [[ -n "${MC_BIN:-}" && "${MC_BIN}" == /tmp/* ]] && rm -f "${MC_BIN}" >/dev/null 2>&1 || true' EXIT

create_buckets_with_mc

kubectl create secret generic "${RGW_SECRET_NAME}" \
    --namespace "${TARGET_NAMESPACE}" \
    --from-literal=endpoint="${RGW_ENDPOINT}" \
    --from-literal=region="${RGW_REGION}" \
    --from-literal=accessKeyId="${RGW_ACCESS_KEY_ID}" \
    --from-literal=secretAccessKey="${RGW_SECRET_ACCESS_KEY}" \
    --from-literal=lokiChunksBucket="${LOKI_CHUNKS_BUCKET}" \
    --from-literal=lokiRulerBucket="${LOKI_RULER_BUCKET}" \
    --from-literal=lokiAdminBucket="${LOKI_ADMIN_BUCKET}" \
    --from-literal=tempoBucket="${TEMPO_BUCKET}" \
    --dry-run=client -o yaml | kubectl apply -f -

write_override_files

echo "Configured Rook RGW storage for monitoring."
echo "Secret: ${TARGET_NAMESPACE}/${RGW_SECRET_NAME}"
echo "Loki overrides: ${GENESTACK_OVERRIDES_DIR}/helm-configs/loki/20-rook-rgw-overrides.yaml"
echo "Tempo overrides: ${GENESTACK_OVERRIDES_DIR}/helm-configs/tempo/20-rook-rgw-overrides.yaml"
