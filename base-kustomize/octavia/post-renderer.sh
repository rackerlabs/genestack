#!/usr/bin/env bash
set -euo pipefail

GENESTACK_OVERRIDES_DIR="${GENESTACK_OVERRIDES_DIR:-/etc/genestack}"
KUSTOMIZE_POST_RENDERER="${GENESTACK_OVERRIDES_DIR}/kustomize/kustomize.sh"

rendered_manifest=$(mktemp)
trap 'rm -f "$rendered_manifest"' EXIT
"$KUSTOMIZE_POST_RENDERER" "$@" > "$rendered_manifest"

if [[ "${GENESTACK_KUBE_OVN_ENABLE_SSL:-false}" != "true" ]]; then
    yq eval '
      del(.spec.template.spec.containers[].volumeMounts[]
        | select(.name == "ovn-tls"))
      | del(.spec.template.spec.volumes[]
        | select(.name == "ovn-tls"))
    ' "$rendered_manifest"
    exit 0
fi

if ! yq eval-all -e '
  [.
    | select(.kind == "Deployment" and .metadata.name == "octavia-api")
    | .spec.template.spec.containers[]
    | select(.name == "octavia-agent")]
  | length == 1
' "$rendered_manifest" >/dev/null; then
    echo "Error: Unable to find the Octavia OVN driver-agent sidecar in the rendered manifest." >&2
    exit 1
fi

if ! yq eval-all -e '
  [.
    | select(.kind == "Deployment" and .metadata.name == "octavia-api")
    | .spec.template.spec.volumes[]
    | select(.name == "ovn-tls" and .secret.secretName == "ovn-client-tls")]
  | length == 1
' "$rendered_manifest" >/dev/null; then
    echo "Error: Unable to find the Octavia OVN TLS secret volume in the rendered manifest." >&2
    exit 1
fi

yq eval '
  (select(.kind == "Deployment" and .metadata.name == "octavia-api")
    .spec.template.spec.containers[]
    | select(.name == "octavia-agent")
    .volumeMounts) += [{
      "name": "ovn-tls",
      "mountPath": "/etc/octavia/ovn",
      "readOnly": true
    }]
' "$rendered_manifest"
