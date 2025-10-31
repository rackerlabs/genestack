#!/bin/bash
NAMESPACE="openstack"
TTL=180

echo "Applying TTL=$TTL seconds to completed jobs in $NAMESPACE..."

# Check if any jobs exist
if ! kubectl get jobs -n "$NAMESPACE" &>/dev/null; then
  echo "No jobs found in '$NAMESPACE'. Exiting."
  exit 0
fi

# Process each job
kubectl get jobs -n "$NAMESPACE" --no-headers | awk '{print $1}' | while read -r job; do
  [[ -z "$job" ]] && continue

  # Check if job is COMPLETED or NOT
  status=$(kubectl get job "$job" -n "$NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' \
    2>/dev/null || echo "Unknown")

  if [ "$status" == "True" ]; then
    if kubectl patch job "$job" -n "$NAMESPACE" --type=json \
      -p="[{\"op\": \"add\", \"path\": \"/spec/ttlSecondsAfterFinished\", \"value\": $TTL}]" \
      >/dev/null 2>&1; then
      echo "Patched: $job → delete in $TTL sec"
    else
      echo "Failed: $job (patch error)"
    fi
  else
    echo "Skipped: $job (not completed)"
  fi
done
