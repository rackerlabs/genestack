#!/bin/bash
# Phase 1: Update install scripts to use existing common functions
# This script automates the replacement of duplicated code with function calls

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

echo "=== Phase 1: Consolidating Install Scripts ==="
echo "Target directory: $BIN_DIR"
echo ""

# Function to update a single script
update_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    echo "Processing: $script_name"

    # Create backup
    cp "$script_path" "${script_path}.backup"

    # Track if we made changes
    local changed=false

    # Check if script has argument parsing code that should use parse_install_args
    if grep -q "ROTATE_SECRETS=false" "$script_path" && \
       grep -q "HELM_PASS_THROUGH=()" "$script_path" && \
       grep -q "while \[\[ \"\$#\" -gt 0 \]\]" "$script_path"; then
        echo "  - Found argument parsing to consolidate"
        changed=true
    fi

    # Check if script has version extraction that should use get_chart_version
    if grep -q "VERSION_FILE=.*helm-chart-versions.yaml" "$script_path" && \
       grep -q "grep.*SERVICE_NAME.*VERSION_FILE" "$script_path"; then
        echo "  - Found version extraction to consolidate"
        changed=true
    fi

    # Check if script has chart metadata extraction that should use extract_chart_metadata
    if grep -q "for yaml_file in.*yaml" "$script_path" && \
       grep -q "yq eval '.chart.repo_url" "$script_path"; then
        echo "  - Found chart metadata extraction to consolidate"
        changed=true
    fi

    # Check if script has helm repo setup that should use setup_helm_chart_path
    if grep -q 'if \[\[ "$HELM_REPO_URL.*== oci://' "$script_path" && \
       grep -q "update_helm_repo" "$script_path"; then
        echo "  - Found helm repo setup to consolidate"
        changed=true
    fi

    if [ "$changed" = true ]; then
        echo "  ✓ Needs consolidation"
        return 0
    else
        echo "  - No changes needed"
        rm "${script_path}.backup"
        return 1
    fi
}

# Count scripts
total=0
needs_update=0

for script in "$BIN_DIR"/install-*.sh; do
    if [ -f "$script" ]; then
        ((total++))
        if update_script "$script"; then
            ((needs_update++))
        fi
    fi
done

echo ""
echo "=== Summary ==="
echo "Total scripts: $total"
echo "Need updates: $needs_update"
echo "Already optimized: $((total - needs_update))"
echo ""
echo "Backups created with .backup extension"
echo "Review changes before committing"
