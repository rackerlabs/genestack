#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="qonos"
SERVICE_NAMESPACE="openstack"

GENESTACK_BASE_DIR="${GENESTACK_BASE_DIR:-/opt/genestack}"
GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
KUSTOMIZE_PATH="${GENESTACK_BASE_DIR}/base-kustomize/${SERVICE_NAME}/base"
QONOS_CONF_DEFAULT="${GENESTACK_BASE_DIR}/etc/qonos/qonos.conf"
QONOS_CONF_OVERRIDE="${GENESTACK_OVERRIDES_DIR}/qonos/qonos.conf"

resolve_qonos_conf() {
    if [ -f "${QONOS_CONF_OVERRIDE}" ]; then
        echo "${QONOS_CONF_OVERRIDE}"
        return 0
    fi

    if [ -f "${QONOS_CONF_DEFAULT}" ]; then
        echo "${QONOS_CONF_DEFAULT}"
        return 0
    fi

    echo "Error: qonos.conf not found. Looked for:" >&2
    echo "  ${QONOS_CONF_OVERRIDE}" >&2
    echo "  ${QONOS_CONF_DEFAULT}" >&2
    exit 1
}

require_secret() {
    local secret_name="$1"

    if ! kubectl --namespace "${SERVICE_NAMESPACE}" get secret "${secret_name}" >/dev/null 2>&1; then
        echo "Error: secret ${secret_name} not found in namespace ${SERVICE_NAMESPACE}" >&2
        echo "Run bin/create-secrets.sh and apply /etc/genestack/kubesecrets.yaml first." >&2
        exit 1
    fi
}

get_secret_password() {
    local secret_name="$1"

    kubectl --namespace "${SERVICE_NAMESPACE}" get secret "${secret_name}" \
        -o jsonpath='{.data.password}' | base64 -d
}

apply_qonos_etc_secret() {
    local conf_template="$1"
    local rendered_conf
    local qonos_db_password
    local qonos_rabbitmq_password
    local qonos_admin_password

    qonos_db_password="$(get_secret_password qonos-db-password)"
    qonos_rabbitmq_password="$(get_secret_password qonos-rabbitmq-password)"
    qonos_admin_password="$(get_secret_password qonos-admin)"

    rendered_conf="$(mktemp)"
    trap 'rm -f "${rendered_conf}"' RETURN

    sed \
        -e "s|__QONOS_DB_PASSWORD__|${qonos_db_password}|g" \
        -e "s|__QONOS_RABBITMQ_PASSWORD__|${qonos_rabbitmq_password}|g" \
        -e "s|__QONOS_ADMIN_PASSWORD__|${qonos_admin_password}|g" \
        "${conf_template}" > "${rendered_conf}"

    kubectl create secret generic qonos-etc \
        --namespace "${SERVICE_NAMESPACE}" \
        --from-file=qonos.conf="${rendered_conf}" \
        --dry-run=client -o yaml | kubectl apply -f -
}

if [ ! -f "${KUSTOMIZE_PATH}/kustomization.yaml" ]; then
    echo "Error: qonos kustomization not found at ${KUSTOMIZE_PATH}" >&2
    exit 1
fi

QONOS_CONF_PATH="$(resolve_qonos_conf)"

echo "Installing qonos from ${KUSTOMIZE_PATH}"
echo "Rendering qonos.conf from ${QONOS_CONF_PATH}"

require_secret "keystone-keystone-admin"
require_secret "qonos-db-password"
require_secret "qonos-rabbitmq-password"
require_secret "qonos-admin"

apply_qonos_etc_secret "${QONOS_CONF_PATH}"

kubectl --namespace "${SERVICE_NAMESPACE}" delete job qonos-ks-user qonos-db-sync --ignore-not-found=true

kubectl kustomize "${KUSTOMIZE_PATH}" | kubectl apply -f -

kubectl --namespace "${SERVICE_NAMESPACE}" wait \
    --for=condition=complete "job/qonos-ks-user" \
    --timeout=15m

kubectl --namespace "${SERVICE_NAMESPACE}" wait \
    --for=condition=complete "job/qonos-db-sync" \
    --timeout=15m

for deployment in qonos-api qonos-scheduler qonos-worker; do
    kubectl --namespace "${SERVICE_NAMESPACE}" rollout status "deployment/${deployment}" --timeout=15m
done

echo "qonos installed successfully"
