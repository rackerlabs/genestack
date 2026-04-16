#!/usr/bin/env python3
"""Deep-merge a Manila endpoints fragment into global_overrides/endpoints.yaml.

Preserves the _region YAML anchor line that safe_load would otherwise drop.

Usage:
    python3 merge_endpoints.py ENDPOINTS_FILE FRAGMENT_FILE
"""
import copy
import os
import sys
import yaml


def deep_merge(base, overlay):
    """Recursively merge overlay into base. Overlay values win."""
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} ENDPOINTS_FILE FRAGMENT_FILE", file=sys.stderr)
        sys.exit(1)

    endpoints_file = sys.argv[1]
    fragment_file = sys.argv[2]
    anchor_line = ""

    if os.path.exists(endpoints_file):
        with open(endpoints_file, "r") as fh:
            content = fh.read()
            base = yaml.safe_load(content) or {}
            for line in content.splitlines():
                if line.strip().startswith("_region:"):
                    anchor_line = line
                    break
    else:
        base = {}

    with open(fragment_file, "r") as fh:
        fragment = yaml.safe_load(fh) or {}

    merged = deep_merge(base, fragment)

    with open(endpoints_file, "w") as fh:
        if anchor_line:
            fh.write(anchor_line + "\n\n")
        # Remove _region from the dict so it is not dumped twice
        merged.pop("_region", None)
        yaml.dump(merged, fh, default_flow_style=False, sort_keys=False, width=200)


if __name__ == "__main__":
    main()
