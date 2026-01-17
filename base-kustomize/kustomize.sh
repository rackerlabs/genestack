#!/usr/bin/env bash
set -e
KUSTOMIZE_DIR=${1:-$GENESTACK_KUSTOMIZE_ARG}
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    # Read helm output from stdin
    HELM_OUTPUT=$(cat)
    
    # Check if the overlay directory exists
    if [ -d "${KUSTOMIZE_DIR}" ]; then
        # Run kustomize on the overlay
        KUSTOMIZE_OUTPUT=$(kubectl kustomize "${KUSTOMIZE_DIR}" 2>/dev/null || true)
        
        # If kustomize produced output, combine it with helm output
        if [ -n "$KUSTOMIZE_OUTPUT" ]; then
            echo "$HELM_OUTPUT"
            echo "---"
            echo "$KUSTOMIZE_OUTPUT"
        else
            # If kustomize failed or produced no output, just output helm
            echo "$HELM_OUTPUT"
        fi
    else
        # If overlay doesn't exist, just output helm
        echo "$HELM_OUTPUT"
    fi
popd &>/dev/null
