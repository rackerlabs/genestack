import json

try:
    with open("installed.json") as f:
        # Only store package names for comparison, ignore versions
        installed = {pkg["name"].lower() for pkg in json.load(f)}
except (json.JSONDecodeError, FileNotFoundError):
    installed = set()

with open("requirements.txt") as f:
    requirements = [
        line.strip() for line in f if line.strip() and not line.startswith("#")
    ]

filtered = []
for req in requirements:
    # Only get package name for comparison
    pkg_name = req.split("==")[0].strip().lower()
    if pkg_name in installed:
        # Add the full original requirement (including version)
        filtered.append(req)

with open("filtered-requirements.txt", "w") as f:
    f.write("\n".join(filtered))
