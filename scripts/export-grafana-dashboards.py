#! /usr/bin/env python
import requests
import re
import json


def export_dashboards(grafana_url, api_key):
    headers = {"Authorization": f"Bearer {api_key}"}

    # First get all folders
    folders = requests.get(f"{grafana_url}/api/folders", headers=headers).json()
    folder_map = {folder["id"]: folder["title"] for folder in folders}

    # Get all dashboards with folder info
    dashboards = requests.get(f"{grafana_url}/api/search", headers=headers).json()

    for dashboard in dashboards:
        if dashboard["type"] == "dash-folder":
            continue  # Skip folder entries

        uid = dashboard["uid"]
        dash_json = requests.get(
            f"{grafana_url}/api/dashboards/uid/{uid}", headers=headers
        ).json()

        # Add folder info
        folder_id = dashboard.get("folderId", 0)
        dash_json["folderTitle"] = folder_map.get(folder_id, "General")

        # Replace slashes with underscores in filename
        safe_title = re.sub(r"[/\\]", "_", dashboard["title"])
        with open(f"{safe_title}.json", "w") as f:
            json.dump(dash_json, f)


def main():
    apikey = "<api_key>"
    grafana = "<https://grafana.endpoint.region.example.com>"

    export_dashboards(grafana, apikey)


main()
