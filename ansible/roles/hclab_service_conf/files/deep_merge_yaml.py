#!/usr/bin/env python3
"""Deep-merge a YAML fragment into an existing YAML file.

Usage:
    python3 deep_merge_yaml.py BASE_FILE FRAGMENT_FILE

If BASE_FILE does not exist it is created. The fragment values win on conflict.
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
        print(f"Usage: {sys.argv[0]} BASE_FILE FRAGMENT_FILE", file=sys.stderr)
        sys.exit(1)

    base_file = sys.argv[1]
    fragment_file = sys.argv[2]

    if os.path.exists(base_file):
        with open(base_file, "r") as fh:
            base = yaml.safe_load(fh) or {}
    else:
        base = {}

    with open(fragment_file, "r") as fh:
        fragment = yaml.safe_load(fh) or {}

    merged = deep_merge(base, fragment)

    with open(base_file, "w") as fh:
        yaml.dump(merged, fh, default_flow_style=False, sort_keys=False, width=200)


if __name__ == "__main__":
    main()
