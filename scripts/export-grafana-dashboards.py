#!/usr/bin/env python
import argparse
import json
import os
import re
import sys

import requests
from requests.auth import HTTPBasicAuth


def _get_json(url, auth):
    response = requests.get(url, auth=auth)
    if not response.ok:
        print(f"Failed to fetch {url}: {response.status_code} - {response.text}")
        return None

    try:
        return response.json()
    except ValueError:
        print(f"Failed to decode JSON from {url}: {response.text}")
        return None


def _safe_filename(title, fallback):
    """Convert a dashboard title into a shell-friendly filename stem."""
    safe_title = re.sub(r"[^A-Za-z0-9]+", "_", title).strip("_")
    return safe_title or fallback


def export_dashboards(grafana_url, grafana_user, grafana_password, dashboard_dir):
    if not os.path.isdir(dashboard_dir):
        print(f"Error: '{dashboard_dir}' is not a valid directory.")
        return False

    grafana_url = grafana_url.rstrip("/")
    auth = HTTPBasicAuth(grafana_user, grafana_password)

    folders = _get_json(f"{grafana_url}/api/folders", auth)
    if folders is None:
        return False
    folder_map = {folder["id"]: folder["title"] for folder in folders}

    dashboards = _get_json(f"{grafana_url}/api/search", auth)
    if dashboards is None:
        return False

    for dashboard in dashboards:
        if dashboard["type"] == "dash-folder":
            continue

        uid = dashboard["uid"]
        dashboard_response = _get_json(f"{grafana_url}/api/dashboards/uid/{uid}", auth)
        if dashboard_response is None:
            continue

        # Grafana wraps the dashboard definition in a response object. The
        # importer expects the dashboard definition itself at the JSON root.
        dashboard_json = dashboard_response.get("dashboard")
        if dashboard_json is None:
            print(f"Failed to find dashboard data for '{dashboard['title']}'")
            continue

        folder_id = dashboard.get("folderId", 0)
        dashboard_json["folderTitle"] = folder_map.get(folder_id, "General")

        safe_title = _safe_filename(dashboard["title"], uid)
        output_file = os.path.join(dashboard_dir, f"{safe_title}.json")
        with open(output_file, "w") as file:
            json.dump(dashboard_json, file, indent=2)
        print(f"Exported {output_file}")

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Export Grafana dashboards to a local directory."
    )
    parser.add_argument(
        "-d",
        "--dir",
        required=True,
        help="Path to directory where dashboard JSON files will be written",
    )
    args = parser.parse_args()

    required_vars = ["GRAFANA_PASSWORD"]
    optional_vars = {
        "GRAFANA_USERNAME": "admin",
        "GRAFANA_URL": "http://grafana.monitoring.svc.cluster.local:80",
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

    success = export_dashboards(
        os.environ["GRAFANA_URL"],
        os.environ["GRAFANA_USERNAME"],
        os.environ["GRAFANA_PASSWORD"],
        args.dir,
    )
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
