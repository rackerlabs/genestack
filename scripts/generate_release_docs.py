import os
import re
import subprocess
from argparse import ArgumentParser
from collections import OrderedDict
from pathlib import Path

import yaml
from reno import config as reno_config
from reno import loader as reno_loader


RELEASE_TAG_PATTERN = re.compile(r"release-(?P<version>\d+(?:\.\d+)*)$")
INLINE_LITERAL_PATTERN = re.compile(r"``([^`]+)``")
SENSITIVE_URL_PATTERN = re.compile(
    r"https?://[^\s)`>]*(?:artifactory|containers-internal|rackspacecloud\.com)[^\s)`>]*"
)
SENSITIVE_INTERNAL_PATH_PATTERN = re.compile(
    r"\b[^\s)`>]*(?:artifactory|containers-internal)[^\s)`>]*",
    re.IGNORECASE,
)
SENSITIVE_HOST_PATTERN = re.compile(
    r"\b[a-z0-9][a-z0-9.-]*\.(?:svc\.cluster\.local|rackspacecloud\.com)\b",
    re.IGNORECASE,
)
RELEASE_LINK_PATTERN = re.compile(
    r"^- \[Release (?P<version>\d+(?:\.\d+)*)\]\(release-(?P=version)\.md\)$"
)
CONVENTIONAL_COMMIT_PATTERN = re.compile(
    r"^(?P<type>feat|fix|perf|docs|chore|refactor|security|deprecations?|deprecate)"
    r"(?:\((?P<scope>[^)]+)\))?:\s*(?P<summary>.+)$",
    re.IGNORECASE,
)

SECTION_TITLES = {
    "prelude": "Prelude",
    "features": "New Features",
    "issues": "Known Issues",
    "upgrade": "Upgrade Notes",
    "deprecations": "Deprecations",
    "critical": "Critical Issues",
    "security": "Security Notes",
    "fixes": "Bug Fixes",
    "other": "Other Notes",
}

COMPONENT_GROUPS = OrderedDict(
    [
        (
            "Platform Foundations",
            OrderedDict(
                [
                    ("cert-manager", "Cert-Manager"),
                    ("proxy", "Proxy Environment Handling"),
                    ("mariadb", "MariaDB Operator"),
                    ("memcached", "Memcached"),
                    ("rabbitmq", "RabbitMQ"),
                    ("redis", "Redis"),
                    ("container-distro", "Container Images"),
                    ("maintenance", "Maintenance Runbooks"),
                ]
            ),
        ),
        (
            "Observability and Telemetry",
            OrderedDict(
                [
                    ("observability", "Observability Stack"),
                    ("ceilometer", "Ceilometer"),
                    ("cloudkitty", "CloudKitty"),
                    ("gnocchi", "Gnocchi"),
                ]
            ),
        ),
        (
            "Kubernetes and Container Platform",
            OrderedDict(
                [
                    ("magnum", "Magnum"),
                    ("kube-ovn", "Kube-OVN"),
                    ("kubernetes", "Kubernetes"),
                    ("longhorn", "Longhorn"),
                    ("topolvm", "TopoLVM"),
                ]
            ),
        ),
        (
            "Networking and Load Balancing",
            OrderedDict(
                [
                    ("designate", "Designate"),
                    ("neutron", "Neutron / OVN"),
                    ("octavia", "Octavia"),
                    ("metallb", "MetalLB"),
                    ("envoy", "Envoy Gateway"),
                ]
            ),
        ),
        (
            "Compute and Scheduling",
            OrderedDict(
                [
                    ("blazar", "Blazar"),
                    ("libvirt", "Libvirt"),
                    ("nova", "Nova"),
                    ("placement", "Placement"),
                    ("ironic", "Ironic"),
                    ("masakari", "Masakari"),
                ]
            ),
        ),
        (
            "Identity and Secrets",
            OrderedDict(
                [
                    ("keystone-ldap", "Keystone LDAP/AD"),
                    ("keystone", "Keystone"),
                    ("barbican", "Barbican"),
                    ("sealed-secrets", "Sealed Secrets"),
                ]
            ),
        ),
        (
            "Storage, Images, and Data Protection",
            OrderedDict(
                [
                    ("freezer", "Freezer"),
                    ("cinder", "Cinder"),
                    ("glance", "Glance"),
                    ("trove", "Trove"),
                    ("manila", "Manila"),
                ]
            ),
        ),
        (
            "Orchestration",
            OrderedDict(
                [
                    ("heat", "Heat"),
                    ("horizon", "Horizon"),
                    ("skyline", "Skyline"),
                    ("zaqar", "Zaqar"),
                ]
            ),
        ),
    ]
)

COMPONENT_ALIASES = OrderedDict(
    [
        ("cert-manager", "cert-manager"),
        ("force_proxy", "proxy"),
        ("force-proxy", "proxy"),
        ("proxy", "proxy"),
        ("mariadb", "mariadb"),
        ("memcached", "memcached"),
        ("rabbitmq", "rabbitmq"),
        ("redis", "redis"),
        ("default-container-distro", "container-distro"),
        ("container-distro", "container-distro"),
        ("maintenance-runbooks", "maintenance"),
        ("observability-stack", "observability"),
        ("observability", "observability"),
        ("opentelemetry", "observability"),
        ("ceilometer", "ceilometer"),
        ("cloudkitty", "cloudkitty"),
        ("gnocchi", "gnocchi"),
        ("magnum", "magnum"),
        ("kube-ovn", "kube-ovn"),
        ("kubernetes", "kubernetes"),
        ("kubespray", "kubernetes"),
        ("longhorn", "longhorn"),
        ("topolvm", "topolvm"),
        ("designate", "designate"),
        ("neutron", "neutron"),
        ("ovn", "neutron"),
        ("octavia", "octavia"),
        ("metallb", "metallb"),
        ("envoy", "envoy"),
        ("blazar", "blazar"),
        ("libvirt", "libvirt"),
        ("nova", "nova"),
        ("placement", "placement"),
        ("ironic", "ironic"),
        ("masakari", "masakari"),
        ("keystone-ldap", "keystone-ldap"),
        ("ldap", "keystone-ldap"),
        ("keystone", "keystone"),
        ("barbican", "barbican"),
        ("sealed-secrets", "sealed-secrets"),
        ("freezer", "freezer"),
        ("cinder", "cinder"),
        ("glance", "glance"),
        ("trove", "trove"),
        ("manila", "manila"),
        ("heat", "heat"),
        ("horizon", "horizon"),
        ("skyline", "skyline"),
        ("zaqar", "zaqar"),
    ]
)


def parse_args():
    parser = ArgumentParser(
        description="Generate grouped release notes and product matrix pages."
    )
    parser.add_argument(
        "--release",
        help="Git release tag name, for example: release-2026.1.0",
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


def parse_release_tag(release_tag):
    match = RELEASE_TAG_PATTERN.fullmatch(release_tag)
    if not match:
        raise ValueError(
            f"Invalid release tag '{release_tag}'. Expected format: release-<version>."
        )
    return match.group("version")


def repo_root():
    return Path(__file__).resolve().parent.parent


def normalize_inline_markup(text):
    return INLINE_LITERAL_PATTERN.sub(r"`\1`", text)


def sanitize_text(text):
    text = SENSITIVE_URL_PATTERN.sub("[internal URL redacted]", str(text))
    text = SENSITIVE_INTERNAL_PATH_PATTERN.sub("[internal URL redacted]", text)
    text = SENSITIVE_HOST_PATTERN.sub("[internal host redacted]", text)
    text = re.sub(
        r"`mariadb-cluster-primary`",
        "`[database service host]`",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(
        r"\binternal repository\b", "artifact repository", text, flags=re.IGNORECASE
    )
    text = re.sub(
        r"\binternal\s+`{1,2}[^`]+`{1,2}\s+image\b",
        "patched image",
        text,
        flags=re.IGNORECASE,
    )
    return text


def normalize_paragraphs(text):
    paragraphs = []
    for paragraph in sanitize_text(text).strip().split("\n\n"):
        lines = paragraph.splitlines()
        if any(line.startswith((" ", "\t")) for line in lines):
            normalized = "\n".join(line.rstrip() for line in lines).strip()
        else:
            normalized = " ".join(line.strip() for line in lines).strip()
        if normalized:
            paragraphs.append(normalize_inline_markup(normalized))
    return paragraphs


def render_paragraph_block(text):
    output = []
    for paragraph in normalize_paragraphs(text):
        output.append(paragraph)
        output.append("")
    return output


def render_bullet(text):
    paragraphs = normalize_paragraphs(text)
    if not paragraphs:
        return []

    output = [f"- {paragraphs[0]}"]
    for paragraph in paragraphs[1:]:
        output.append("")
        output.append(f"  {paragraph}")
    output.append("")
    return output


def release_series_ref(release_tag):
    version = parse_release_tag(release_tag)
    parts = version.split(".")
    if len(parts) < 3:
        return None
    return f"release-{'.'.join(parts[:2])}-rc"


def git(args, repo_dir):
    return subprocess.check_output(
        ["git", *args], cwd=repo_dir, text=True
    ).strip()


def git_lines(args, repo_dir):
    output = git(args, repo_dir)
    if not output:
        return []
    return [line for line in output.splitlines() if line.strip()]


def load_chart_versions(repo_dir, release_tag=None):
    if release_tag:
        content = git(["show", f"{release_tag}:helm-chart-versions.yaml"], repo_dir)
        data = yaml.safe_load(content) or {}
    else:
        with (repo_dir / "helm-chart-versions.yaml").open() as handle:
            data = yaml.safe_load(handle) or {}

    charts = data.get("charts")
    if charts is None:
        source = f"helm-chart-versions.yaml at {release_tag}" if release_tag else "helm-chart-versions.yaml"
        raise KeyError(f"'charts' key not found in {source}")
    return charts


def iter_config_sections(config):
    for section in config.sections:
        if hasattr(section, "name"):
            yield section.name, section.title
        else:
            yield section


def choose_reno_version(loader, release_tag):
    if release_tag in loader.versions:
        return release_tag

    series_ref = release_series_ref(release_tag)
    if series_ref and series_ref in loader.versions:
        return series_ref

    return None


def parse_note_file_from_disk(path):
    with path.open() as f:
        note = yaml.safe_load(f) or {}

    for section_name in SECTION_TITLES:
        if section_name == "prelude":
            continue
        value = note.get(section_name)
        if value is None:
            note[section_name] = []
        elif isinstance(value, str):
            note[section_name] = [value]
    return note


def normalize_note(path, note):
    note = note or {}
    component = note.get("component")
    if isinstance(component, list):
        note["component"] = [str(value).strip() for value in component if str(value).strip()]
    elif component is not None:
        note["component"] = str(component).strip()

    for section_name in SECTION_TITLES:
        if section_name == "prelude":
            continue
        value = note.get(section_name)
        if value is None:
            note[section_name] = []
        elif isinstance(value, str):
            note[section_name] = [value]
    return str(path), note


def iter_disk_release_notes(repo_dir, release_tag):
    note_dir = repo_dir / "releasenotes" / "notes"

    for path in sorted(note_dir.glob("*.yaml")):
        yield normalize_note(path.relative_to(repo_dir), parse_note_file_from_disk(path))


def iter_range_release_notes(repo_dir, from_tag, to_tag):
    note_dir = repo_dir / "releasenotes" / "notes"
    changed_files = git_lines(
        ["diff", "--name-only", f"{from_tag}..{to_tag}", "--", "releasenotes/notes"],
        repo_dir,
    )

    for filename in sorted(changed_files):
        path = repo_dir / filename
        if path.exists():
            yield normalize_note(filename, parse_note_file_from_disk(path))


def classify_component(filename, note):
    component = note.get("component")
    if isinstance(component, list):
        component_values = component
    elif component:
        component_values = [component]
    else:
        component_values = []

    for value in component_values:
        component_key = classify_component_from_text(value)
        if component_key != "miscellaneous":
            return component_key

    component_key = classify_component_from_text(filename)
    if component_key != "miscellaneous":
        return component_key

    return "miscellaneous"


def empty_component_data(config):
    data = OrderedDict()
    for _, components in COMPONENT_GROUPS.items():
        for component_key in components:
            data[component_key] = OrderedDict()
            data[component_key][config.prelude_section_name] = []
            for section_name, _ in iter_config_sections(config):
                data[component_key][section_name] = []

    data["miscellaneous"] = OrderedDict()
    data["miscellaneous"][config.prelude_section_name] = []
    for section_name, _ in iter_config_sections(config):
        data["miscellaneous"][section_name] = []
    return data


def empty_commit_data():
    data = OrderedDict()
    for _, components in COMPONENT_GROUPS.items():
        for component_key in components:
            data[component_key] = []
    data["miscellaneous"] = []
    return data


def classify_component_from_text(*values):
    searchable = " ".join(str(value).lower() for value in values if value)
    for alias, component_key in COMPONENT_ALIASES.items():
        if alias in searchable:
            return component_key
    return "miscellaneous"


def collect_note_data(repo_dir, release_tag):
    config = reno_config.Config(str(repo_dir))

    with reno_loader.Loader(config, ignore_cache=True) as loader:
        reno_version = choose_reno_version(loader, release_tag)
        component_data = empty_component_data(config)

        if reno_version:
            note_items = [
                (filename, normalize_note(filename, loader.parse_note_file(filename, sha))[1])
                for filename, sha in loader[reno_version]
            ]
        else:
            note_items = list(iter_disk_release_notes(repo_dir, release_tag))

        for filename, note in note_items:
            component_key = classify_component(filename, note)

            prelude = note.get(config.prelude_section_name)
            if prelude:
                component_data[component_key][config.prelude_section_name].append(
                    prelude
                )

            for section_name, _ in iter_config_sections(config):
                section_notes = note.get(section_name, [])
                if section_notes:
                    component_data[component_key][section_name].extend(section_notes)

    return config, reno_version, component_data


def collect_range_note_data(repo_dir, from_tag, to_tag):
    config = reno_config.Config(str(repo_dir))
    component_data = empty_component_data(config)
    note_items = list(iter_range_release_notes(repo_dir, from_tag, to_tag))

    for filename, note in note_items:
        component_key = classify_component(filename, note)

        prelude = note.get(config.prelude_section_name)
        if prelude:
            component_data[component_key][config.prelude_section_name].append(prelude)

        for section_name, _ in iter_config_sections(config):
            section_notes = note.get(section_name, [])
            if section_notes:
                component_data[component_key][section_name].extend(section_notes)

    return config, note_items, component_data


def format_commit_summary(subject):
    match = CONVENTIONAL_COMMIT_PATTERN.match(subject)
    if not match:
        return subject.strip()

    commit_type = match.group("type").lower()
    summary = match.group("summary").strip()
    type_labels = {
        "feat": "Feature",
        "fix": "Fix",
        "perf": "Performance",
        "docs": "Docs",
        "chore": "Chore",
        "refactor": "Refactor",
        "security": "Security",
        "deprecation": "Deprecation",
        "deprecations": "Deprecation",
        "deprecate": "Deprecation",
    }
    label = type_labels.get(commit_type, commit_type.capitalize())
    return f"{label}: {summary}"


def collect_commit_supplement(repo_dir, from_tag, to_tag):
    commit_data = empty_commit_data()
    log_lines = git_lines(
        ["log", "--format=%H%x1f%s", "--no-merges", f"{from_tag}..{to_tag}"],
        repo_dir,
    )

    for line in log_lines:
        commit_sha, subject = line.split("\x1f", 1)
        paths = git_lines(["show", "--format=", "--name-only", commit_sha], repo_dir)
        if any(path.startswith("releasenotes/notes/") for path in paths):
            continue

        match = CONVENTIONAL_COMMIT_PATTERN.match(subject)
        scope = match.group("scope") if match else ""
        component_key = classify_component_from_text(scope, subject, " ".join(paths))
        commit_data[component_key].append(format_commit_summary(subject))

    return commit_data


def commit_data_has_entries(commit_data):
    return any(commit_data.values())


def component_has_notes(config, component_notes):
    if component_notes.get(config.prelude_section_name):
        return True
    return any(
        component_notes.get(section_name)
        for section_name, _ in iter_config_sections(config)
    )


def group_has_notes(config, component_data, components):
    return any(component_has_notes(config, component_data[key]) for key in components)


def component_has_commits(commit_data, component_key):
    return bool(commit_data.get(component_key))


def group_has_commits(commit_data, components):
    return any(component_has_commits(commit_data, component_key) for component_key in components)


def render_component_notes(config, component_notes):
    output = []
    preludes = component_notes.get(config.prelude_section_name, [])
    if preludes:
        output.extend(["#### Prelude", ""])
        for prelude in preludes:
            output.extend(render_paragraph_block(prelude))

    for section_name, section_title in iter_config_sections(config):
        notes = component_notes.get(section_name, [])
        if not notes:
            continue

        title = SECTION_TITLES.get(section_name, section_title)
        output.extend([f"#### {title}", ""])
        for note in notes:
            output.extend(render_bullet(note))

    return output


def render_components_index(config, component_data):
    output = ["## Components", ""]
    for group_title, components in COMPONENT_GROUPS.items():
        if group_has_notes(config, component_data, components):
            output.append(f"- [{group_title}](#{slugify(group_title)})")
    if component_has_notes(config, component_data["miscellaneous"]):
        output.append("- [Other Release Notes](#other-release-notes)")
    output.append("")
    return output


def render_commit_supplement_index(commit_data):
    output = [
        "## Additional Changes From Git History",
        "",
        "These items were derived from commit history in the same tag range when no curated reno note was present.",
        "",
    ]
    for group_title, components in COMPONENT_GROUPS.items():
        if group_has_commits(commit_data, components):
            output.append(f"- [{group_title} Git History](#{slugify(f'{group_title} Git History')})")
    if component_has_commits(commit_data, "miscellaneous"):
        output.append("- [Other Git History](#other-git-history)")
    output.append("")
    return output


def slugify(value):
    value = value.lower().replace("/", "")
    value = re.sub(r"[^a-z0-9 -]", "", value)
    return re.sub(r"\s+", "-", value.strip())


def build_release_notes_output(release_tag, version, config, component_data):
    output = [
        f"# Release {version}",
        "",
        "This release note set is organized by component to make upgrade planning and validation easier.",
        "",
        f"[Product Matrix](product-matrix-{version}.md)",
        "",
    ]
    output.extend(render_components_index(config, component_data))

    for group_title, components in COMPONENT_GROUPS.items():
        if not group_has_notes(config, component_data, components):
            continue

        output.extend([f"## {group_title}", ""])
        for component_key, component_title in components.items():
            component_notes = component_data[component_key]
            if not component_has_notes(config, component_notes):
                continue

            output.extend([f"### {component_title}", ""])
            output.extend(render_component_notes(config, component_notes))

    if component_has_notes(config, component_data["miscellaneous"]):
        output.extend(["## Other Release Notes", "", "### Miscellaneous", ""])
        output.extend(render_component_notes(config, component_data["miscellaneous"]))

    return "\n".join(output).rstrip() + "\n"


def build_range_release_notes_output(
    from_tag, to_tag, version, config, component_data, commit_data
):
    output = [
        f"# Release {version}",
        "",
        f"This release note set covers the exact git diff from `{from_tag}` to `{to_tag}`.",
        "Curated reno note fragments are listed first. Supplemental commit-derived items are listed separately afterward.",
        "",
        f"[Product Matrix](product-matrix-{version}.md)",
        "",
    ]
    output.extend(render_components_index(config, component_data))
    if commit_data_has_entries(commit_data):
        output.extend(render_commit_supplement_index(commit_data))

    for group_title, components in COMPONENT_GROUPS.items():
        if not group_has_notes(config, component_data, components):
            continue

        output.extend([f"## {group_title}", ""])
        for component_key, component_title in components.items():
            component_notes = component_data[component_key]
            if not component_has_notes(config, component_notes):
                continue

            output.extend([f"### {component_title}", ""])
            output.extend(render_component_notes(config, component_notes))

    if component_has_notes(config, component_data["miscellaneous"]):
        output.extend(["## Other Release Notes", "", "### Miscellaneous", ""])
        output.extend(render_component_notes(config, component_data["miscellaneous"]))

    if commit_data_has_entries(commit_data):
        for group_title, components in COMPONENT_GROUPS.items():
            if not group_has_commits(commit_data, components):
                continue

            output.extend([f"## {group_title} Git History", ""])
            for component_key, component_title in components.items():
                if not component_has_commits(commit_data, component_key):
                    continue
                output.extend([f"### {component_title}", ""])
                for summary in commit_data[component_key]:
                    output.extend(render_bullet(summary))

        if component_has_commits(commit_data, "miscellaneous"):
            output.extend(["## Other Git History", "", "### Miscellaneous", ""])
            for summary in commit_data["miscellaneous"]:
                output.extend(render_bullet(summary))

    return "\n".join(output).rstrip() + "\n"


def build_github_release_output(release_tag, version, config, component_data):
    version_parts = version.split(".")
    release_branch = f"release-{'.'.join(version_parts[:2])}"
    release_type = "Initial" if version_parts[-1] == "0" else "Patch"
    output = [
        f"# Genestack {release_tag}",
        "",
        f"{release_type} Genestack {version} release from the `{release_branch}` release branch.",
        "",
        "## Release Artifacts",
        "",
        f"- Release notes: `docs/release-{version}.md`",
        f"- Product matrix: `docs/product-matrix-{version}.md`",
        "",
        "## Highlights",
        "",
    ]

    for group_title, components in COMPONENT_GROUPS.items():
        if not group_has_notes(config, component_data, components):
            continue

        output.extend([f"### {group_title}", ""])
        for component_key, component_title in components.items():
            component_notes = component_data[component_key]
            if not component_has_notes(config, component_notes):
                continue

            section_names = []
            if component_notes.get(config.prelude_section_name):
                section_names.append("Prelude")
            for section_name, section_title in iter_config_sections(config):
                if component_notes.get(section_name):
                    section_names.append(
                        SECTION_TITLES.get(section_name, section_title)
                    )
            output.append(f"- **{component_title}**: {', '.join(section_names)}")
        output.append("")

    if component_has_notes(config, component_data["miscellaneous"]):
        output.extend(["### Other Release Notes", ""])
        output.append("- **Miscellaneous**: additional release notes")
        output.append("")

    output.extend(
        [
            "## Detailed Notes",
            "",
            "See the generated release notes document for the full per-service details.",
            "",
        ]
    )
    return "\n".join(output).rstrip() + "\n"


def build_product_matrix_output(release_tag, charts):
    output = [
        f"# Product Matrix for {release_tag}",
        "",
        "This matrix is automatically generated from `helm-chart-versions.yaml`.",
        "",
        "## Current Chart Versions",
        "",
        "| Chart Name | Version |",
        "| :--- | :--- |",
    ]

    for chart, version in charts:
        output.append(f"| **{chart}** | `{version}` |")

    output.append("")
    return "\n".join(output)


def build_chart_change_rows(previous_charts, current_charts):
    change_rows = []
    chart_names = sorted(set(previous_charts) | set(current_charts))
    for chart_name in chart_names:
        previous_version = previous_charts.get(chart_name)
        current_version = current_charts.get(chart_name)
        if previous_version == current_version:
            continue
        if previous_version is None:
            change_rows.append((chart_name, "-", current_version, "Added"))
        elif current_version is None:
            change_rows.append((chart_name, previous_version, "-", "Removed"))
        else:
            change_rows.append((chart_name, previous_version, current_version, "Updated"))
    return change_rows


def build_range_product_matrix_output(from_tag, to_tag, charts, change_rows):
    output = [
        f"# Product Matrix for {to_tag}",
        "",
        f"This matrix is generated from the exact git diff between `{from_tag}` and `{to_tag}`.",
        "",
    ]

    if change_rows:
        output.extend(
            [
                "## Chart Changes In This Release",
                "",
                "| Chart Name | Previous Version | New Version | Change Type |",
                "| :--- | :--- | :--- | :--- |",
            ]
        )
        for chart_name, previous_version, current_version, change_type in change_rows:
            output.append(
                f"| **{chart_name}** | `{previous_version}` | `{current_version}` | `{change_type}` |"
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
    for chart_name, version in charts:
        output.append(f"| **{chart_name}** | `{version}` |")
    output.append("")
    return "\n".join(output)


def generate_release_notes(repo_dir, release_tag, version):
    release_doc = repo_dir / "docs" / f"release-{version}.md"
    config, reno_version, component_data = collect_note_data(repo_dir, release_tag)
    release_doc.write_text(
        build_release_notes_output(release_tag, version, config, component_data)
    )

    dist_dir = repo_dir / "dist"
    dist_dir.mkdir(exist_ok=True)
    github_doc = dist_dir / f"release-notes-{release_tag}.md"
    github_doc.write_text(
        build_github_release_output(release_tag, version, config, component_data)
    )
    return release_doc, github_doc, reno_version


def generate_range_release_notes(repo_dir, from_tag, to_tag, version):
    release_doc = repo_dir / "docs" / f"release-{version}.md"
    config, note_items, component_data = collect_range_note_data(repo_dir, from_tag, to_tag)
    commit_data = collect_commit_supplement(repo_dir, from_tag, to_tag)
    release_doc.write_text(
        build_range_release_notes_output(
            from_tag, to_tag, version, config, component_data, commit_data
        )
    )

    dist_dir = repo_dir / "dist"
    dist_dir.mkdir(exist_ok=True)
    github_doc = dist_dir / f"release-notes-{to_tag}.md"
    github_doc.write_text(
        "\n".join(
            [
                f"# Genestack {to_tag}",
                "",
                f"Release notes generated from the exact git diff `{from_tag}..{to_tag}`.",
                "",
                f"- Release notes: `docs/release-{version}.md`",
                f"- Product matrix: `docs/product-matrix-{version}.md`",
                f"- Reno note files included: `{len(note_items)}`",
                f"- Commit-history supplement groups included: `{sum(1 for values in commit_data.values() if values)}`",
                "",
                "See the generated release notes document for the full per-service details.",
                "",
            ]
        )
    )
    return release_doc, github_doc, len(note_items)


def generate_product_matrix(repo_dir, release_tag, version):
    output_file = repo_dir / "docs" / f"product-matrix-{version}.md"
    charts = sorted(load_chart_versions(repo_dir).items())
    output_file.write_text(build_product_matrix_output(release_tag, charts))
    return output_file


def generate_range_product_matrix(repo_dir, from_tag, to_tag, version):
    output_file = repo_dir / "docs" / f"product-matrix-{version}.md"
    previous_charts = load_chart_versions(repo_dir, from_tag)
    current_charts = load_chart_versions(repo_dir, to_tag)
    change_rows = build_chart_change_rows(previous_charts, current_charts)
    output_file.write_text(
        build_range_product_matrix_output(
            from_tag, to_tag, sorted(current_charts.items()), change_rows
        )
    )
    return output_file


def release_sort_key(version):
    return tuple(int(part) for part in version.split("."))


def update_release_index(repo_dir, version):
    release_notes_file = repo_dir / "docs" / "release-notes.md"
    versions = set()
    if release_notes_file.exists():
        for line in release_notes_file.read_text().splitlines():
            match = RELEASE_LINK_PATTERN.match(line)
            if match:
                versions.add(match.group("version"))

    versions.add(version)
    versions.discard("2026.1")
    sorted_versions = sorted(versions, key=release_sort_key, reverse=True)

    output = [
        "# Release Notes",
        "",
        "This page is the navigation index for versioned Genestack release notes.",
        "",
        "## Available Releases",
        "",
    ]
    for release_version in sorted_versions:
        output.append(f"- [Release {release_version}](release-{release_version}.md)")

    output.extend(
        [
            "",
            "## Maintainer Notes",
            "",
            "Versioned release notes are generated from [reno](https://docs.openstack.org/reno/latest/) and then published as separate documentation pages.",
            "",
            "Example generation workflow:",
            "",
            "```shell",
            "pip install -r doc-requirements.txt -r dev-requirements.txt",
            f"python scripts/generate_release_docs.py --release release-{version}",
            "```",
            "",
        ]
    )
    release_notes_file.write_text("\n".join(output))
    return release_notes_file


def main():
    args = parse_args()
    root = repo_root()

    os.makedirs(root / "docs", exist_ok=True)

    if args.release:
        release_tag = args.release
        version = parse_release_tag(release_tag)
        release_doc, github_doc, reno_version = generate_release_notes(
            root, release_tag, version
        )
        matrix_doc = generate_product_matrix(root, release_tag, version)
    else:
        from_tag = args.from_tag
        to_tag = args.to_tag
        parse_release_tag(from_tag)
        version = parse_release_tag(to_tag)
        release_tag = to_tag
        release_doc, github_doc, reno_version = generate_range_release_notes(
            root, from_tag, to_tag, version
        )
        matrix_doc = generate_range_product_matrix(root, from_tag, to_tag, version)
    release_index = update_release_index(root, version)

    print(f"Generated release notes: {release_doc}")
    print(f"Generated product matrix: {matrix_doc}")
    print(f"Generated GitHub release body: {github_doc}")
    print(f"Updated release index: {release_index}")
    if args.release and reno_version == release_tag:
        print(f"Reno release source: {release_tag}")
    elif args.release:
        print(f"Target release: {release_tag}")
        print(f"Pre-tag reno source bucket: {reno_version}")
    else:
        print(f"Target release: {release_tag}")
        print(f"Range mode reno note files: {reno_version}")


if __name__ == "__main__":
    main()
