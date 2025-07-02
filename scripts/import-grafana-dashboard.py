#!/usr/bin/env python
import requests
from requests.auth import HTTPBasicAuth
import json
import glob
import os
import sys
import argparse


def import_dashboards(
    grafana_url, grafana_user, grafana_password, dashboard_dir, prometheus_datasource
):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}

    if not os.path.isdir(dashboard_dir):
        print(f"Error: '{dashboard_dir}' is not a valid directory.")
        sys.exit(1)

    os.chdir(dashboard_dir)

    # Create folders first
    folder_cache = {}

    for file in glob.glob("*.json"):
        with open(file, "r") as f:
            dashboard_json = json.load(f)
            folder_title = dashboard_json.get("folderTitle", "General")

            if folder_title != "General" and folder_title not in folder_cache:
                folder_response = requests.post(
                    f"{grafana_url}/api/folders",
                    headers=headers,
                    json={"title": folder_title},
                    auth=HTTPBasicAuth(grafana_user, grafana_password),
                )
                if folder_response.ok:
                    folder_cache[folder_title] = folder_response.json()["id"]
                else:
                    print(
                        f"Failed to create folder '{folder_title}': {folder_response.status_code} {folder_response.text}"
                    )
                    continue

    # Import dashboards
    for file in glob.glob("*.json"):
        with open(file, "r") as f:
            dashboard_json = json.load(f)
            dashboard_json.pop("id", None)
            folder_title = dashboard_json.get("folderTitle", "General")
            import_json = {
                "dashboard": dashboard_json,
                "overwrite": True,
                "folderId": folder_cache.get(folder_title, 0),
                "inputs": [
                    {
                        "name": "DS_PROMETHEUS",
                        "type": "datasource",
                        "pluginId": "prometheus",
                        "value": prometheus_datasource,
                    }
                ],
            }
            response = requests.post(
                f"{grafana_url}/api/dashboards/import",
                headers=headers,
                json=import_json,
                auth=HTTPBasicAuth(grafana_user, grafana_password),
            )
            if response.ok:
                print(f"Imported {file}: {response.status_code}")
            else:
                print(
                    f"Failed to import {file}: {response.status_code} - {response.text}"
                )


def main():
    parser = argparse.ArgumentParser(
        description="Import Grafana dashboards from a local directory."
    )
    parser.add_argument(
        "-d",
        "--dir",
        required=True,
        help="Path to directory containing dashboard JSON files",
    )
    parser.add_argument(
        "-ds",
        "--datasource",
        required=False,
        help='Name of the Prometheus datasource. Default: "Prometheus"',
        default="Prometheus",
    )
    args = parser.parse_args()
    required_vars = ["GRAFANA_PASSWORD"]
    optional_vars = {
        "GRAFANA_USERNAME": "admin",
        "GRAFANA_URL": "http://grafana.grafana.svc.cluster.local:80",
    }

    missing = [var for var in required_vars if var not in os.environ]
    if missing:
        print(f"Error: Missing required environment variable(s): {', '.join(missing)}")
        sys.exit(1)

    for var, default in optional_vars.items():
        if var not in os.environ:
            print(
                f"Info: Environment variable '{var}' not set. Using default: '{default}'"
            )
            os.environ[var] = default

    grafana_username = os.environ.get("GRAFANA_USERNAME")
    grafana_password = os.environ.get("GRAFANA_PASSWORD")
    grafana_url = os.environ.get("GRAFANA_URL")

    import_dashboards(
        grafana_url, grafana_username, grafana_password, args.dir, args.datasource
    )


if __name__ == "__main__":
    main()
