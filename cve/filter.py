import json

try:
    with open("installed.json") as f:
        installed = {pkg["name"].lower(): pkg["version"] for pkg in json.load(f)}
except (json.JSONDecodeError, FileNotFoundError):
    installed = {}

with open("requirements.txt") as f:
    requirements = [
        line.strip() for line in f if line.strip() and not line.startswith("#")
    ]

filtered = []
for req in requirements:
    pkg_name = req.split("==")[0].strip().lower()
    if pkg_name in installed:
        filtered.append(req)

with open("filtered-requirements.txt", "w") as f:
    f.write("\n".join(filtered))
