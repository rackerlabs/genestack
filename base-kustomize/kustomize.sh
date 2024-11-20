#!/usr/bin/env bash
set -e

clean_up() {
  test -d "$tmp_dir" && rm -rf "$tmp_dir"
}

tmp_dir=$(mktemp -d -t kustomize-XXXXXXXXXX)
trap "clean_up $tmp_dir" EXIT

KUSTOMIZE_DIR="${1:-$GENESTACK_KUSTOMIZE_ARG}"
pushd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null
    cat <&0 > "${KUSTOMIZE_DIR}"/../base/all.yaml
    cp -R "${KUSTOMIZE_DIR}"/../../base-images/"${2:-latest}"/* "${tmp_dir}"/
    kubectl kustomize "${KUSTOMIZE_DIR}" > "${tmp_dir}"/compiled.yaml
    kubectl kustomize "${tmp_dir}" | tee "${KUSTOMIZE_DIR}"/../base/.compiled-output  # for debugging
popd &>/dev/null
