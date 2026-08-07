#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openstack}"
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: ${0##*/} [--dry-run] [-n NAMESPACE]

Options:
  --dry-run              Validate patches on the API server without
                         persisting them.
  -n, --namespace NAME   Kubernetes namespace. Default: openstack
  -h, --help             Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    -n|--namespace)
      shift

      if (($# == 0)); then
        echo "error: --namespace requires a value" >&2
        exit 2
      fi

      NAMESPACE=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac

  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd jq
require_cmd base64
require_cmd awk
require_cmd cut
require_cmd sort
require_cmd tr
require_cmd mktemp
require_cmd rm

if command -v sha256sum >/dev/null 2>&1; then
  sha256_hex() {
    sha256sum | awk '{print $1}'
  }
elif command -v shasum >/dev/null 2>&1; then
  sha256_hex() {
    shasum -a 256 | awk '{print $1}'
  }
elif command -v openssl >/dev/null 2>&1; then
  sha256_hex() {
    openssl dgst -sha256 | awk '{print $NF}'
  }
else
  echo "error: need sha256sum, shasum, or openssl" >&2
  exit 1
fi

strip_newlines() {
  local value=$1

  # Remove every LF and CR character, not merely the final one.
  value=${value//$'\n'/}
  value=${value//$'\r'/}

  printf '%s' "$value"
}

read_hidden() {
  local prompt=$1
  local value

  IFS= read -r -s -p "$prompt" value </dev/tty || {
    printf '\n' >/dev/tty
    return 1
  }

  printf '\n' >/dev/tty
  strip_newlines "$value"
}

umask 077

TMPDIR_ROTATE=$(
  mktemp -d "${TMPDIR:-/tmp}/rotate-secret-values.XXXXXX"
)

cleanup() {
  rm -rf "$TMPDIR_ROTATE"
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

old_password=$(read_hidden 'Old admin password: ')
new_password=$(read_hidden 'New admin password: ')
new_password_confirm=$(read_hidden 'Confirm new admin password: ')

if [[ -z $old_password ]]; then
  echo "error: old password is empty after removing CR/LF characters" >&2
  exit 1
fi

if [[ -z $new_password ]]; then
  echo "error: new password is empty after removing CR/LF characters" >&2
  exit 1
fi

if [[ $new_password != "$new_password_confirm" ]]; then
  echo "error: new passwords do not match" >&2
  exit 1
fi

if [[ $old_password == "$new_password" ]]; then
  echo "error: old and new passwords are identical" >&2
  exit 1
fi

old_sha=$(
  printf '%s' "$old_password" |
    sha256_hex
)

new_sha=$(
  printf '%s' "$new_password" |
    sha256_hex
)

old_b64=$(
  printf '%s' "$old_password" |
    base64 |
    tr -d '\r\n'
)

new_b64=$(
  printf '%s' "$new_password" |
    base64 |
    tr -d '\r\n'
)

# Keep sensitive comparison values in mode-0600 temporary files so they
# do not need to be placed in jq or kubectl command-line arguments.
printf '%s' "$old_b64" >"$TMPDIR_ROTATE/old.b64"
printf '%s' "$new_b64" >"$TMPDIR_ROTATE/new.b64"

unset old_password new_password new_password_confirm

if [[ $DRY_RUN == true ]]; then
  mode_description="DRY RUN (server-side)"
else
  mode_description="LIVE"
fi

cat <<SUMMARY

Namespace: $NAMESPACE
Mode:      $mode_description

Old password:
  SHA-256: $old_sha
  Base64:  $old_b64

New password:
  SHA-256: $new_sha
  Base64:  $new_b64
SUMMARY

# The requested values have been displayed. Remove the extra shell copies.
unset old_sha new_sha old_b64 new_b64 mode_description

snapshot="$TMPDIR_ROTATE/secrets-before.json"
matches="$TMPDIR_ROTATE/matches.tsv"
secret_names="$TMPDIR_ROTATE/secret-names.txt"

kubectl -n "$NAMESPACE" get secret -o json >"$snapshot"

# Record every .data key whose complete encoded value equals the encoded
# old password.
jq -r \
  --rawfile old "$TMPDIR_ROTATE/old.b64" '
    .items[]
    | .metadata.name as $name
    | (.data // {} | to_entries[])
    | select(.value == $old)
    | [$name, .key]
    | @tsv
  ' \
  "$snapshot" >"$matches"

match_count=$(awk 'END {print NR + 0}' "$matches")

if ((match_count == 0)); then
  echo
  echo "No Secret .data value exactly matched the encoded old password."
  echo "Nothing to do."
  exit 0
fi

cut -f1 "$matches" |
  LC_ALL=C sort -u >"$secret_names"

secret_count=$(awk 'END {print NR + 0}' "$secret_names")

echo
echo "Exact matches: $match_count field(s) in $secret_count Secret(s)"

while IFS=$'\t' read -r secret key; do
  printf '  secret/%s  .data[%s]\n' "$secret" "$key"
done <"$matches"

echo

if [[ $DRY_RUN == true ]]; then
  prompt="Proceed with server-side dry-run validation? [yes/no] "
else
  prompt="Proceed with modifying these fields? [yes/no] "
fi

IFS= read -r -p "$prompt" answer </dev/tty

case "$answer" in
  y|Y|yes|YES|Yes)
    ;;
  *)
    echo "Aborted; no changes made."
    exit 0
    ;;
esac

patch_failures=0
processed_secrets=0
patch_index=0

while IFS= read -r secret; do
  ((patch_index += 1))
  patch_file="$TMPDIR_ROTATE/patch-${patch_index}.json"

  # Generate one JSON Patch request per Secret. Each matching key gets:
  #
  #   1. A test requiring the live value to still equal the old value.
  #   2. A replacement with the new value.
  #
  # JSON Pointer escapes are included even though normal Secret key names
  # do not ordinarily contain "/" or "~".
  jq \
    --arg name "$secret" \
    --rawfile old "$TMPDIR_ROTATE/old.b64" \
    --rawfile new "$TMPDIR_ROTATE/new.b64" '
      .items[]
      | select(.metadata.name == $name)
      | [
          (
            .data // {}
            | to_entries[]
            | select(.value == $old)
            | .key
          ) as $key
          | (
              $key
              | gsub("~"; "~0")
              | gsub("/"; "~1")
            ) as $escaped
          | {
              op: "test",
              path: ("/data/" + $escaped),
              value: $old
            },
            {
              op: "replace",
              path: ("/data/" + $escaped),
              value: $new
            }
        ]
    ' \
    "$snapshot" >"$patch_file"

  if [[ $DRY_RUN == true ]]; then
    if kubectl -n "$NAMESPACE" patch secret "$secret" \
      --type=json \
      --patch-file="$patch_file" \
      --dry-run=server \
      -o name >/dev/null
    then
      echo "  validated: secret/$secret"
      ((processed_secrets += 1))
    else
      echo "  FAILED validation: secret/$secret" >&2
      ((patch_failures += 1))
    fi
  else
    if kubectl -n "$NAMESPACE" patch secret "$secret" \
      --type=json \
      --patch-file="$patch_file" \
      -o name >/dev/null
    then
      echo "  patched: secret/$secret"
      ((processed_secrets += 1))
    else
      echo "  FAILED patch: secret/$secret" >&2
      ((patch_failures += 1))
    fi
  fi
done <"$secret_names"

post_snapshot="$TMPDIR_ROTATE/secrets-after.json"

kubectl -n "$NAMESPACE" get secret -o json >"$post_snapshot"

verification_failures=0

if [[ $DRY_RUN == true ]]; then
  expected_file="$TMPDIR_ROTATE/old.b64"
  expected_label="old value, unchanged"
else
  expected_file="$TMPDIR_ROTATE/new.b64"
  expected_label="new value"
fi

echo
echo "Verification: originally matched fields should contain the $expected_label."

while IFS=$'\t' read -r secret key; do
  if jq -e \
    --arg name "$secret" \
    --arg key "$key" \
    --rawfile expected "$expected_file" '
      any(
        .items[];
        .metadata.name == $name
        and ((.data // {})[$key] // null) == $expected
      )
    ' \
    "$post_snapshot" >/dev/null
  then
    printf '  ok: secret/%s  .data[%s]\n' "$secret" "$key"
  else
    printf '  FAILED: secret/%s  .data[%s]\n' \
      "$secret" "$key" >&2
    ((verification_failures += 1))
  fi
done <"$matches"

remaining_old=$(
  jq \
    --rawfile old "$TMPDIR_ROTATE/old.b64" '
      [
        .items[]
        | (.data // {} | to_entries[])
        | select(.value == $old)
      ]
      | length
    ' \
    "$post_snapshot"
)

echo

if [[ $DRY_RUN == true ]]; then
  echo "Dry run complete: $processed_secrets Secret patch(es) validated."
  echo "No changes were persisted."
  echo "Exact old-value matches still present: $remaining_old"
else
  echo "Live run complete: $processed_secrets Secret(s) patched."
  echo "Exact old-value matches remaining: $remaining_old"
fi

if ((patch_failures > 0 || verification_failures > 0)); then
  echo "error: one or more patch or verification operations failed" >&2
  exit 1
fi

if [[ $DRY_RUN == false ]] && ((remaining_old > 0)); then
  echo "error: the old encoded value remains in one or more fields" >&2
  exit 1
fi
