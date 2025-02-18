#!/usr/bin/env python3
import sys
import argparse
import re
import subprocess
from prometheus_client import (
    Gauge,
    generate_latest,
    CollectorRegistry,
    write_to_textfile,
)

REGEXP_CONTROLLER_HP = re.compile(r"Smart Array ([a-zA-Z0-9- ]+) in Slot ([0-9]+)")


class Raid:
    def get_controllers(self):
        raise NotImplementedError


class RaidController:
    def get_product_name(self):
        raise NotImplementedError

    def get_serial_number(self):
        raise NotImplementedError

    def get_manufacturer(self):
        raise NotImplementedError

    def get_firmware_version(self):
        raise NotImplementedError

    def get_physical_disks(self):
        raise NotImplementedError


def _get_indentation(string):
    """Return the number of spaces before the current line."""
    return len(string) - len(string.lstrip(" "))


def _get_key_value(string):
    """Return the (key, value) as a tuple from a string."""
    # Normally all properties look like this:
    #   Unique Identifier: 600508B1001CE4ACF473EE9C826230FF
    #   Disk Name: /dev/sda
    #   Mount Points: None
    key = ""
    value = ""
    try:
        key, value = string.split(":")
    except ValueError:
        # This handles the case when the property of a logical drive
        # returned is as follows. Here we cannot split by ':' because
        # the disk id has colon in it. So if this is about disk,
        # then strip it accordingly.
        #   Mirror Group 0: physicaldrive 6I:1:5
        string = string.lstrip(" ")
        if string.startswith("physicaldrive"):
            fields = string.split(" ")
            key = fields[0]
            value = fields[1]
        else:
            # TODO(rameshg87): Check if this ever occurs.
            return None, None

    return key.lstrip(" ").rstrip(" "), value.lstrip(" ").rstrip(" ")


def _get_dict(lines, start_index, indentation):
    """Recursive function for parsing hpssacli/ssacli output."""

    info = {}
    current_item = None

    i = start_index
    while i < len(lines):
        current_line = lines[i]
        if current_line.startswith("Note:"):
            i = i + 1
            continue

        current_line_indentation = _get_indentation(current_line)
        # This check ignore some useless information that make
        # crash the parsing
        product_name = REGEXP_CONTROLLER_HP.search(current_line)
        if current_line_indentation == 0 and not product_name:
            i = i + 1
            continue

        if current_line_indentation == indentation:
            current_item = current_line.lstrip(" ")

            info[current_item] = {}
            i = i + 1
            continue

        if i >= len(lines) - 1:
            key, value = _get_key_value(current_line)
            # If this is some unparsable information, then
            # just skip it.
            if key:
                info[current_item][key] = value
            return info, i

        next_line = lines[i + 1]
        next_line_indentation = _get_indentation(next_line)

        if current_line_indentation == next_line_indentation:
            key, value = _get_key_value(current_line)
            if key:
                info[current_item][key] = value
            i = i + 1
        elif next_line_indentation > current_line_indentation:
            ret_dict, j = _get_dict(lines, i, current_line_indentation)
            info[current_item].update(ret_dict)
            i = j + 1
        elif next_line_indentation < current_line_indentation:
            key, value = _get_key_value(current_line)
            if key:
                info[current_item][key] = value
            return info, i

    return info, i


class HPRaidController(RaidController):
    def __init__(self, controller_name, data, *args, **kwargs):
        self.controller_name = controller_name
        self.data = data
        self.bin_path = kwargs.get("bin_path")

    def get_product_name(self):
        return self.controller_name

    def get_manufacturer(self):
        return "HP"

    def get_serial_number(self):
        return self.data.get("Serial Number", "")

    def get_firmware_version(self):
        return self.data.get("Firmware Version", "")

    def get_controller_status(self):
        return self.data.get("Controller Status")

    def get_controller_cache(self):
        present = self.data.get("Cache Board Present")
        if not present or present == "False":
            return None
        ret = {
            "status": self.data["Cache Status"],
            "size": self.data["Total Cache Size"],
            "available": self.data["Total Cache Memory Available"],
        }
        return ret

    def get_temperature(self):
        return {
            "controller": self.data["Controller Temperature (C)"],
            "capacitor": self.data["Capacitor Temperature  (C)"],
        }

    def get_logical_drives(self):
        ret = []
        output = subprocess.getoutput(
            "{bin_path} ctrl slot={slot} ld all show detail".format(
                bin_path=self.bin_path, slot=self.data["Slot"]
            )
        )
        if "Error: The specified device does not have any logical drives." in output:
            return ret
        lines = output.split("\n")
        lines = list(filter(None, lines))
        j = -1
        while j < len(lines):
            info_dict, j = _get_dict(lines, j + 1, 0)
        key = next(iter(info_dict))

        for array, logical_disk in info_dict[key].items():
            for _, ld_attr in logical_disk.items():
                ld = {"Array": array.split()[1]}
                attrs = [
                    # `src` is the key of the ssacli output
                    # `dst` is the key of our destination dict
                    #       in case we want to rename it
                    # `func` is function to pass to change the output
                    {"src": "Size", "func": tosize},
                    {"src": "Status", "func": isok},
                    {"src": "Caching", "func": isenabled},
                ]
                for attr in attrs:
                    dst = attr["src"] if not attr.get("dst") else attr.get("dst")
                    value = ld_attr.get(attr["src"]).strip()
                    if attr.get("func"):
                        value = attr["func"](value)
                    ld[dst] = value
                ret.append(ld)
        return ret

    def get_physical_disks(self):
        ret = []
        output = subprocess.getoutput(
            "{bin_path} ctrl slot={slot} pd all show detail".format(
                bin_path=self.bin_path, slot=self.data["Slot"]
            )
        )
        lines = output.split("\n")
        lines = list(filter(None, lines))
        j = -1
        while j < len(lines):
            info_dict, j = _get_dict(lines, j + 1, 0)

        key = next(iter(info_dict))
        for array, physical_disk in info_dict[key].items():
            for _, pd_attr in physical_disk.items():
                model = pd_attr.get("Model", "").strip()
                pd = {
                    "Model": model,
                    "Type": (
                        "SSD"
                        if pd_attr.get("Interface Type") == "Solid State SATA"
                        else "HDD"
                    ),
                }
                attrs = [
                    # `src` is the key of the ssacli output
                    # `dst` is the key of our destination dict
                    #       in case we want to rename it
                    # `func` is function to pass to change the output
                    {"src": "Port"},
                    {"src": "Box", "func": int},
                    {"src": "Bay", "func": int},
                    {"src": "Serial Number", "dst": "SN"},
                    {"src": "Size", "func": tosize},
                    {"src": "Status", "func": isok},
                    {"src": "Power On Hours", "func": int},
                    {"src": "Usage remaining", "func": topercent},
                    {
                        "src": "Current Temperature (C)",
                        "dst": "Temperature",
                        "func": int,
                    },
                    {
                        "src": "Maximum Temperature (C)",
                        "dst": "Max Temperature",
                        "func": int,
                    },
                ]
                for attr in attrs:
                    dst = attr["src"] if not attr.get("dst") else attr.get("dst")
                    value = pd_attr.get(attr["src"])
                    if not value:
                        continue
                    value = value.strip()
                    if attr.get("func"):
                        value = attr["func"](value)
                    pd[dst] = value
                ret.append(pd)
        return ret


def isenabled(value):
    return value == "Enabled"


def isok(value):
    return value == "OK"


def tosize(value):
    ret = float(value.split()[0])
    if "TB" in value:
        ret = float(value.split()[0]) * 1000
    return ret


def topercent(value):
    return float(value.replace("%", ""))


class HPRaid(Raid):
    def __init__(self, *args, **kwargs):
        self.bin_path = kwargs.get("bin_path")
        self.output = subprocess.getoutput(self.bin_path + " ctrl all show detail")
        self.controllers = []
        self.convert_to_dict()

    def convert_to_dict(self):
        lines = self.output.split("\n")
        lines = list(filter(None, lines))
        j = -1
        while j < len(lines):
            info_dict, j = _get_dict(lines, j + 1, 0)
            if len(info_dict.keys()):
                _product_name = list(info_dict.keys())[0]
                product_name = REGEXP_CONTROLLER_HP.search(_product_name)
                if product_name:
                    self.controllers.append(
                        HPRaidController(
                            product_name.group(1),
                            info_dict[_product_name],
                            bin_path=self.bin_path,
                        )
                    )

    def get_controllers(self):
        return self.controllers


class Raid(Raid):
    def get_controllers(self):
        raise NotImplementedError


def run(args):
    registry = CollectorRegistry()
    hp_smart_array_controller_status = Gauge(
        "hp_smart_array_controller_status",
        "Controller status",
        ["product_name", "serial", "firmware_version"],
        registry=registry,
    )
    hp_smart_array_controller_cache_status = Gauge(
        "hp_smart_array_controller_cache_status",
        "Controller Cache Status",
        ["product_name", "serial", "firmware_version"],
        registry=registry,
    )
    hp_smart_array_controller_cache_size = Gauge(
        "hp_smart_array_controller_cache_size",
        "Controller Cache Size in GB",
        ["product_name", "serial", "firmware_version"],
        registry=registry,
    )
    hp_smart_array_controller_cache_available = Gauge(
        "hp_smart_array_controller_cache_available",
        "Controller Cache available in GB",
        ["product_name", "serial", "firmware_version"],
        registry=registry,
    )
    hp_smart_array_disk_power_on_hours = Gauge(
        "hp_smart_array_disk_power_on_hours",
        "Number of power on hours",
        ["bay", "box", "port", "serial"],
        registry=registry,
    )
    hp_smart_array_disk_usage = Gauge(
        "hp_smart_array_disk_usage",
        "Usage remaining for disk in %",
        ["bay", "box", "port", "serial"],
        registry=registry,
    )
    hp_smart_array_disk_status = Gauge(
        "hp_smart_array_disk_status",
        "Status of physical disk",
        ["bay", "box", "port", "serial"],
        registry=registry,
    )
    hp_smart_array_disk_count = Gauge(
        "hp_smart_array_disk_count",
        "Number of physical disks",
        registry=registry,
    )
    hp_smart_array_disk_temperature = Gauge(
        "hp_smart_array_disk_temperature",
        "Temperature of disk in C",
        ["bay", "box", "port", "serial"],
        registry=registry,
    )
    hp_smart_array_disk_max_temperature = Gauge(
        "hp_smart_array_disk_max_temperature",
        "Maxmium temperature of disk in C",
        ["bay", "box", "port", "serial"],
        registry=registry,
    )
    hp_smart_array_ld_status = Gauge(
        "hp_smart_array_ld_status",
        "Logicial drive status",
        [
            "array",
        ],
        registry=registry,
    )
    hp_smart_array_ld_caching = Gauge(
        "hp_smart_array_ld_caching",
        "Logicial drive caching",
        [
            "array",
        ],
        registry=registry,
    )

    r = HPRaid(bin_path=args.bin_path)
    controllers = r.get_controllers()
    for controller in controllers:
        labels = {
            "serial": controller.get_serial_number(),
            "firmware_version": controller.get_firmware_version(),
            "product_name": controller.get_product_name(),
        }
        cache = controller.get_controller_cache()
        hp_smart_array_controller_status.labels(**labels).set(
            isok(controller.get_controller_status())
        )
        if cache:
            hp_smart_array_controller_cache_status.labels(**labels).set(
                isok(cache["status"])
            )
            hp_smart_array_controller_cache_size.labels(**labels).set(
                float(cache["size"])
            )
            hp_smart_array_controller_cache_available.labels(**labels).set(
                float(cache["available"])
            )
        for ld in controller.get_logical_drives():
            labels = {
                "array": ld["Array"],
            }
            hp_smart_array_ld_status.labels(**labels).set(ld["Status"])
            hp_smart_array_ld_caching.labels(**labels).set(ld["Caching"])

        disks = controller.get_physical_disks()
        hp_smart_array_disk_count.set(len(disks))
        for disk in disks:
            labels = {
                "bay": disk["Bay"],
                "box": disk["Box"],
                "port": disk["Port"],
                "serial": disk["SN"],
            }
            hp_smart_array_disk_status.labels(**labels).set(disk["Status"])
            if "Temperature" in disk.keys():
                hp_smart_array_disk_temperature.labels(**labels).set(
                    disk["Temperature"]
                )
            if "Max Temperature" in disk.keys():
                hp_smart_array_disk_max_temperature.labels(**labels).set(
                    disk["Max Temperature"]
                )
            if "Power On Hours" in disk.keys():
                hp_smart_array_disk_power_on_hours.labels(**labels).set(
                    disk["Power On Hours"]
                )
            if "Usage remaining" in disk.keys():
                hp_smart_array_disk_usage.labels(**labels).set(disk["Usage remaining"])

    with open(args.output, "wb") as prom_export:
        prom_export.write(generate_latest(registry))


def main():
    parser = argparse.ArgumentParser(
        description="HP SmartArray cli exporter for Prometheus"
    )
    parser.add_argument(
        "--bin-path",
        default="/usr/sbin/ssacli",
        help="Binary path for ssacli/hpacucli binary",
    )
    parser.add_argument(
        "--output",
        help="Output filename",
        required=True,
    )
    args = parser.parse_args()
    try:
        run(args)
        sys.exit(0)
    except Exception as e:
        print(e)
        sys.exit(1)


if __name__ == "__main__":
    main()
