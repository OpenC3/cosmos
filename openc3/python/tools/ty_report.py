#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""Convert `ty check --output-format=gitlab` output into formats GitHub renders.

ty can emit full, concise, gitlab, github and junit, but not SARIF, which is the
format GitHub Code Scanning reads. Its GitLab Code Quality JSON is structured
and stable, so this converts that into:

  --sarif PATH     SARIF 2.1.0 for github/codeql-action/upload-sarif. Results
                   appear under Security > Code scanning, filterable by rule and
                   annotated inline on the PR diff, with per-result history.
  --markdown PATH  A collapsible summary table for $GITHUB_STEP_SUMMARY.

It also fixes paths. ty reports files inside the working directory as relative
and files outside it as absolute; GitHub only matches results to files when the
SARIF URI is relative to the repository root, so every path is rewritten that
way via --repo-root.

Usage:
    uv run --frozen ty check --output-format=gitlab openc3 > ty.json
    ./tools/ty_report.py --input ty.json --sarif ty.sarif --markdown ty.md
"""

import argparse
import json
import os
import re
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


# GitLab Code Quality severity -> SARIF level
SARIF_LEVEL = {
    "blocker": "error",
    "critical": "error",
    "major": "error",
    "minor": "warning",
    "info": "note",
}

RULE_DOCS = "https://docs.astral.sh/ty/rules/#"

# Code scanning rejects uploads above this many results
SARIF_RESULT_LIMIT = 25_000

# The report is built from JSON supplied on the command line, so nothing in it
# is trusted. Every field is constrained before it reaches the SARIF, which
# GitHub ingests, or the markdown, which is rendered in the job summary.
#
# ty rule names are kebab-case identifiers; anything else is not a rule name
RULE_NAME = re.compile(r"^[a-z][a-z0-9-]{0,63}$")
# ty fingerprints are short hex digests
FINGERPRINT = re.compile(r"^[0-9a-f]{1,64}$", re.IGNORECASE)
MAX_MESSAGE_CHARS = 1_000
MAX_PATH_CHARS = 1_024
# SARIF regions are 1-based; cap at a signed 32-bit int
MAX_POSITION = 2**31 - 1
UNKNOWN_RULE = "unknown-rule"


def clean_text(value: object, limit: int = MAX_MESSAGE_CHARS) -> str:
    """Render an untrusted value as a single-line, length-capped string."""
    text = value if isinstance(value, str) else str(value)
    text = "".join(char if char.isprintable() else " " for char in text)
    return text[:limit].strip()


def clean_position(value: object) -> int:
    """Coerce an untrusted line or column into a valid 1-based SARIF position."""
    if not isinstance(value, int | str):
        return 1
    try:
        number = int(value)
    except ValueError:
        return 1
    return max(1, min(number, MAX_POSITION))


def escape_markdown_cell(value: str) -> str:
    """Neutralize a value interpolated into a markdown table cell.

    A crafted rule name such as `x) [click](http://evil)` would otherwise
    close the link this is interpolated into and inject arbitrary markdown
    into the job summary.
    """
    return re.sub(r"[|\[\]()`\\]", "-", value)


def parse_diagnostics(raw: str, repo_root: Path, cwd: Path) -> tuple[list[dict], list[str]]:
    """Validate and normalize ty's JSON into records the builders can trust.

    Returns the accepted records and a list of human-readable reasons for the
    ones that were dropped.
    """
    if not raw.strip():
        return [], []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as error:
        raise SystemExit(f"input is not valid JSON: {error}") from error
    if not isinstance(parsed, list):
        raise SystemExit(f"expected a JSON array of diagnostics, got {type(parsed).__name__}")

    accepted: list[dict] = []
    dropped: list[str] = []
    for index, entry in enumerate(parsed):
        if len(accepted) >= SARIF_RESULT_LIMIT:
            dropped.append(f"{len(parsed) - index} entries beyond the {SARIF_RESULT_LIMIT} result limit")
            break
        if not isinstance(entry, dict):
            dropped.append(f"entry {index} is {type(entry).__name__}, not an object")
            continue

        location = entry.get("location")
        if not isinstance(location, dict):
            dropped.append(f"entry {index} has no location object")
            continue
        positions = location.get("positions")
        if not isinstance(positions, dict):
            dropped.append(f"entry {index} has no location.positions object")
            continue
        begin = positions.get("begin")
        if not isinstance(begin, dict):
            dropped.append(f"entry {index} has no location.positions.begin object")
            continue
        end = positions.get("end")
        if not isinstance(end, dict):
            end = begin

        path = clean_text(location.get("path", ""), MAX_PATH_CHARS)
        if not path:
            dropped.append(f"entry {index} has no location.path")
            continue
        relative = to_repo_relative(path, repo_root, cwd)
        if Path(relative).is_absolute() or relative.startswith(".."):
            # Outside the repository: GitHub cannot annotate it, and emitting
            # the resolved path would leak the runner's filesystem layout
            dropped.append(f"entry {index} resolves outside the repository")
            continue

        raw_rule = clean_text(entry.get("check_name", ""), 64)
        valid_rule = bool(RULE_NAME.match(raw_rule))
        fingerprint = clean_text(entry.get("fingerprint", ""), 64)

        accepted.append(
            {
                "rule": raw_rule if valid_rule else UNKNOWN_RULE,
                # Only link to the docs for a name that really is a rule name
                "rule_documented": valid_rule,
                "message": clean_text(entry.get("description", "")),
                "severity": clean_text(entry.get("severity", ""), 16).lower(),
                "path": relative,
                "start_line": clean_position(begin.get("line")),
                "start_column": clean_position(begin.get("column")),
                "end_line": clean_position(end.get("line")),
                "end_column": clean_position(end.get("column")),
                "fingerprint": fingerprint if FINGERPRINT.match(fingerprint) else None,
            }
        )
    return accepted, dropped


def allowed_roots(repo_root: Path) -> list[Path]:
    """Directories this script may read from or write to.

    The report paths come from the command line, so they are confined to the
    repository, the working directory, the temp directory, and whatever
    locations the CI runner asked us to write to (GITHUB_STEP_SUMMARY lives
    outside the checkout). Anything else is rejected rather than followed.
    """
    roots = [repo_root, Path.cwd(), Path(tempfile.gettempdir())]
    for variable in ("GITHUB_STEP_SUMMARY", "GITHUB_OUTPUT", "GITHUB_ENV", "RUNNER_TEMP"):
        value = os.environ.get(variable)
        if value:
            candidate = Path(value)
            roots.append(candidate if candidate.is_dir() else candidate.parent)
    resolved = []
    for root in roots:
        try:
            resolved.append(root.resolve(strict=True))
        except OSError:
            continue
    return resolved


def checked_path(path: Path, roots: list[Path], *, must_exist: bool) -> Path:
    """Resolve path and confirm it stays inside one of roots.

    Guards against a traversing or symlinked argument (--sarif ../../etc/foo)
    reaching the file system.
    """
    try:
        resolved = path.resolve(strict=must_exist)
    except OSError as error:
        raise SystemExit(f"cannot resolve {path}: {error}") from error

    if not must_exist and not resolved.parent.is_dir():
        raise SystemExit(f"refusing to write {path}: {resolved.parent} is not an existing directory")
    if resolved.is_symlink():
        raise SystemExit(f"refusing to follow symlink {path}")
    if resolved.is_dir():
        raise SystemExit(f"refusing to use directory {path} as a file")

    if not any(resolved == root or root in resolved.parents for root in roots):
        listed = ", ".join(str(root) for root in roots)
        raise SystemExit(f"refusing to access {resolved}: outside the permitted directories ({listed})")
    return resolved


def to_repo_relative(path: str, repo_root: Path, cwd: Path) -> str:
    """Rewrite a ty path (relative to cwd, or absolute) as repo-root relative."""
    candidate = Path(path)
    absolute = candidate if candidate.is_absolute() else (cwd / candidate)
    try:
        return absolute.resolve().relative_to(repo_root).as_posix()
    except ValueError:
        # Outside the repository: leave it alone rather than emit a bogus URI
        return absolute.resolve().as_posix()


def build_sarif(diagnostics: list[dict], version: str) -> dict:
    rule_ids = sorted({d["rule"] for d in diagnostics})
    rule_index = {name: i for i, name in enumerate(rule_ids)}
    documented = {d["rule"] for d in diagnostics if d["rule_documented"]}

    results = []
    for diagnostic in diagnostics:
        rule = diagnostic["rule"]
        message = diagnostic["message"]
        # ty prefixes the rule name onto the description; drop the duplicate
        prefix = f"{rule}: "
        if message.startswith(prefix):
            message = message[len(prefix) :]

        result = {
            "ruleId": rule,
            "ruleIndex": rule_index[rule],
            "level": SARIF_LEVEL.get(diagnostic["severity"], "warning"),
            "message": {"text": message or "(no description)"},
            "locations": [
                {
                    "physicalLocation": {
                        "artifactLocation": {"uri": diagnostic["path"]},
                        "region": {
                            "startLine": diagnostic["start_line"],
                            "startColumn": diagnostic["start_column"],
                            "endLine": max(diagnostic["end_line"], diagnostic["start_line"]),
                            "endColumn": diagnostic["end_column"],
                        },
                    }
                }
            ],
        }
        if diagnostic["fingerprint"]:
            # ty's own hash, so a result keeps its identity across runs and
            # code scanning can track / dismiss it
            result["partialFingerprints"] = {"tyFingerprint/v1": diagnostic["fingerprint"]}
        results.append(result)

    rules = []
    for name in rule_ids:
        rule_entry = {
            "id": name,
            "name": name,
            "shortDescription": {"text": name.replace("-", " ")},
            "properties": {"tags": ["type-check"]},
        }
        if name in documented:
            rule_entry["helpUri"] = f"{RULE_DOCS}{name}"
        rules.append(rule_entry)

    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "ty",
                        "version": clean_text(version, 32) or "unknown",
                        "informationUri": "https://github.com/astral-sh/ty",
                        "rules": rules,
                    }
                },
                "results": results,
            }
        ],
    }


def build_markdown(diagnostics: list[dict]) -> str:
    if not diagnostics:
        return "## ty type check\n\nNo diagnostics.\n"

    by_rule = Counter(d["rule"] for d in diagnostics)
    documented = {d["rule"] for d in diagnostics if d["rule_documented"]}
    by_file: defaultdict[str, int] = defaultdict(int)
    for diagnostic in diagnostics:
        by_file[diagnostic["path"]] += 1

    lines = [
        "## ty type check",
        "",
        f"**{len(diagnostics)} diagnostics** across {len(by_file)} files.",
        "Full results with inline annotations are under **Security > Code scanning**.",
        "",
        "| rule | count |",
        "| --- | --: |",
    ]
    for rule, count in by_rule.most_common():
        cell = escape_markdown_cell(rule)
        label = f"[`{cell}`]({RULE_DOCS}{rule})" if rule in documented else f"`{cell}`"
        lines.append(f"| {label} | {count} |")

    lines += [
        "",
        f"<details><summary>Top files ({min(len(by_file), 25)} of {len(by_file)})</summary>",
        "",
        "| file | count |",
        "| --- | --: |",
    ]
    ranked = sorted(by_file.items(), key=lambda item: item[1], reverse=True)
    lines += [f"| `{escape_markdown_cell(path)}` | {count} |" for path, count in ranked[:25]]
    lines += ["", "</details>", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="ty gitlab JSON file (default: stdin)")
    parser.add_argument("--sarif", type=Path, help="write SARIF 2.1.0 here")
    parser.add_argument("--markdown", type=Path, help="write a markdown summary here")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[3],
        help="paths in the report are made relative to this (default: repository root)",
    )
    parser.add_argument("--cwd", type=Path, default=Path.cwd(), help="directory ty ran in")
    parser.add_argument("--ty-version", default="unknown", help="recorded in the SARIF tool driver")
    args = parser.parse_args()

    if not args.sarif and not args.markdown:
        parser.error("nothing to do: pass --sarif and/or --markdown")

    repo_root = args.repo_root.resolve()
    cwd = args.cwd.resolve()
    roots = allowed_roots(repo_root)

    input_path = checked_path(args.input, roots, must_exist=True) if args.input else None
    sarif_path = checked_path(args.sarif, roots, must_exist=False) if args.sarif else None
    markdown_path = checked_path(args.markdown, roots, must_exist=False) if args.markdown else None

    raw = input_path.read_text() if input_path else sys.stdin.read()
    diagnostics, dropped = parse_diagnostics(raw, repo_root, cwd)
    for reason in dropped:
        print(f"warning: skipped {reason}", file=sys.stderr)

    if sarif_path:
        sarif_path.write_text(json.dumps(build_sarif(diagnostics, args.ty_version), indent=2) + "\n")
        print(f"wrote {sarif_path} ({len(diagnostics)} results)")

    if markdown_path:
        markdown_path.write_text(build_markdown(diagnostics))
        print(f"wrote {markdown_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
