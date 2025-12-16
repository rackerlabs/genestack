#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    cat <&0 > "${KUSTOMIZE_DIR}"/../base/all.yaml
    
    # Also copy it to the overlay directory so kustomize can reference it
    # This is needed because kustomize has security restrictions on file paths
    cp "${KUSTOMIZE_DIR}"/../base/all.yaml "${KUSTOMIZE_DIR}"/all.yaml
    
    kubectl kustomize "${KUSTOMIZE_DIR}"
popd &>/dev/null
