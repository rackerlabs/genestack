import subprocess
from argparse import ArgumentParser
from pathlib import Path

import yaml


def parse_args():
    parser = ArgumentParser(description="Generate product matrix documentation.")
    parser.add_argument(
        "--release",
        help="Git release tag name, for example: release-2026.2.0",
    )
    parser.add_argument(
        "--from-tag",
        help="Start of a git diff range, for example: release-2026.1.0",
    )
    parser.add_argument(
        "--to-tag",
        help="End of a git diff range, for example: release-2026.2.0",
    )
    args = parser.parse_args()

    if args.release and (args.from_tag or args.to_tag):
        parser.error("Use either --release or --from-tag/--to-tag, not both.")

    if args.release:
        return args

    if bool(args.from_tag) != bool(args.to_tag):
        parser.error("Both --from-tag and --to-tag are required for range mode.")

    if not args.from_tag:
        parser.error("Either --release or both --from-tag and --to-tag are required.")

    return args


def repo_root():
    return Path(__file__).resolve().parent.parent


def parse_release_tag(release_tag):
    prefix = "release-"
    if not release_tag.startswith(prefix):
        raise ValueError(
            f"Invalid release tag '{release_tag}'. Expected format: release-<version>."
        )
    return release_tag[len(prefix) :]


def git(args, repo_dir):
    return subprocess.check_output(["git", *args], cwd=repo_dir, text=True)


def load_chart_versions(path):
    with path.open() as handle:
        data = yaml.safe_load(handle) or {}
    charts = data.get("charts")
    if charts is None:
        raise KeyError(f"'charts' key not found in {path}")
    return charts


def load_chart_versions_from_tag(repo_dir, tag):
    content = git(["show", f"{tag}:helm-chart-versions.yaml"], repo_dir)
    data = yaml.safe_load(content) or {}
    charts = data.get("charts")
    if charts is None:
        raise KeyError(f"'charts' key not found in helm-chart-versions.yaml at {tag}")
    return charts


def build_product_matrix_output(title, intro, charts, changed_rows=None):
    output = [f"# {title}", "", intro, ""]

    if changed_rows:
        output.extend(
            [
                "## Chart Changes In This Release",
                "",
                "| Chart Name | Previous Version | New Version | Change Type |",
                "| :--- | :--- | :--- | :--- |",
            ]
        )
        for chart_name, previous_version, new_version, change_type in changed_rows:
            output.append(
                f"| **{chart_name}** | `{previous_version}` | `{new_version}` | `{change_type}` |"
            )
        output.append("")

    output.extend(
        [
            "## Current Chart Versions",
            "",
            "| Chart Name | Version |",
            "| :--- | :--- |",
        ]
    )
    for chart_name, version in sorted(charts.items()):
        output.append(f"| **{chart_name}** | `{version}` |")
    output.append("")
    return "\n".join(output)


def build_changed_rows(previous_charts, current_charts):
    changed_rows = []
    chart_names = sorted(set(previous_charts) | set(current_charts))
    for chart_name in chart_names:
        previous_version = previous_charts.get(chart_name)
        current_version = current_charts.get(chart_name)
        if previous_version == current_version:
            continue
        if previous_version is None:
            change_type = "Added"
            previous_display = "-"
            current_display = current_version
        elif current_version is None:
            change_type = "Removed"
            previous_display = previous_version
            current_display = "-"
        else:
            change_type = "Updated"
            previous_display = previous_version
            current_display = current_version
        changed_rows.append(
            (chart_name, previous_display, current_display, change_type)
        )
    return changed_rows


def generate_release_matrix(repo_dir, release_tag, version):
    charts = load_chart_versions(repo_dir / "helm-chart-versions.yaml")
    output_dir = repo_dir / "docs"
    output_dir.mkdir(exist_ok=True)
    output_file = output_dir / f"product-matrix-{version}.md"
    output_file.write_text(
        build_product_matrix_output(
            f"Product Matrix for {release_tag}",
            "This matrix is automatically generated from `helm-chart-versions.yaml`.",
            charts,
        )
    )
    return output_file


def generate_range_matrix(repo_dir, from_tag, to_tag, version):
    previous_charts = load_chart_versions_from_tag(repo_dir, from_tag)
    current_charts = load_chart_versions_from_tag(repo_dir, to_tag)
    changed_rows = build_changed_rows(previous_charts, current_charts)
    output_dir = repo_dir / "docs"
    output_dir.mkdir(exist_ok=True)
    output_file = output_dir / f"product-matrix-{version}.md"
    output_file.write_text(
        build_product_matrix_output(
            f"Product Matrix for {to_tag}",
            (
                "This matrix is generated from the exact git diff between "
                f"`{from_tag}` and `{to_tag}`."
            ),
            current_charts,
            changed_rows=changed_rows,
        )
    )
    return output_file, len(changed_rows)


def generate_product_matrix_index(repo_dir):
    output_file = repo_dir / "docs" / "product-matrix.md"
    output_file.write_text(
        "\n".join(
            [
                "# Product Matrix",
                "All release notes are automatically generated using the **Python script** found in [scripts/generate_product_matrix.py](https://github.com/rackerlabs/genestack/scripts/generate_product_matrix.py).",
                "",
                "To manually generate and update this file, run the following commands from the **root of the repository**:",
                "",
                "```shell",
                "pip install -r doc-requirements.txt -r dev-requirements.txt",
                "python scripts/generate_product_matrix.py --release release-2026.2.0",
                "python scripts/generate_product_matrix.py --from-tag release-2026.1.0 --to-tag release-2026.2.0",
                "```",
                "",
            ]
        )
    )
    return output_file


def main():
    args = parse_args()
    root = repo_root()

    if args.release:
        release_tag = args.release
        version = parse_release_tag(release_tag)
        output_file = generate_release_matrix(root, release_tag, version)
        change_count = None
    else:
        from_tag = args.from_tag
        to_tag = args.to_tag
        parse_release_tag(from_tag)
        version = parse_release_tag(to_tag)
        output_file, change_count = generate_range_matrix(root, from_tag, to_tag, version)

    index_file = generate_product_matrix_index(root)

    print(f"Generated product matrix: {output_file}")
    print(f"Updated product matrix index: {index_file}")
    if change_count is not None:
        print(f"Chart changes identified in range: {change_count}")


if __name__ == "__main__":
    main()
