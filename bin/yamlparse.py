# This works with install-chart.sh to get the information to run the script.
# It doesn't work very well as any kind of stand-alone utility.

import sys
import yaml

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} <filename> <chart>")
    sys.exit(1)

filename = sys.argv[1]
chart = sys.argv[2]

try:
    with open(filename, "r") as conf_file:
        conf_yaml = yaml.safe_load(conf_file)
except Exception as e:
    print(f"Error parsing YAML file {filename}: {e}")
    sys.exit(1)

if chart not in conf_yaml:
    print(f"No chart '{chart}' in file {filename}")
    sys.exit(1)

for key, value in conf_yaml[chart].items():
    print(f"{key}")
    if not isinstance(value, list):
        print(f"{value}")
    else:
        print(*value)
