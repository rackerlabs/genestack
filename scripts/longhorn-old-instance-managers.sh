#!/usr/bin/env bash
set -euo pipefail

LH_NS="${LH_NS:-longhorn-system}"
VERSION_FILE="${VERSION_FILE:-/etc/genestack/helm-chart-versions.yaml}"
SEARCH="${SEARCH:-all}"

usage() {
  cat <<'EOF'
Usage: longhorn-old-instance-managers.sh [--search <term>]

Options:
  --search <term>  Filter rows by attached pod name. Use "all" to disable filtering.
  -h, --help       Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --search" >&2
        usage >&2
        exit 1
      fi
      SEARCH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "version file not found: $VERSION_FILE" >&2
  exit 1
fi

EXPECTED_VERSION="$(awk '/^[[:space:]]*longhorn:[[:space:]]*/{print $2; exit}' "$VERSION_FILE")"
EXPECTED_TAG="v${EXPECTED_VERSION#v}"

kubectl -n "$LH_NS" get engines.longhorn.io,volumes.longhorn.io,pods -o json | jq -r --arg expected "$EXPECTED_TAG" --arg search "$SEARCH" '
  (.items
   | map(select(.kind=="Pod" and (.metadata.name | startswith("instance-manager-"))))
   | map({
       key: .metadata.name,
       value: {
         image: (.spec.containers[0].image // ""),
         node: (.spec.nodeName // "-"),
         old: (((.spec.containers[0].image // "") | contains(":" + $expected)) | not)
       }
     })
   | from_entries) as $ims
  |
  (.items
   | map(select(.kind=="Volume"))
   | map({
       key: .metadata.name,
       value: {
         pvc_ns: (.status.kubernetesStatus.namespace // "-"),
         pvc_name: (.status.kubernetesStatus.pvcName // .metadata.name),
         pods: ((.status.kubernetesStatus.workloadsStatus // [])
           | map({
               ns: (.workloadNamespace // .podNamespace // "-"),
               pod: (.podName // .workloadName // "-")
             }))
       }
     })
   | from_entries) as $vols
  |
  ["PVC_NS","PVC","ATTACHED_POD_NS","ATTACHED_POD","LONGHORN_VOLUME","INSTANCE_MANAGER","INSTANCE_MANAGER_IMAGE","NODE"],
  (
    .items[]
    | select(.kind=="Engine" and .status.currentState=="running")
    | (.metadata.name | sub("-e-[0-9]+$"; "")) as $vol
    | .status.instanceManagerName as $im
    | select($im != null and ($ims[$im].old // false))
    | ($vols[$vol] // {pvc_ns:"-", pvc_name:$vol, pods:[]}) as $v
    | if ($v.pods | length) == 0 then
        [$v.pvc_ns, $v.pvc_name, "-", "-", $vol, $im, $ims[$im].image, (.spec.nodeID // $ims[$im].node // "-")]
      else
        $v.pods[]
        | [$v.pvc_ns, $v.pvc_name, .ns, .pod, $vol, $im, $ims[$im].image, (.spec.nodeID // $ims[$im].node // "-")]
      end
    | select(
        ($search == "all") or
        ((.[3] // "") | ascii_downcase | contains($search | ascii_downcase))
      )
  )
  | @tsv
' | column -t -s $'\t'
