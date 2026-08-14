#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openstack}"

IFS= read -r -s -p 'Admin password: ' password
printf '\n' >&2

if [[ -z $password ]]; then
    printf 'Password cannot be empty\n' >&2
    exit 1
fi

{
    printf '%s' "$password" | jq -Rs .
    kubectl -n "$NAMESPACE" get secrets -o json
} |
jq -n '
    # Convert a jq path array into an exact, reusable jq expression.
    #
    # ["data", "username"]    -> .data.username
    # ["data", "clouds.yaml"] -> .data["clouds.yaml"]
    # ["items", 0, "value"]   -> .items[0].value
    def jq_path:
        reduce .[] as $part (
            "";
            if ($part | type) == "number" then
                . + "[" + ($part | tostring) + "]"
            elif $part | test("^[A-Za-z_][A-Za-z0-9_]*$") then
                . + "." + $part
            else
                . + "[" + ($part | tojson) + "]"
            end
        );

    input as $needle
    | input
    | [
        .items[]
        | select(
            .kind == "Secret"
            and (.data? | type == "object")
          )
        | .data |= with_entries(.value |= @base64d)
        | . as $secret
        | {
            name: .metadata.name,
            list_of_paths_containing_the_string: [
                $secret.data
                | paths(scalars) as $path
                | select(
                    (getpath($path) | type) == "string"
                    and
                    (getpath($path) | contains($needle))
                  )
                | (["data"] + $path | jq_path)
            ]
          }
        | select(.list_of_paths_containing_the_string | length > 0)
      ]
'

unset password
