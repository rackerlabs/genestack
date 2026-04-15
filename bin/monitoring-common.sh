#!/bin/bash

set -euo pipefail

GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"

monitoring_generate_password() {
    < /dev/urandom tr -dc _A-Za-z0-9 | head -c"${1:-32}"
}

monitoring_load_provider() {
    if [[ -z "${K8S_PROVIDER:-}" ]] && [[ -f "${GENESTACK_OVERRIDES_DIR}/provider" ]]; then
        K8S_PROVIDER=$(head -n1 "${GENESTACK_OVERRIDES_DIR}/provider")
    fi

    export K8S_PROVIDER="${K8S_PROVIDER:-kubespray}"
}

monitoring_ensure_namespace() {
    local namespace="${1:-monitoring}"

    if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
        kubectl create namespace "${namespace}"
    fi
}

monitoring_label_namespace_for_talos() {
    local namespace="${1:-monitoring}"

    monitoring_load_provider

    if [[ "${K8S_PROVIDER}" == "talos" ]]; then
        kubectl label namespace "${namespace}" \
            pod-security.kubernetes.io/enforce=privileged \
            pod-security.kubernetes.io/enforce-version=latest \
            pod-security.kubernetes.io/warn=privileged \
            pod-security.kubernetes.io/warn-version=latest \
            pod-security.kubernetes.io/audit=privileged \
            pod-security.kubernetes.io/audit-version=latest \
            --overwrite
    fi
}

monitoring_apply_secret_from_kubesecrets() {
    local secret_name="$1"
    local source_namespace="$2"
    local target_namespace="${3:-$2}"
    local kubesecrets_file="${GENESTACK_OVERRIDES_DIR}/kubesecrets.yaml"
    local secret_manifest

    if [[ ! -f "${kubesecrets_file}" ]]; then
        return 1
    fi

    secret_manifest=$(
        SECRET_NAME="${secret_name}" \
        SECRET_NAMESPACE="${source_namespace}" \
        yq eval-all '
            select(
                .kind == "Secret" and
                .metadata.name == strenv(SECRET_NAME) and
                .metadata.namespace == strenv(SECRET_NAMESPACE)
            )
        ' "${kubesecrets_file}"
    )

    if [[ -z "${secret_manifest}" || "${secret_manifest}" == "null" ]]; then
        return 1
    fi

    TARGET_NAMESPACE="${target_namespace}" yq eval '
        del(
            .metadata.creationTimestamp,
            .metadata.managedFields,
            .metadata.ownerReferences,
            .metadata.resourceVersion,
            .metadata.selfLink,
            .metadata.uid,
            .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
        ) |
        .metadata.namespace = strenv(TARGET_NAMESPACE)
    ' - <<< "${secret_manifest}" | kubectl apply -f -
}

monitoring_copy_secret_between_namespaces() {
    local secret_name="$1"
    local source_namespace="$2"
    local target_namespace="$3"

    kubectl -n "${source_namespace}" get secret "${secret_name}" -o yaml \
        | TARGET_NAMESPACE="${target_namespace}" yq eval '
            del(
                .metadata.creationTimestamp,
                .metadata.managedFields,
                .metadata.ownerReferences,
                .metadata.resourceVersion,
                .metadata.selfLink,
                .metadata.uid,
                .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
            ) |
            .metadata.namespace = strenv(TARGET_NAMESPACE)
        ' - \
        | kubectl apply -f -
}

monitoring_ensure_grafana_db_secret() {
    if kubectl -n monitoring get secret grafana-db >/dev/null 2>&1; then
        return 0
    fi

    if monitoring_apply_secret_from_kubesecrets "grafana-db" "monitoring" "monitoring"; then
        return 0
    fi

    if monitoring_apply_secret_from_kubesecrets "grafana-db" "grafana" "monitoring"; then
        return 0
    fi

    kubectl create secret generic grafana-db \
        --namespace monitoring \
        --type Opaque \
        --from-literal=password="$(monitoring_generate_password 32)" \
        --from-literal=root-password="$(monitoring_generate_password 32)" \
        --from-literal=username=grafana \
        --dry-run=client -o yaml | kubectl apply -f -
}

monitoring_ensure_mariadb_monitoring_secret() {
    if ! kubectl -n openstack get secret mariadb-monitoring >/dev/null 2>&1; then
        if ! monitoring_apply_secret_from_kubesecrets "mariadb-monitoring" "openstack" "openstack"; then
            kubectl create secret generic mariadb-monitoring \
                --namespace openstack \
                --type Opaque \
                --from-literal=username=monitoring \
                --from-literal=password="$(monitoring_generate_password 32)" \
                --dry-run=client -o yaml | kubectl apply -f -
        fi
    fi

    monitoring_copy_secret_between_namespaces "mariadb-monitoring" "openstack" "monitoring"
}

monitoring_ensure_rabbitmq_monitoring_secret() {
    if ! kubectl -n openstack get secret rabbitmq-monitoring-user >/dev/null 2>&1; then
        if ! monitoring_apply_secret_from_kubesecrets "rabbitmq-monitoring-user" "openstack" "openstack"; then
            kubectl create secret generic rabbitmq-monitoring-user \
                --namespace openstack \
                --type Opaque \
                --from-literal=username=monitoring \
                --from-literal=password="$(monitoring_generate_password 32)" \
                --dry-run=client -o yaml | kubectl apply -f -
        fi
    fi

    monitoring_copy_secret_between_namespaces "rabbitmq-monitoring-user" "openstack" "monitoring"
}

monitoring_ensure_postgres_monitoring_secret() {
    if ! kubectl -n postgres-system get secret postgres-monitoring >/dev/null 2>&1; then
        if ! monitoring_apply_secret_from_kubesecrets "postgres-monitoring" "postgres-system" "postgres-system"; then
            kubectl create secret generic postgres-monitoring \
                --namespace postgres-system \
                --type Opaque \
                --from-literal=memberof=pg_monitor \
                --from-literal=username=postgres-monitoring-user \
                --from-literal=password="$(monitoring_generate_password 32)" \
                --dry-run=client -o yaml | kubectl apply -f -
        fi
    fi

    monitoring_copy_secret_between_namespaces "postgres-monitoring" "postgres-system" "monitoring"
}
