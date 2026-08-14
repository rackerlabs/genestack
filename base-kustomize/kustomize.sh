#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    all_yaml="${KUSTOMIZE_DIR}"/../base/all.yaml
    if grep -Eq '^[[:space:]]*-[[:space:]]+all\.yaml[[:space:]]*$' "${KUSTOMIZE_DIR}"/kustomization.yaml; then
        all_yaml="${KUSTOMIZE_DIR}"/all.yaml
    fi
    cat <&0 > "${all_yaml}"
    # Helm is typically invoked via sudo'd install scripts, which would leave
    # all.yaml root-owned inside a user-owned checkout (dev-mode labs rsync
    # /opt/genestack as the ssh user). Match the file's ownership to its
    # directory so unprivileged runs can overwrite it later.
    if [ "$(id -u)" -eq 0 ]; then
        chown --reference="$(dirname "${all_yaml}")" "${all_yaml}" 2>/dev/null || true
    fi
    kubectl kustomize "${KUSTOMIZE_DIR}"
popd &>/dev/null
