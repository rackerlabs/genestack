#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openstack}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd jq
require_cmd yq
require_cmd base64
require_cmd tr
require_cmd mktemp
require_cmd rm

umask 077

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/edit-clouds-yaml-secret.XXXXXX")
secret_json="$tmpdir/secret.json"
tmp="$tmpdir/clouds.yaml"

cleanup() {
  rm -rf "$tmpdir"
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

kubectl -n "$NAMESPACE" get secret clouds-yaml-secret -o json >"$secret_json"

keys_json=$(
  jq -c '
    [
      (.data // {} | keys[])
      | select(
          . == "generated-clouds-yaml"
          or . == "generated-clouds-certs-yaml"
        )
    ]
  ' "$secret_json"
)
key_count=$(jq -r 'length' <<<"$keys_json")

if ((key_count == 0)); then
  echo "error: secret/clouds-yaml-secret has neither supported data key:" >&2
  echo "  generated-clouds-yaml" >&2
  echo "  generated-clouds-certs-yaml" >&2
  exit 1
fi

if ((key_count > 1)); then
  echo "error: secret/clouds-yaml-secret has both supported data keys;" >&2
  echo "refusing to guess which one os-metrics consumes" >&2
  exit 1
fi

key=$(jq -r '.[0]' <<<"$keys_json")
encoded_before=$(jq -er --arg key "$key" '.data[$key]' "$secret_json")

printf '%s' "$encoded_before" | base64 --decode >"$tmp"

if [[ ! -s $tmp ]]; then
  echo "error: extracted secret data is empty; aborting" >&2
  exit 1
fi

echo "Editing secret/clouds-yaml-secret .data[$key] in namespace $NAMESPACE."

while :; do
  ${EDITOR:-vi} "$tmp"

  if [[ ! -s $tmp ]]; then
    echo "error: edited file is empty; edit it again or abort" >&2
    continue
  fi

  if ! yq '.' "$tmp" >/dev/null; then
    echo "error: edited file is not valid YAML; edit it again or abort" >&2
    continue
  fi

  while :; do
    printf '\nPatch clouds-yaml-secret with this edited file? [y]es/[e]dit again/[n]o: '
    read -r answer

    case "$answer" in
      y|Y|yes|YES)
        break
        ;;
      e|E|edit|EDIT)
        break
        ;;
      n|N|no|NO|'')
        echo "Aborted; secret was not changed."
        exit 0
        ;;
      *)
        echo "Please answer y, e, or n."
        ;;
    esac
  done

  case "$answer" in
    y|Y|yes|YES)
      break
      ;;
  esac
done

encoded=$(base64 <"$tmp" | tr -d '\r\n')
patch_file="$tmpdir/patch.json"
encoded_before_file="$tmpdir/encoded-before"
encoded_after_file="$tmpdir/encoded-after"
printf '%s' "$encoded_before" >"$encoded_before_file"
printf '%s' "$encoded" >"$encoded_after_file"

jq -n \
  --arg path "/data/$key" \
  --rawfile before "$encoded_before_file" \
  --rawfile after "$encoded_after_file" '
    [
      {
        op: "test",
        path: $path,
        value: $before
      },
      {
        op: "replace",
        path: $path,
        value: $after
      }
    ]
  ' >"$patch_file"

kubectl -n "$NAMESPACE" patch secret clouds-yaml-secret \
  --type=json \
  --patch-file="$patch_file"
