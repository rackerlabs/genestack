#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    all_yaml="${KUSTOMIZE_DIR}"/../base/all.yaml
    if grep -Eq '^[[:space:]]*-[[:space:]]+all\.yaml[[:space:]]*$' "${KUSTOMIZE_DIR}"/kustomization.yaml; then
        all_yaml="${KUSTOMIZE_DIR}"/all.yaml
    fi
    cat <&0 > "${all_yaml}"
    kubectl kustomize "${KUSTOMIZE_DIR}"
popd &>/dev/null
