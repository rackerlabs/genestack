#!/usr/bin/env python3
# Copyright 2026, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Check multipath maps and their SCSI path WWNs.

The checker deliberately uses ``scsi_id`` for the path identity instead of
trusting a udev symlink name.  It is intended for read-only diagnostics on a
Linux host and needs root (or equivalent permissions) to query some devices.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from typing import Sequence

DEFAULT_SCSI_ID = "/lib/udev/scsi_id"
DEFAULT_MULTIPATH = "multipath"
NO_PATHS_REASON = (
    "no underlying SCSI paths parsed from multipath -l; path verification skipped"
)
MULTIPATH_HEADER = re.compile(
    r"^(?:\w+:\s+)?(?P<name>\S+)\s+"
    r"(?:\((?P<wwid>[^)]+)\)\s+)?(?:dm-\d+|undef)(?:\s|$)"
)
PATH_LINE = re.compile(
    r"^[|`+\\\s-]*(?P<hctl>\d+:\d+:\d+:\d+)\s+"
    r"(?P<device>\S+)\s+\S+\s+(?P<state>\S+)\s+(?P<path_state>\S+)"
    r"\s+(?P<device_state>\S+)"
)
WWN = re.compile(r"^(?:0x)?[0-9a-f]+$", re.IGNORECASE)


@dataclass
class PathResult:
    device: str
    hctl: str | None = None
    state: str | None = None
    path_state: str | None = None
    device_state: str | None = None
    wwn: str | None = None
    error: str | None = None


@dataclass
class MapResult:
    name: str
    wwn: str | None
    paths: list[PathResult] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def failed_paths(self) -> list[PathResult]:
        failed = {"failed", "faulty", "offline", "down", "removed", "shaky", "timeout"}
        return [
            p
            for p in self.paths
            if any(
                value and value.lower() in failed
                for value in (p.state, p.path_state, p.device_state)
            )
        ]

    @property
    def mismatched_paths(self) -> list[PathResult]:
        return [
            p
            for p in self.paths
            if p.wwn and self.wwn and normalize_wwn(p.wwn) != normalize_wwn(self.wwn)
        ]

    @property
    def has_problems(self) -> bool:
        return bool(
            self.failed_paths
            or self.mismatched_paths
            or self.errors
            or any(p.error for p in self.paths)
        )


def normalize_wwn(value: str) -> str:
    """Normalize common scsi_id/multipath WWID spellings for comparison."""
    return value.strip().lower().removeprefix("0x")


def run_command(command: Sequence[str]) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            command, text=True, capture_output=True, check=False, timeout=30
        )
    except subprocess.TimeoutExpired:
        return 124, "", "command timed out after 30 seconds"
    except OSError as exc:
        return 127, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr.strip()


def scsi_id(device: str, executable: str) -> tuple[str | None, str | None]:
    command = [executable, "--page=0x83", "--whitelisted", "--device", device]
    rc, stdout, stderr = run_command(command)
    value = stdout.strip().splitlines()[-1].strip() if stdout.strip() else ""
    if rc != 0 or not value:
        return None, stderr or f"{executable} exited with status {rc}"
    if not WWN.fullmatch(value):
        return None, f"unexpected scsi_id output: {value!r}"
    return normalize_wwn(value), None


def parse_multipath(output: str) -> list[MapResult]:
    maps: list[MapResult] = []
    current: MapResult | None = None
    for raw_line in output.splitlines():
        line = raw_line.strip()
        header = MULTIPATH_HEADER.match(line)
        if header:
            current = MapResult(
                name=header.group("name"),
                wwn=normalize_wwn(header.group("wwid") or header.group("name")),
            )
            maps.append(current)
            continue
        if current is None:
            continue
        path = PATH_LINE.match(line)
        if path:
            current.paths.append(
                PathResult(
                    device=f"/dev/{path.group('device')}",
                    hctl=path.group("hctl"),
                    state=path.group("state"),
                    path_state=path.group("path_state"),
                    device_state=path.group("device_state"),
                )
            )
    return maps


def map_device_path(name: str) -> str:
    return name if name.startswith("/") else f"/dev/mapper/{name}"


def check_maps(
    maps: list[MapResult], scsi_id_path: str
) -> tuple[list[str], list[tuple[str, str]]]:
    scanned: list[str] = []
    skipped: list[tuple[str, str]] = []
    for multipath_map in maps:
        # Some multipath versions report a WWID that is not a 0x83 value.  In
        # that case, obtain the map identity from the map device itself.
        map_path = map_device_path(multipath_map.name)
        scanned.append(map_path)
        map_wwn, map_error = scsi_id(map_path, scsi_id_path)
        if map_wwn and map_wwn != multipath_map.wwn:
            multipath_map.errors.append(
                f"{map_path}: queried WWN {map_wwn} differs from map WWID {multipath_map.wwn}"
            )
        if map_error:
            multipath_map.errors.append(f"{map_path}: {map_error}")

        if not multipath_map.paths:
            reason = NO_PATHS_REASON
            skipped.append((map_path, reason))
            multipath_map.errors.append(reason)
        for path in multipath_map.paths:
            if path.device in {"/dev/undef", "/dev/-", "/dev/[undef]"}:
                path.error = "multipath listed no usable device node; WWN query skipped"
                skipped.append((path.device, path.error))
                continue
            scanned.append(path.device)
            path.wwn, path.error = scsi_id(path.device, scsi_id_path)
    return scanned, skipped


def print_table(maps: list[MapResult], mismatches_only: bool = False) -> None:
    """Show path identity separately from path availability/health."""
    rows = []
    for device in maps:
        paths = device.mismatched_paths if mismatches_only else device.paths
        for path in paths:
            if path.error or not path.wwn or not device.wwn:
                match = "UNKNOWN"
            elif normalize_wwn(path.wwn) == normalize_wwn(device.wwn):
                match = "YES"
            else:
                match = "NO"
            rows.append(
                [
                    device.name,
                    device.wwn or "UNKNOWN",
                    f"YES ({len(device.paths)})",
                    path.device,
                    path.wwn or "UNKNOWN",
                    match,
                    " / ".join(
                        s for s in (path.state, path.path_state, path.device_state) if s
                    )
                    or "UNKNOWN",
                ]
            )
        if not device.paths and not mismatches_only:
            rows.append(
                [
                    device.name,
                    device.wwn or "UNKNOWN",
                    "NO (0)",
                    "none found",
                    "-",
                    "N/A",
                    "no paths parsed",
                ]
            )
    if not rows:
        return
    headers = [
        "MULTIPATH",
        "MAP WWID",
        "PATHS FOUND",
        "SCSI DEVICE",
        "PATH WWN",
        "WWN MATCH",
        "PATH STATE",
    ]
    widths = [max(len(row[i]) for row in [headers] + rows) for i in range(len(headers))]

    def line(row: list[str]) -> str:
        return " | ".join(value.ljust(width) for value, width in zip(row, widths))

    print(line(headers))
    print("-+-".join("-" * width for width in widths))
    for row in rows:
        print(line(row))


def report_status(maps: list[MapResult]) -> int:
    """WWN verification and path presence/health are independent checks."""
    wwn_failed = not maps or any(
        not m.wwn
        or m.errors
        or m.mismatched_paths
        or any(p.error or not p.wwn for p in m.paths)
        for m in maps
        if m.paths
    )
    paths_failed = not maps or any(
        not m.paths
        or m.failed_paths
        or any(p.device in {"/dev/undef", "/dev/-", "/dev/[undef]"} for p in m.paths)
        for m in maps
    )
    print("WWN    | PATHS")
    print("-------+-------")
    print(
        f"{'FAILED' if wwn_failed else 'OK':<6} | {'FAILED' if paths_failed else 'OK'}"
    )
    return 1 if wwn_failed or paths_failed else 0


def report(
    maps: list[MapResult],
    scanned: list[str],
    skipped: list[tuple[str, str]],
    mismatches_only: bool = False,
    debug: bool = False,
) -> int:
    if debug:
        print("SCANNED DEVICES")
        for device in scanned:
            print(f"  {device}")
        print("SKIPPED DEVICES")
        if skipped:
            for device, reason in skipped:
                if reason != NO_PATHS_REASON:
                    print(f"  {device}: {reason}")
        else:
            print("  none")

    if not debug:
        return report_status(maps)

    print_table(maps, mismatches_only=mismatches_only)
    no_paths_count = sum(not device.paths for device in maps)
    if no_paths_count:
        print(f"Note: {no_paths_count} multipath device(s): {NO_PATHS_REASON}.")

    for multipath_map in maps:
        failed = multipath_map.failed_paths
        mismatched = multipath_map.mismatched_paths
        errors = [error for error in multipath_map.errors if error != NO_PATHS_REASON]
        if not (
            failed or mismatched or errors or any(p.error for p in multipath_map.paths)
        ):
            continue
        print(
            f"MAP {multipath_map.name}: expected WWN {multipath_map.wwn or 'UNKNOWN'}"
        )
        for path in failed:
            status = " ".join(
                value
                for value in (path.state, path.path_state, path.device_state)
                if value
            )
            print(f"  FAILED PATH {path.device} ({path.hctl or 'unknown'}): {status}")
        for path in mismatched:
            print(
                f"  WWN MISMATCH {path.device}: {path.wwn} (expected {multipath_map.wwn})"
            )
        for path in multipath_map.paths:
            if path.error:
                print(f"  UNREADABLE PATH {path.device}: {path.error}")
        for error in errors:
            print(f"  ERROR {error}")
    print("Note: multipath -l does not run path checkers; unchecked is not a failure.")
    return report_status(maps)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scsi-id",
        default=DEFAULT_SCSI_ID,
        help="path to scsi_id (default: %(default)s)",
    )
    parser.add_argument(
        "--multipath",
        default=DEFAULT_MULTIPATH,
        help="multipath command (default: %(default)s)",
    )
    parser.add_argument(
        "--json", action="store_true", help="emit all map/path results as JSON"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="show scanned/skipped devices, diagnostics and the full text report",
    )
    parser.add_argument(
        "--mismatches-only",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="filter the debug table to mismatched paths; by default show all maps and paths; "
        "does not filter JSON or change exit status",
    )
    args = parser.parse_args(argv)

    rc, stdout, stderr = run_command([args.multipath, "-l"])
    if rc != 0:
        if not args.json:
            report_status([])
        if args.debug or args.json:
            print(
                f"error: {args.multipath} -l failed: {stderr or f'exit status {rc}'}",
                file=sys.stderr,
            )
        return 2
    maps = parse_multipath(stdout)
    if not maps:
        if args.json:
            print("[]")
        else:
            report_status([])
            if args.debug:
                print(
                    "Cannot verify devices: multipath -l returned no recognizable topology."
                )
                print(
                    "SCANNED DEVICES\n  none\nSKIPPED DEVICES\n  all: no map headers parsed"
                )
                print(f"{args.multipath} -l exited with status {rc}.")
                print(f"stdout:\n{stdout.strip() or '(empty)'}")
                print(f"stderr:\n{stderr or '(empty)'}")
        return 2
    if stderr and args.debug and not args.json:
        print(f"multipath diagnostics:\n{stderr}")
    scanned, skipped = check_maps(maps, args.scsi_id)
    if args.json:
        print(json.dumps([asdict(m) for m in maps], indent=2, sort_keys=True))
        return 1 if any(m.has_problems for m in maps) else 0
    return report(maps, scanned, skipped, args.mismatches_only, args.debug)


if __name__ == "__main__":
    raise SystemExit(main())
