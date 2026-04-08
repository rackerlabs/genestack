#!/bin/bash

# --- DEFAULTS ---
# Default targets the script-generated file specifically
DEFAULT_PATH="genestack/ansible/inventory/genestack/group_vars/all/cloud_resources.yml"
TARGET_FILE="$DEFAULT_PATH"
REQUIRED_UTILS=("jq" "openstack" "tr")

usage() {
    echo "Usage: $0 [-o /path/to/output.yml]"
    echo "  -o    Override the default output path"
    exit 1
}

while getopts "o:" opt; do
    case $opt in
        o) TARGET_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done

# --- PRE-FLIGHT ---
for util in "${REQUIRED_UTILS[@]}"; do
    command -v "$util" &> /dev/null || { echo "ERROR: $util missing."; exit 1; }
done
openstack token issue &> /dev/null || { echo "ERROR: API unreachable."; exit 1; }

TEMP_FILE=$(mktemp /tmp/cloud_resources.XXXXXX.yml)

# --- START YAML (DYNAMIC DATA ONLY) ---
cat <<EOF > "$TEMP_FILE"
---
# Generated Cloud Resource Configuration (Dynamic State)
# Generated: $(date)

openstack_flavors:
EOF

echo "Extracting Flavors..."
mapfile -t FLAVOR_IDS < <(openstack flavor list -f value -c ID)
for ID in "${FLAVOR_IDS[@]}"; do
    RAW=$(openstack flavor show "$ID" -f json)
    NAME=$(echo "$RAW" | jq -r '.name')
    echo "  -> Flavor: $NAME"
    cat <<EOF >> "$TEMP_FILE"
  - name: "$NAME"
    description: "$(echo "$RAW" | jq -r '.description // ""')"
    ram: $(echo "$RAW" | jq -r '.ram')
    disk: $(echo "$RAW" | jq -r '.disk')
    vcpus: $(echo "$RAW" | jq -r '.vcpus')
    ephemeral: $(echo "$RAW" | jq -r '."OS-FLV-EXT-DATA:ephemeral" // 0')
    swap: $(echo "$RAW" | jq -r '.swap // 0')
    is_public: $(echo "$RAW" | jq -r '."os-flavor-access:is_public"')
    extra_specs: $(echo "$RAW" | jq -c '.properties // {}')
EOF
done

echo -e "\nopenstack_networks:" >> "$TEMP_FILE"

echo "Extracting Networks..."
mapfile -t NET_IDS < <(openstack network list --external -f value -c ID)
for NET_ID in "${NET_IDS[@]}"; do
    NET_DATA=$(openstack network show "$NET_ID" -f json)
    NET_NAME=$(echo "$NET_DATA" | jq -r '.name')
    echo "  -> Network: $NET_NAME"
    
    EXT_RAW=$(echo "$NET_DATA" | jq -r '."router:external"')
    [[ "$EXT_RAW" == "External" || "$EXT_RAW" == "true" ]] && EXTERNAL="true" || EXTERNAL="false"

    cat <<EOF >> "$TEMP_FILE"
  - name: "$NET_NAME"
    provider_physical_network: "$(echo "$NET_DATA" | jq -r '."provider:physical_network" // "null"')"
    provider_network_type: "$(echo "$NET_DATA" | jq -r '."provider:network_type" // "null"')"
    provider_segmentation_id: $(echo "$NET_DATA" | jq -r '."provider:segmentation_id" // "null"')
    external: $EXTERNAL
    shared: $(echo "$NET_DATA" | jq -r '.shared // false')
    subnets:
EOF

    SUB_IDS=$(echo "$NET_DATA" | jq -r '.subnets | if type == "array" then .[] else . end' | tr -d ',')
    for SUB_ID in $SUB_IDS; do
        [[ -z "$SUB_ID" ]] && continue
        SUB_DATA=$(openstack subnet show "$SUB_ID" -f json)
        cat <<EOF >> "$TEMP_FILE"
      - name: "$(echo "$SUB_DATA" | jq -r '.name')"
        cidr: "$(echo "$SUB_DATA" | jq -r '.cidr')"
        gateway_ip: "$(echo "$SUB_DATA" | jq -r '.gateway_ip // "null"')"
        enable_dhcp: $(echo "$SUB_DATA" | jq -r '.enable_dhcp // true')
        allocation_pools: $(echo "$SUB_DATA" | jq -c '.allocation_pools // []')
EOF
    done
done

mv "$TEMP_FILE" "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
echo "Success! Dynamic resources written to $TARGET_FILE"
