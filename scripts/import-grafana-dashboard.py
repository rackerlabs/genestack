#!/usr/bin/env python
import requests
from requests.auth import HTTPBasicAuth
import json
import glob
import os
import sys
import argparse


def convert_v2_dashboard(dashboard_json):
    """Convert Grafana dashboard.grafana.app/v2beta1 JSON to legacy format."""
    if dashboard_json.get("kind") != "Dashboard" or "spec" not in dashboard_json:
        return dashboard_json

    spec = dashboard_json["spec"]
    panels = []
    positions = {}
    layout = spec.get("layout", {}).get("spec", {}).get("items", [])
    for item in layout:
        element = item.get("spec", {}).get("element", {})
        name = element.get("name")
        if name:
            positions[name] = item.get("spec", {})

    for name, element in spec.get("elements", {}).items():
        if element.get("kind") != "Panel":
            continue
        panel = element.get("spec", {})
        viz = panel.get("vizConfig", {})
        viz_spec = viz.get("spec", {})
        panel_data = panel.get("data", {}).get("spec", {})
        targets = []
        for query in panel_data.get("queries", []):
            query_spec = query.get("spec", {})
            query_data = query_spec.get("query", {})
            targets.append(
                {
                    "refId": query_spec.get("refId", "A"),
                    "datasource": {
                        "type": query_data.get("group"),
                        "uid": "${alertmanager}",
                    },
                    **query_data.get("spec", {}),
                }
            )
        position = positions.get(name, {})
        panels.append(
            {
                "id": panel.get("id"),
                "title": panel.get("title", ""),
                "description": panel.get("description", ""),
                "type": viz.get("group", "timeseries"),
                "fieldConfig": viz_spec.get("fieldConfig", {}),
                "options": viz_spec.get("options", {}),
                "targets": targets,
                "gridPos": {
                    "x": position.get("x", 0),
                    "y": position.get("y", 0),
                    "w": position.get("width", 24),
                    "h": position.get("height", 6),
                },
            }
        )

    variables = []
    for variable in spec.get("variables", []):
        variable_spec = variable.get("spec", {})
        if variable.get("kind") == "DatasourceVariable":
            variables.append(
                {
                    "name": variable_spec.get("name", "datasource"),
                    "label": variable_spec.get("label"),
                    "type": "datasource",
                    "query": variable_spec.get("pluginId", "prometheus"),
                    "refresh": 1,
                    "hide": 0,
                }
            )

    return {
        "title": spec.get("title", "Untitled Dashboard"),
        "description": spec.get("description", ""),
        "editable": spec.get("editable", True),
        "tags": spec.get("tags", []),
        "panels": panels,
        "links": spec.get("links", []),
        "time": {
            "from": spec.get("timeSettings", {}).get("from", "now-6h"),
            "to": spec.get("timeSettings", {}).get("to", "now"),
        },
        "templating": {"list": variables},
        "annotations": {"list": []},
        "schemaVersion": 39,
        "version": 1,
    }


def import_dashboards(
    grafana_url,
    grafana_user,
    grafana_password,
    dashboard_dir,
    prometheus_datasource,
    dashboard_files=None,
):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}

    if not os.path.isdir(dashboard_dir):
        print(f"Error: '{dashboard_dir}' is not a valid directory.")
        sys.exit(1)

    if dashboard_files:
        files = []
        for dashboard_file in dashboard_files:
            path = dashboard_file
            if not os.path.isabs(path):
                path = os.path.join(dashboard_dir, path)
            path = os.path.abspath(path)
            if not os.path.isfile(path):
                print(f"Error: '{dashboard_file}' is not a valid dashboard file.")
                sys.exit(1)
            if not path.lower().endswith(".json"):
                print(
                    f"Error: Dashboard file '{dashboard_file}' must have a .json extension."
                )
                sys.exit(1)
            files.append(path)
    else:
        files = sorted(glob.glob(os.path.join(dashboard_dir, "*.json")))

    # Create folders first
    folder_cache = {}

    for file in files:
        with open(file, "r") as f:
            dashboard_json = json.load(f)
            dashboard_json = convert_v2_dashboard(dashboard_json)
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
    for file in files:
        with open(file, "r") as f:
            dashboard_json = json.load(f)
            dashboard_json = convert_v2_dashboard(dashboard_json)
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
    parser.add_argument(
        "-f",
        "--file",
        action="append",
        dest="dashboard_files",
        metavar="FILE",
        help=(
            "Dashboard JSON file to import. May be repeated; paths are relative "
            "to --dir unless absolute. If omitted, import all JSON files in --dir."
        ),
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

    grafana_username = os.environ.get("GRAFANA_USERNAME")
    grafana_password = os.environ.get("GRAFANA_PASSWORD")
    grafana_url = os.environ.get("GRAFANA_URL")

    import_dashboards(
        grafana_url,
        grafana_username,
        grafana_password,
        args.dir,
        args.datasource,
        args.dashboard_files,
    )


if __name__ == "__main__":
    main()
