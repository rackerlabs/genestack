#!/usr/bin/env bash
set -e
pushd $(dirname "${BASH_SOURCE[0]}") &>/dev/null
    cat <&0 > all.yaml
    kubectl kustomize --reorder='none'
popd &>/dev/null
