#!/usr/bin/env bash
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

kubectl -n openstack get secret clouds-yaml-secret -o json \
  | jq -r '.data["generated-clouds-yaml"] | @base64d' \
  > "$tmp"

chmod 600 "$tmp"

while :; do
  ${EDITOR:-vi} "$tmp"

  printf '\nPatch clouds-yaml-secret with this edited file? [y]es/[e]dit again/[n]o: '
  read -r answer

  case "$answer" in
    y|Y|yes|YES)
      break
      ;;
    e|E|edit|EDIT)
      continue
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

kubectl -n openstack patch secret clouds-yaml-secret \
  --type=merge \
  -p "$(jq -n \
    --arg value "$(base64 -w0 < "$tmp")" \
    '{"data":{"generated-clouds-yaml":$value}}'
  )"
