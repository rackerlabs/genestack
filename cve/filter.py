import json

try:
    with open("installed.json") as f:
        # Only store package names for comparison, ignore versions
        installed = {pkg["name"].lower() for pkg in json.load(f)}
except (json.JSONDecodeError, FileNotFoundError):
    installed = set()

print("Installed packages:")
print("\n".join(sorted(installed)) if installed else "No installed packages found")
print("\n" + "=" * 50 + "\n")

with open("cve/requirements.txt") as f:
    requirements = [
        line.strip() for line in f if line.strip() and not line.startswith("#")
    ]

print("Requirements from requirements.txt:")
print("\n".join(requirements) if requirements else "No requirements found")
print("\n" + "=" * 50 + "\n")

filtered = []
for req in requirements:
    # Only get package name for comparison
    pkg_name = req.split("==")[0].strip().lower()
    if pkg_name in installed:
        # Add the full original requirement (including version)
        filtered.append(req)

print("Filtered requirements (matching installed packages):")
print("\n".join(filtered) if filtered else "No matching packages found")
print("\n" + "=" * 50 + "\n")

with open("filtered-requirements.txt", "w") as f:
    f.write("\n".join(filtered))
