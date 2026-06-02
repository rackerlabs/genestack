#!/usr/bin/env bash

set -u
set -o pipefail

NS="${NS:-cert-manager}"
RELEASE="${RELEASE:-cert-manager}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
TIMEOUT="${TIMEOUT:-300s}"

failed=0

fail() {
  echo "ERROR: $*" >&2
  failed=1
}

normalize_version() {
  case "$1" in
    v*) printf '%s\n' "$1" ;;
    *)  printf 'v%s\n' "$1" ;;
  esac
}

if [ -z "$EXPECTED_VERSION" ]; then
  fail "EXPECTED_VERSION must be set, for example EXPECTED_VERSION=v1.19.5"
else
  EXPECTED_VERSION="$(normalize_version "$EXPECTED_VERSION")"
fi

echo "== cmctl API check =="
if ! cmctl check api --wait=2m; then
  fail "cert-manager API check failed"
fi

echo
echo "== cert-manager version check =="

helm_json="$(
  helm -n "$NS" list --filter "^${RELEASE}$" -o json 2>/dev/null
)" || {
  helm_json="[]"
  fail "helm list failed for release ${RELEASE} in namespace ${NS}"
}

if echo "$helm_json" | jq -e 'length == 1' >/dev/null 2>&1; then
  echo "Helm release found. Checking Helm release version."

  echo "$helm_json" | jq -r '.[] | {name, namespace, revision, status, chart, app_version}'

  if [ -n "$EXPECTED_VERSION" ]; then
    if echo "$helm_json" | jq -e --arg v "$EXPECTED_VERSION" '
        (length == 1)
        and
        (
          .[0] as $r
          | ($r.status == "deployed")
            and
            (
              ($r.chart | endswith("-" + $v))
              or ($r.app_version == $v)
            )
        )
      ' >/dev/null 2>&1; then
      echo "Helm release is deployed and matches expected version: $EXPECTED_VERSION"
    else
      fail "Helm release is not deployed or does not match expected version: $EXPECTED_VERSION"
    fi
  fi
else
  echo "No Helm release found. Checking cert-manager Deployment image tag."

  controller_image="$(
    kubectl -n "$NS" get deployment cert-manager \
      -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}' 2>/dev/null \
      | awk '$1 == "cert-manager-controller" {print $2}'
  )" || controller_image=""

  if [ -z "$controller_image" ]; then
    fail "Could not determine cert-manager-controller image from deployment/cert-manager"
  else
    echo "cert-manager-controller image: $controller_image"

    if [ -n "$EXPECTED_VERSION" ]; then
      case "$controller_image" in
        *":$EXPECTED_VERSION")
          echo "Deployment image matches expected version: $EXPECTED_VERSION"
          ;;
        *)
          fail "Deployment image does not match expected version: $EXPECTED_VERSION; found image: $controller_image"
          ;;
      esac
    fi
  fi
fi

echo
echo "== Workload rollouts =="

for kind in deployment statefulset daemonset; do
  objects="$(kubectl -n "$NS" get "$kind" -o name 2>/dev/null)" || {
    fail "Could not list ${kind} objects in namespace ${NS}"
    continue
  }

  if [ -z "$objects" ]; then
    continue
  fi

  while IFS= read -r obj; do
    [ -z "$obj" ] && continue

    echo "Checking $obj"

    if ! kubectl -n "$NS" rollout status "$obj" --timeout="$TIMEOUT"; then
      fail "Rollout check failed for $obj"
    fi
  done <<EOF
$objects
EOF
done

echo
if [ "$failed" -eq 0 ]; then
  echo "All cert-manager upgrade gate checks passed"
else
  echo "One or more cert-manager upgrade gate checks failed" >&2
fi

exit "$failed"
