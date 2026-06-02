#!/usr/bin/env bash
# Show certificates and issuers for cert-manager

kubectl get certificates -A -o json |
jq -r '
  ["NAMESPACE","NAME","READY","ISSUER","DNS_NAMES"],
  (.items[]
    | select(.spec.issuerRef.name | startswith("letsencrypt"))
    | [
        .metadata.namespace,
        .metadata.name,
        ([.status.conditions[]? | select(.type=="Ready") | .status][0] // "Unknown"),
        .spec.issuerRef.name,
        (
          (.spec.dnsNames // []) as $d
          | if ($d|length) <= 3
            then ($d|join(","))
            else ($d[0:3]|join(",")) + ",...(" + (($d|length|tostring)) + " total)"
            end
        )
      ])
  | @tsv
' |
column -t -s $'\t'
