#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    # Save helm output to a temporary file
    HELM_OUTPUT=$(mktemp)
    cat <&0 > "$HELM_OUTPUT"
    
    # Run kustomize on the overlay
    KUSTOMIZE_OUTPUT=$(kubectl kustomize "${KUSTOMIZE_DIR}")
    
    # Combine helm output and kustomize output
    # This ensures both the helm-generated resources and kustomize-processed resources are applied
    cat "$HELM_OUTPUT"
    echo "---"
    echo "$KUSTOMIZE_OUTPUT"
    
    # Cleanup
    rm -f "$HELM_OUTPUT"
popd &>/dev/null
