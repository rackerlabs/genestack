#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    cat <&0 > "${KUSTOMIZE_DIR}"/../base/all.yaml
    kubectl kustomize "${KUSTOMIZE_DIR}"
popd &>/dev/null
