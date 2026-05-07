#!/usr/bin/env python3
"""Merge the Manila service instance password into global_overrides/secrets.yaml.

Reads the password from the _MANILA_SVC_PW environment variable and writes it
into conf.manila.generic.service_instance_password, preserving any other keys
already present in the file.

Usage:
    _MANILA_SVC_PW=<password> python3 merge_manila_secret.py SECRETS_FILE
"""
import os
import sys
import yaml


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} SECRETS_FILE", file=sys.stderr)
        sys.exit(1)

    secrets_file = sys.argv[1]
    password = os.environ.get("_MANILA_SVC_PW", "")
    if not password:
        print("Error: _MANILA_SVC_PW environment variable is not set", file=sys.stderr)
        sys.exit(1)

    if os.path.exists(secrets_file):
        with open(secrets_file, "r") as fh:
            data = yaml.safe_load(fh) or {}
    else:
        data = {}

    data.setdefault("conf", {}).setdefault("manila", {}).setdefault("generic", {})
    data["conf"]["manila"]["generic"]["service_instance_password"] = password

    with open(secrets_file, "w") as fh:
        yaml.dump(data, fh, default_flow_style=False, sort_keys=False)
    os.chmod(secrets_file, 0o640)


if __name__ == "__main__":
    main()
