#!/usr/bin/env bash
set -e
pushd $(dirname "${BASH_SOURCE[0]}") &>/dev/null
    cat <&0 > ${1}/../base/all.yaml
    kubectl kustomize --reorder='none' ${1}
popd &>/dev/nulls
