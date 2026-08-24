#!/usr/bin/env bash
# -----------------------------------------------
#                             _             _
#                            | |           | |
#   __ _  ___ _ __   ___  ___| |_ __ _  ___| | __
#  / _` |/ _ \ '_ \ / _ \/ __| __/ _` |/ __| |/ /
# | (_| |  __/ | | |  __/\__ \ || (_| | (__|   <
#  \__, |\___|_| |_|\___||___/\__\__,_|\___|_|\_\
#   __/ |           ops scripts
#  |___/
# -----------------------------------------------
# tc-offload-audit.sh
#
# READ-ONLY audit of every node that runs an ovs-ovn pod.
#
# For each node it collects, via "kubectl exec" into the ovs-ovn pod (which
# shares the host network namespace):
#
#   - the kube-ovn HW_OFFLOAD env value on the pod
#   - the OVS other_config:hw-offload setting
#   - the count of live OVS TC datapath flows (dpctl/dump-flows type=tc)
#   - the number of ingress/clsact qdiscs on host devices
#   - TC "flower" filter counts per shared ingress block and per device,
#     reported as chain0/total (chain 0 holds the live interception points;
#     the total includes unreachable residual chains)
#   - host uptime and Genestack role labels
#
# and assigns one verdict per node:
#
#   SOURCE-STATE   hw-offload is true and OVS has live TC flows. TC flower
#                  is the live datapath. Expected before the maintenance.
#   ORPHANED-LIVE  hw-offload is false, zero live TC flows, but chain-0
#                  flower filters remain. Stranded filters still intercept
#                  traffic. NEEDS CLEANUP.
#   RESIDUAL-ONLY  hw-offload is false, zero live TC flows, chain 0 is
#                  clear. Only inert leftovers remain. Acceptable.
#   CLEAN          hw-offload is false, zero live TC flows, and no ingress
#                  qdiscs at all. The post-reboot state.
#   UNREACHABLE    kubectl exec failed for the node's pod.
#   REVIEW         any other combination, for example hw-offload true with
#                  zero TC flows. Investigate.
#
# The script makes NO changes anywhere. Safe to run at any time.
#
# Usage:
#   bash /opt/genestack/scripts/tc-offload-audit.sh
#
# Environment overrides:
#   P    parallel kubectl execs (default 8)
#   OUT  output TSV path (default ~/maint/tc-offload-audit-<date>.tsv)
#
# Exit status:
#   0  no node needs attention
#   2  at least one node is UNREACHABLE, ORPHANED-LIVE, or REVIEW
#
# Intended use: pre/post audit and fleet gate for kube-ovn HW_OFFLOAD=false
# maintenances. Run before the change to record the source state, and after
# the per-node TC cleanup to verify no node remains ORPHANED-LIVE before
# any OpenStack service upgrade proceeds.
#
# shellcheck disable=SC2016,SC2086
set -u
set -o pipefail

P="${P:-8}"
OUT="${OUT:-$HOME/maint/tc-offload-audit-$(date +%F-%H%M).tsv}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LABELS_FILE="$TMP/labels.tsv"    # <node> <tab> <role labels>
PODS_FILE="$TMP/pods.tsv"        # <pod> <tab> <node> <tab> <HW_OFFLOAD env>
RESULTS_FILE="$TMP/results.tsv"  # one audit line per node, unsorted

# ---------------------------------------------------------------------------
# The collector below runs INSIDE each ovs-ovn pod (openvswitch container,
# host network namespace, tc and ovs tools present). It is read-only.
#
# It prints a single line of six pipe-separated fields:
#
#   hw_offload | live_tc_flows | ingress_qdisc_count | blocks | devices | uptime
#
# where "blocks" is a space-separated list like "block8=617/653" and
# "devices" is a space-separated list like "genev_sys_6081=152/279",
# each value being <chain-0 flower count>/<total flower count>.
# ---------------------------------------------------------------------------
export COLLECTOR='
hw=$(ovs-vsctl get Open_vSwitch . other_config:hw-offload 2>/dev/null | tr -d "\"")
if [ -z "$hw" ]; then
  hw=unset
fi

live_flows=$(ovs-appctl dpctl/dump-flows type=tc 2>/dev/null | wc -l | tr -d " ")

qdisc_count=$(tc qdisc show | grep -cE "^qdisc (ingress|clsact)")

# Flower filter counts on each shared ingress block (bond slaves).
blocks=""
for block_id in $(tc qdisc show | grep -oP "ingress_block \K\d+" | sort -un); do
  chain0=$(tc filter show block $block_id chain 0 2>/dev/null | grep -c "^filter.*flower")
  total=$(tc filter show block $block_id 2>/dev/null | grep -c "^filter.*flower")
  blocks="${blocks:+$blocks }block$block_id=$chain0/$total"
done

# Flower filter counts on each per-device ingress qdisc (geneve, taps,
# pod veths). Devices with no flower filters are omitted.
devices=""
for dev in $(tc qdisc show | grep -E "^qdisc (ingress|clsact)" | grep -v ingress_block | awk "{print \$5}"); do
  total=$(tc filter show dev $dev ingress 2>/dev/null | grep -c "^filter.*flower")
  if [ "$total" -gt 0 ]; then
    chain0=$(tc filter show dev $dev ingress chain 0 2>/dev/null | grep -c "^filter.*flower")
    devices="${devices:+$devices }$dev=$chain0/$total"
  fi
done

uptime_days=$(awk "{printf \"%dd\", \$1/86400}" /proc/uptime)

echo "$hw|$live_flows|$qdisc_count|${blocks:-none}|${devices:-none}|$uptime_days"'

# ---------------------------------------------------------------------------
# gather_node_labels
#   Writes LABELS_FILE: one line per node with its Genestack role labels
#   (compute, storage, control, network) or NOLABEL. jsonpath is used so
#   that empty label values do not shift columns.
# ---------------------------------------------------------------------------
gather_node_labels() {
  local jsonpath
  jsonpath='{range .items[*]}{.metadata.name}{"\t"}'
  jsonpath+='{.metadata.labels.openstack-compute-node}{"\t"}'
  jsonpath+='{.metadata.labels.openstack-storage-node}{"\t"}'
  jsonpath+='{.metadata.labels.openstack-control-plane}{"\t"}'
  jsonpath+='{.metadata.labels.openstack-network-node}{"\n"}{end}'

  if ! kubectl get nodes -o jsonpath="$jsonpath" > "$TMP/nodes.raw"; then
    echo "kubectl get nodes failed; cannot gather role labels" >&2
    exit 1
  fi

  awk -F'\t' '
        {
          labels = ""
          if ($2 == "enabled") labels = labels "compute,"
          if ($3 == "enabled") labels = labels "storage,"
          if ($4 == "enabled") labels = labels "control,"
          if ($5 == "enabled") labels = labels "network,"
          sub(/,$/, "", labels)
          if (labels == "") labels = "NOLABEL"
          print $1 "\t" labels
        }' "$TMP/nodes.raw" > "$LABELS_FILE"
}

# ---------------------------------------------------------------------------
# gather_ovs_pods
#   Writes PODS_FILE: one line per ovs-ovn pod with its node and its
#   HW_OFFLOAD env value. Pods are selected by name prefix because label
#   sets vary between kube-ovn chart versions.
# ---------------------------------------------------------------------------
gather_ovs_pods() {
  local jsonpath
  jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}'
  jsonpath+='{.spec.containers[0].env[?(@.name=="HW_OFFLOAD")].value}{"\n"}{end}'

  if ! kubectl -n kube-system get pods -o jsonpath="$jsonpath" > "$TMP/pods.raw"; then
    echo "kubectl get pods failed; cannot enumerate ovs-ovn pods" >&2
    exit 1
  fi

  awk -F'\t' '$1 ~ /^ovs-ovn-/' "$TMP/pods.raw" > "$PODS_FILE"

  if [ ! -s "$PODS_FILE" ]; then
    echo "no ovs-ovn pods found in kube-system" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# audit_one_node <pod> <node> [env]
#   Runs the collector inside the node's ovs-ovn pod, assigns a verdict,
#   and prints one tab-separated result line. Exported for xargs workers.
# ---------------------------------------------------------------------------
audit_one_node() {
  local pod="$1"
  local node="$2"
  local env_value="${3:-unset}"

  local raw
  raw=$(echo "$COLLECTOR" \
        | timeout 120 kubectl -n kube-system exec -i "$pod" -c openvswitch -- bash -s 2>/dev/null)
  if [ -z "$raw" ]; then
    raw="EXEC-FAILED|?|?|?|?|?"
  fi

  local hw live_flows qdisc_count blocks devices uptime_days
  IFS='|' read -r hw live_flows qdisc_count blocks devices uptime_days <<< "$raw"

  # Highest chain-0 flower count seen on any block or device. A value
  # above zero means live interception points remain.
  local chain0_max=0
  local entry value
  for entry in $blocks $devices; do
    value="${entry#*=}"      # strip "name=" prefix
    value="${value%%/*}"     # keep the chain-0 half of chain0/total
    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt "$chain0_max" ]; then
      chain0_max="$value"
    fi
  done

  local verdict
  if [ "$hw" = "EXEC-FAILED" ]; then
    verdict="UNREACHABLE"
  elif [ "$hw" = "true" ] && [ "$live_flows" != "0" ]; then
    verdict="SOURCE-STATE"
  elif [ "$hw" = "false" ] && [ "$live_flows" = "0" ] && [ "$chain0_max" -eq 0 ] && [ "$qdisc_count" = "0" ]; then
    verdict="CLEAN"
  elif [ "$hw" = "false" ] && [ "$live_flows" = "0" ] && [ "$chain0_max" -gt 0 ]; then
    verdict="ORPHANED-LIVE"
  elif [ "$hw" = "false" ] && [ "$live_flows" = "0" ]; then
    verdict="RESIDUAL-ONLY"
  else
    verdict="REVIEW"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$node" "$pod" "$env_value" "$hw" "$live_flows" "$qdisc_count" \
    "$blocks" "$devices" "$uptime_days" "$verdict"
}
export -f audit_one_node

# ---------------------------------------------------------------------------
# run_audit
#   Audits every pod in PODS_FILE, P at a time, into RESULTS_FILE.
# ---------------------------------------------------------------------------
run_audit() {
  awk -F'\t' '{print $1, $2, ($3 == "" ? "unset" : $3)}' "$PODS_FILE" \
    | xargs -P "$P" -L1 bash -c 'audit_one_node "$@"' _ > "$RESULTS_FILE"
}

# ---------------------------------------------------------------------------
# write_report
#   Joins the role labels onto the results and writes the sorted TSV with a
#   header row to OUT.
# ---------------------------------------------------------------------------
write_report() {
  {
    printf 'NODE\tPOD\tENV_HW_OFFLOAD\tOVS_HW_OFFLOAD\tOVS_TC_FLOWS\t'
    printf 'INGRESS_QDISCS\tBLOCKS(chain0/total)\tDEVS(chain0/total)\t'
    printf 'UPTIME\tVERDICT\tROLE_LABELS\n'
    awk -F'\t' '
      NR == FNR { labels[$1] = $2; next }
      { print $0 "\t" (($1 in labels) ? labels[$1] : "?") }
    ' "$LABELS_FILE" "$RESULTS_FILE" | sort
  } > "$OUT"
}

# ---------------------------------------------------------------------------
# print_summary
#   Human-readable table and counts. Exits 2 if any node needs attention.
# ---------------------------------------------------------------------------
print_summary() {
  echo "=== per-node (full TSV: $OUT) ==="
  column -t -s $'\t' "$OUT" | cut -c1-230

  echo
  echo "=== summary ==="
  echo "ovs-ovn pods audited : $(wc -l < "$RESULTS_FILE")"

  awk -F'\t' 'NR > 1 { count[$10]++ }
              END { for (v in count) printf "  %-15s %d\n", v, count[v] }' "$OUT" | sort

  echo "by role label       :"
  awk -F'\t' 'NR > 1 { count[$11 "/" $10]++ }
              END { for (k in count) printf "  %-35s %d\n", k, count[k] }' "$OUT" | sort

  echo "OVS hw-offload      : $(awk -F'\t' 'NR > 1 { count[$4]++ }
              END { for (v in count) printf "%s=%d ", v, count[v] }' "$OUT")"
  echo "kube-ovn env        : $(awk -F'\t' 'NR > 1 { count[$3]++ }
              END { for (v in count) printf "%s=%d ", v, count[v] }' "$OUT")"

  echo "nodes needing attention (UNREACHABLE / ORPHANED-LIVE / REVIEW):"
  awk -F'\t' 'NR > 1 && $10 ~ /UNREACHABLE|ORPHANED-LIVE|REVIEW/ {
                print "  " $1 "  " $10 "  " $7 "  " $8
              }' "$OUT"

  awk -F'\t' 'NR > 1 && $10 ~ /UNREACHABLE|ORPHANED-LIVE|REVIEW/ { bad = 1 }
              END { exit bad ? 2 : 0 }' "$OUT"
}

main() {
  if ! command -v kubectl > /dev/null; then
    echo "kubectl not found" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$OUT")"

  gather_node_labels
  gather_ovs_pods
  run_audit
  write_report
  print_summary
}

main "$@"
