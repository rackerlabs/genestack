#!/usr/bin/env python3

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAINTENANCES_DIR = ROOT / "maintenances"

TITLE_RE = re.compile(r"^###\s+(.*\S)\s*$")
SECTION_RE = re.compile(r"^##\s+(.*\S)\s*$")
STEP_RE = re.compile(r"^#\s+(.*\S)\s*$")
DEEP_HEADER_RE = re.compile(r"^#{4,}\s+(.*\S)\s*$")
FENCE_RE = re.compile(r"^\s*```")
ADMONITION_RE = re.compile(r"^\s*!!!\s+(\w+)")
CONFLICT_RE = re.compile(r"^(<<<<<<<|=======|>>>>>>>)(.*)$")
SHELL_PROMPT_RE = re.compile(r"^\s*\$\s+(.+)$")
PATH_PROMPT_RE = re.compile(r"^\s*-\s+[^$]+\$\s+(.+)$")
YAMLISH_RE = re.compile(
    r"^(---|\.\.\.|[A-Za-z0-9_.\"'/-]+\s*:\s*.*|-\s+[A-Za-z0-9_.\"'{\[]+.*)$"
)

SECTION_HEADERS = {
    "Notes",
    "Validation",
    "Goal",
    "Prep",
    "Execute",
    "Post-Maint",
    "Troubleshooting",
    "Sources",
    "Kubespray",
    "Kubernetes",
    "Execute Uninstalls",
    "Execute Installs",
}

STEP_HEADERS = {
    "Deployment Node",
    "Configuration Review",
    "Pre-Change Safety Checks",
    "Update the Target Version",
    "Apply Required Overrides or Patches",
    "Run the Maintenance",
    "UI Steps",
    "Common Failure Signal",
    "Rollback",
    "Additional Recovery Actions",
    "Select Storage Nodes",
    "Prevent Longhorn from Using Unlabeled Nodes",
    "Update Longhorn Overrides",
    "Bump the Chart Version",
    "Required CRD Migration for the 1.10 Upgrade",
    "Execute the Upgrade",
    "Rollback Signal",
    "If System-Managed Pods Stay on the Wrong Nodes",
    "If Old Instance-Managers Remain After the Upgrade",
    "Validate Kubespray Version",
    "Ensure kubeadm Upgrade Task Is Patched",
    "Validate Inventory and Node Reachability",
    "Refresh Ansible Facts",
    "Determine the Target Kubernetes Version",
    "Upgrade the Control Plane and etcd Nodes First",
    "Upgrade OpenStack Worker and Network Nodes",
    "Upgrade Compute Nodes",
    "Upgrade Block Nodes",
    "Install a Matching kubectl",
    "Manual kubeadm Upgrade on the First Controller",
    "Re-Apply the kubeadm Upgrade Task Patch",
    "Take backups",
    "Impact",
    "Grafana post-maint",
    "General verification",
}

STEP_PREFIXES = ("Workload Restart Patterns After ",)

COMMAND_PREFIXES = (
    "/",
    "./",
    "ansible",
    "awk",
    "base64",
    "bind-key",
    "cat ",
    "cd ",
    "chmod",
    "curl ",
    "done",
    "echo ",
    "egrep ",
    "exec ",
    "export ",
    "fi",
    "for ",
    "function ",
    "git ",
    "grep ",
    "helm ",
    "if ",
    "kubectl ",
    "ln ",
    "local ",
    "ls ",
    "mkdir ",
    "PRIMARY_POD=",
    "MARIADB_",
    "PODS=",
    "python ",
    "return ",
    "sed ",
    "set ",
    "sleep ",
    "tmux ",
    "VERSION_FILE=",
    "while ",
)

COMMAND_EXACT = {"do", "else", "esac", "EOF", "then"}


def strip_prompt(text: str) -> str:
    match = SHELL_PROMPT_RE.match(text)
    if match:
        return match.group(1)

    match = PATH_PROMPT_RE.match(text)
    if match:
        return match.group(1)

    return text


def is_title_case_heading(text: str) -> bool:
    if text in SECTION_HEADERS or text in STEP_HEADERS:
        return True

    if any(text.startswith(prefix) for prefix in STEP_PREFIXES):
        return True

    if len(text) > 90 or text.endswith(":"):
        return False

    if text.endswith(".") and text not in {"Impact"}:
        return False

    if any(ch in text for ch in (";", '"', "{", "}", "|")):
        return False

    words = text.replace("/", " ").replace("-", " ").split()
    if not words:
        return False

    return all(word[:1].isupper() or word[:1].isdigit() for word in words)


def classify_txt_heading(text: str, is_first_content_line: bool) -> str | None:
    if is_first_content_line:
        return f"### {text}"

    if text in SECTION_HEADERS:
        return f"### {text}"

    if text in STEP_HEADERS or any(text.startswith(prefix) for prefix in STEP_PREFIXES):
        return f"## {text}"

    if is_title_case_heading(text):
        return f"## {text}"

    return None


def is_command(line: str, in_heredoc: bool) -> bool:
    stripped = strip_prompt(line.strip())
    if not stripped:
        return False

    if in_heredoc:
        return True

    if stripped in COMMAND_EXACT:
        return True

    if stripped.startswith(("<<", ">>")):
        return True

    if any(stripped.startswith(prefix) for prefix in COMMAND_PREFIXES):
        return True

    if stripped.startswith(("SHOW ", "CREATE ", "DROP ", "ALTER ", "STOP ", "RESET ")):
        return True

    if stripped.startswith(("apiVersion:", "kind:", "metadata:", "spec:")):
        return False

    if re.match(r"^[A-Z_][A-Z0-9_]*=", stripped):
        return True

    return False


def is_yaml_line(line: str, yaml_mode: bool, yaml_trigger: bool) -> bool:
    stripped = line.strip()
    if not stripped:
        return False

    indent = len(line) - len(line.lstrip(" "))

    if stripped in {"---", "..."}:
        return True

    if not (yaml_mode or yaml_trigger):
        return False

    if stripped.startswith("#"):
        return True

    if indent >= 2:
        return True

    if YAMLISH_RE.match(stripped):
        return True

    return False


def comment_line(text: str) -> str:
    stripped = text.strip()
    if not stripped:
        return ""

    if stripped.startswith("#"):
        return stripped

    return f"# {stripped}"


def normalize_md_lines(text: str) -> list[str]:
    lines = []
    in_fence = False
    for raw_line in text.splitlines():
        if CONFLICT_RE.match(raw_line):
            continue

        if FENCE_RE.match(raw_line):
            in_fence = not in_fence
            continue

        line = raw_line.rstrip()
        if in_fence:
            lines.append(strip_prompt(line))
        else:
            lines.append(line)

    return lines


def normalize_txt_lines(text: str) -> list[str]:
    normalized = []
    for line in text.splitlines():
        if CONFLICT_RE.match(line):
            continue
        line = re.sub(r"^(###)\s+###\s+", r"\1 ", line.rstrip())
        line = re.sub(r"^(##)\s+##\s+", r"\1 ", line)
        normalized.append(line)
    return normalized


def convert_lines(lines: list[str], from_md: bool) -> str:
    output: list[str] = []
    previous_non_empty = ""
    previous_source = ""
    yaml_mode = False
    in_heredoc = False
    heredoc_end = ""
    command_continuation = False
    open_double_quotes = False
    first_content_line = True

    for line in lines:
        stripped = line.strip()
        previous_source_core = (
            previous_source[2:] if previous_source.startswith("# ") else previous_source
        )
        yaml_trigger_context = (
            previous_source_core.endswith("with:")
            or previous_source_core == "Set:"
            or (
                previous_source_core.startswith("Edit ")
                and previous_source_core.endswith((".yaml:", ".yml:"))
            )
        )

        if not stripped:
            output.append("")
            previous_non_empty = ""
            if not command_continuation and not yaml_mode and not yaml_trigger_context:
                previous_source = ""
            continue

        if from_md:
            deep_header_match = DEEP_HEADER_RE.match(line)
            if deep_header_match:
                output.append(f"## {deep_header_match.group(1).strip()}")
                previous_non_empty = output[-1]
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

            title_match = TITLE_RE.match(line)
            if title_match:
                output.append(f"### {title_match.group(1).strip()}")
                previous_non_empty = output[-1]
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

            section_match = SECTION_RE.match(line)
            if section_match:
                output.append(f"### {section_match.group(1).strip()}")
                previous_non_empty = output[-1]
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

            step_match = STEP_RE.match(line)
            if step_match:
                output.append(f"## {step_match.group(1).strip()}")
                previous_non_empty = output[-1]
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

            admonition_match = ADMONITION_RE.match(line)
            if admonition_match:
                output.append(f"# {admonition_match.group(1).capitalize()}")
                previous_non_empty = output[-1]
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue
        else:
            if stripped.startswith(("### ", "## ")):
                output.append(stripped)
                previous_non_empty = stripped
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

            heading = classify_txt_heading(stripped, first_content_line)
            if heading:
                output.append(heading)
                previous_non_empty = heading
                previous_source = stripped
                first_content_line = False
                yaml_mode = False
                command_continuation = False
                open_double_quotes = False
                continue

        first_content_line = False

        if in_heredoc:
            if stripped == heredoc_end or stripped == f"# {heredoc_end}":
                output.append(heredoc_end)
                in_heredoc = False
                heredoc_end = ""
            else:
                output.append(line)
            previous_non_empty = output[-1]
            previous_source = stripped
            continue

        if command_continuation:
            continuation_line = line.rstrip()
            if continuation_line.lstrip().startswith("# "):
                continuation_line = re.sub(r"^\s*#\s?", "", continuation_line)
            output.append(strip_prompt(continuation_line))
            previous_non_empty = output[-1]
            previous_source = stripped
            if not output[-1].rstrip().endswith("\\"):
                open_double_quotes ^= bool(len(re.findall(r'(?<!\\)"', output[-1])) % 2)
            command_continuation = (
                output[-1].rstrip().endswith("\\") or open_double_quotes
            )
            continue

        if previous_non_empty.rstrip().endswith("\\") and line.lstrip().startswith(
            ("-", "--", '"', ">", "|")
        ):
            output.append(line.rstrip())
            previous_non_empty = output[-1]
            previous_source = stripped
            command_continuation = output[-1].rstrip().endswith("\\")
            continue

        command_candidate = strip_prompt(stripped)
        heredoc_match = re.search(r"<<['\"]?([A-Za-z0-9_]+)['\"]?$", command_candidate)
        if heredoc_match and is_command(command_candidate, False):
            output.append(command_candidate)
            in_heredoc = True
            heredoc_end = heredoc_match.group(1)
            previous_non_empty = output[-1]
            previous_source = stripped
            yaml_mode = False
            continue

        yaml_trigger = yaml_trigger_context
        line_is_yaml = is_yaml_line(line, yaml_mode, yaml_trigger)
        if line_is_yaml and not is_command(line, False):
            yaml_line = line.rstrip()
            stripped_yaml = yaml_line.strip()
            if stripped_yaml.startswith("# "):
                candidate = stripped_yaml[2:]
                if YAMLISH_RE.match(candidate):
                    yaml_line = candidate
                else:
                    yaml_line = stripped_yaml
            elif stripped_yaml.startswith("#"):
                yaml_line = stripped_yaml
            output.append(yaml_line)
            previous_non_empty = output[-1]
            previous_source = stripped
            yaml_mode = True
            continue

        yaml_mode = False

        if is_command(line, False):
            output.append(command_candidate)
            open_double_quotes = bool(
                len(re.findall(r'(?<!\\)"', command_candidate)) % 2
            )
            command_continuation = (
                output[-1].rstrip().endswith("\\") or open_double_quotes
            )
        else:
            output.append(comment_line(line))
            command_continuation = False
            open_double_quotes = False

        previous_non_empty = output[-1]
        previous_source = stripped

    while output and output[-1] == "":
        output.pop()

    return "\n".join(output) + "\n"


def main() -> None:
    for txt_path in sorted(MAINTENANCES_DIR.glob("*.txt")):
        md_path = txt_path.with_suffix(".md")
        if md_path.exists():
            source_lines = normalize_md_lines(md_path.read_text())
            rendered = convert_lines(source_lines, from_md=True)
        else:
            source_lines = normalize_txt_lines(txt_path.read_text())
            rendered = convert_lines(source_lines, from_md=False)

        txt_path.write_text(rendered)

    for md_path in sorted(MAINTENANCES_DIR.glob("*.md")):
        txt_path = md_path.with_suffix(".txt")
        if txt_path.exists():
            continue

        source_lines = normalize_md_lines(md_path.read_text())
        rendered = convert_lines(source_lines, from_md=True)
        txt_path.write_text(rendered)


if __name__ == "__main__":
    main()
