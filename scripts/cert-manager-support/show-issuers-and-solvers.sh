#!/usr/bin/env bash
# Show issuers and solvers (like HTTP01 and DNS01) for config-manager

kubectl get clusterissuer -o json \
  | jq -r '
    .items[]
    | .metadata.name as $name
    | (.spec.acme.solvers // [])[]
    | if has("dns01") then
        "\($name)\tDNS01\t\(.dns01 | keys | join(","))"
      elif has("http01") then
        "\($name)\tHTTP01\t\(.http01 | keys | join(","))"
      else
        "\($name)\tUNKNOWN\t\(keys | join(","))"
      end
  ' \
  | column -t
