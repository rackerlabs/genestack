import os
import re
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
        required=True,
        help="Git release tag name, for example: release-2026.1.0",
    )
    return parser.parse_args()


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
    text = re.sub(r"\binternal repository\b", "artifact repository", text, flags=re.IGNORECASE)
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


def choose_reno_version(loader, release_tag):
    if release_tag in loader.versions:
        return release_tag

    series_ref = release_series_ref(release_tag)
    if series_ref and series_ref in loader.versions:
        return series_ref

    if loader.versions and loader.versions[0] != release_tag:
        return loader.versions[0]

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


def iter_disk_release_notes(repo_dir, release_tag):
    version = parse_release_tag(release_tag)
    series = ".".join(version.split(".")[:2])
    note_dir = repo_dir / "releasenotes" / "notes"
    prefixes = (f"release-{series}",)

    for path in sorted(note_dir.glob("*.yaml")):
        if path.name.startswith(prefixes):
            yield str(path.relative_to(repo_dir)), parse_note_file_from_disk(path)


def classify_component(filename, note):
    searchable = filename.lower()
    for alias, component_key in COMPONENT_ALIASES.items():
        if alias in searchable:
            return component_key

    return "miscellaneous"


def empty_component_data(config):
    data = OrderedDict()
    for _, components in COMPONENT_GROUPS.items():
        for component_key in components:
            data[component_key] = OrderedDict()
            data[component_key][config.prelude_section_name] = []
            for section_name, _ in config.sections:
                data[component_key][section_name] = []

    data["miscellaneous"] = OrderedDict()
    data["miscellaneous"][config.prelude_section_name] = []
    for section_name, _ in config.sections:
        data["miscellaneous"][section_name] = []
    return data


def collect_note_data(repo_dir, release_tag):
    config = reno_config.Config(str(repo_dir))

    with reno_loader.Loader(config, ignore_cache=True) as loader:
        reno_version = choose_reno_version(loader, release_tag)
        component_data = empty_component_data(config)

        if reno_version:
            note_items = [
                (filename, loader.parse_note_file(filename, sha))
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

            for section_name, _ in config.sections:
                section_notes = note.get(section_name, [])
                if section_notes:
                    component_data[component_key][section_name].extend(section_notes)

    return config, reno_version, component_data


def component_has_notes(config, component_notes):
    if component_notes.get(config.prelude_section_name):
        return True
    return any(component_notes.get(section_name) for section_name, _ in config.sections)


def group_has_notes(config, component_data, components):
    return any(component_has_notes(config, component_data[key]) for key in components)


def render_component_notes(config, component_notes):
    output = []
    preludes = component_notes.get(config.prelude_section_name, [])
    if preludes:
        output.extend(["#### Prelude", ""])
        for prelude in preludes:
            output.extend(render_paragraph_block(prelude))

    for section_name, section_title in config.sections:
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
            for section_name, section_title in config.sections:
                if component_notes.get(section_name):
                    section_names.append(SECTION_TITLES.get(section_name, section_title))
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
    matrix_output = f"# Product Matrix for {release_tag}\n\n"
    matrix_output += "This matrix is automatically generated from `helm-chart-versions.yaml`.\n\n"
    matrix_output += "| Chart Name | Version |\n"
    matrix_output += "| :--- | :--- |\n"

    for chart, version in charts:
        matrix_output += f"| **{chart}** | `{version}` |\n"

    return matrix_output


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


def generate_product_matrix(repo_dir, release_tag, version):
    input_file = repo_dir / "helm-chart-versions.yaml"
    output_file = repo_dir / "docs" / f"product-matrix-{version}.md"

    with input_file.open() as f:
        data = yaml.safe_load(f)

    if "charts" not in data:
        raise KeyError(f"'charts' key not found in {input_file}")

    charts = sorted(data["charts"].items())
    output_file.write_text(build_product_matrix_output(release_tag, charts))
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
        output.append(
            f"- [Release {release_version}](release-{release_version}.md)"
        )

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
    release_tag = args.release
    version = parse_release_tag(release_tag)
    root = repo_root()

    os.makedirs(root / "docs", exist_ok=True)

    release_doc, github_doc, reno_version = generate_release_notes(
        root, release_tag, version
    )
    matrix_doc = generate_product_matrix(root, release_tag, version)
    release_index = update_release_index(root, version)

    print(f"Generated release notes: {release_doc}")
    print(f"Generated product matrix: {matrix_doc}")
    print(f"Generated GitHub release body: {github_doc}")
    print(f"Updated release index: {release_index}")
    if reno_version == release_tag:
        print(f"Reno release source: {release_tag}")
    else:
        print(f"Target release: {release_tag}")
        print(f"Pre-tag reno source bucket: {reno_version}")


if __name__ == "__main__":
    main()
