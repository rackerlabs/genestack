#!/usr/bin/env python
import argparse
import json
import os
import re
import sys

import requests
from requests.auth import HTTPBasicAuth


def build_session():
    """Build a requests session authenticated against Grafana.

    A Grafana service account token (``GRAFANA_TOKEN``) is preferred. Basic
    auth with ``GRAFANA_USERNAME``/``GRAFANA_PASSWORD`` is still accepted for
    backwards compatibility, but it is deprecated: it requires the Grafana
    admin credentials and cannot be scoped or revoked independently.
    """
    session = requests.Session()
    session.headers.update({"Accept": "application/json"})

    token = os.environ.get("GRAFANA_TOKEN")
    if token:
        session.headers["Authorization"] = f"Bearer {token}"
        return session

    password = os.environ.get("GRAFANA_PASSWORD")
    if password:
        username = os.environ.get("GRAFANA_USERNAME", "admin")
        print(
            "Warning: GRAFANA_TOKEN is not set, falling back to basic auth as "
            f"'{username}'. Basic auth is deprecated, use a Grafana service "
            "account token instead."
        )
        session.auth = HTTPBasicAuth(username, password)
        return session

    print(
        "Error: No Grafana credentials found. Set GRAFANA_TOKEN to a Grafana "
        "service account token (preferred), or GRAFANA_PASSWORD to use "
        "deprecated basic auth."
    )
    sys.exit(1)


def _get_json(session, url):
    response = session.get(url)
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


def export_dashboards(grafana_url, session, dashboard_dir):
    if not os.path.isdir(dashboard_dir):
        print(f"Error: '{dashboard_dir}' is not a valid directory.")
        return False

    grafana_url = grafana_url.rstrip("/")

    folders = _get_json(session, f"{grafana_url}/api/folders")
    if folders is None:
        return False
    folder_map = {folder["id"]: folder["title"] for folder in folders}

    dashboards = _get_json(session, f"{grafana_url}/api/search")
    if dashboards is None:
        return False

    for dashboard in dashboards:
        if dashboard["type"] == "dash-folder":
            continue

        uid = dashboard["uid"]
        dashboard_response = _get_json(
            session, f"{grafana_url}/api/dashboards/uid/{uid}"
        )
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

    default_url = "http://grafana.monitoring.svc.cluster.local:80"
    grafana_url = os.environ.get("GRAFANA_URL")
    if not grafana_url:
        print(
            "Info: Environment variable 'GRAFANA_URL' not set. Using default: "
            f"'{default_url}'"
        )
        grafana_url = default_url

    session = build_session()

    success = export_dashboards(grafana_url, session, args.dir)
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
