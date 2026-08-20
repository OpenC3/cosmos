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
    rule_ids = sorted({d["check_name"] for d in diagnostics})
    rule_index = {name: i for i, name in enumerate(rule_ids)}

    results = []
    for diagnostic in diagnostics:
        rule = diagnostic["check_name"]
        begin = diagnostic["location"]["positions"]["begin"]
        end = diagnostic["location"]["positions"].get("end", begin)
        message = diagnostic["description"]
        # ty prefixes the rule name onto the description; drop the duplicate
        prefix = f"{rule}: "
        if message.startswith(prefix):
            message = message[len(prefix) :]

        results.append(
            {
                "ruleId": rule,
                "ruleIndex": rule_index[rule],
                "level": SARIF_LEVEL.get(diagnostic["severity"], "warning"),
                "message": {"text": message},
                "locations": [
                    {
                        "physicalLocation": {
                            "artifactLocation": {"uri": diagnostic["location"]["path"]},
                            "region": {
                                "startLine": begin["line"],
                                "startColumn": begin["column"],
                                "endLine": end["line"],
                                "endColumn": end["column"],
                            },
                        }
                    }
                ],
                # ty's own hash, so a result keeps its identity across runs and
                # code scanning can track / dismiss it
                "partialFingerprints": {"tyFingerprint/v1": diagnostic["fingerprint"]},
            }
        )

    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "ty",
                        "version": version,
                        "informationUri": "https://github.com/astral-sh/ty",
                        "rules": [
                            {
                                "id": name,
                                "name": name,
                                "shortDescription": {"text": name.replace("-", " ")},
                                "helpUri": f"{RULE_DOCS}{name}",
                                "properties": {"tags": ["type-check"]},
                            }
                            for name in rule_ids
                        ],
                    }
                },
                "results": results,
            }
        ],
    }


def build_markdown(diagnostics: list[dict]) -> str:
    if not diagnostics:
        return "## ty type check\n\nNo diagnostics.\n"

    by_rule = Counter(d["check_name"] for d in diagnostics)
    by_file: defaultdict[str, Counter] = defaultdict(Counter)
    for diagnostic in diagnostics:
        by_file[diagnostic["location"]["path"]][diagnostic["check_name"]] += 1

    lines = [
        "## ty type check",
        "",
        f"**{len(diagnostics)} diagnostics** across {len(by_file)} files.",
        "Full results with inline annotations are under **Security > Code scanning**.",
        "",
        "| rule | count |",
        "| --- | --: |",
    ]
    lines += [f"| [`{rule}`]({RULE_DOCS}{rule}) | {count} |" for rule, count in by_rule.most_common()]

    lines += [
        "",
        f"<details><summary>Top files ({min(len(by_file), 25)} of {len(by_file)})</summary>",
        "",
        "| file | count |",
        "| --- | --: |",
    ]
    ranked = sorted(by_file.items(), key=lambda item: sum(item[1].values()), reverse=True)
    lines += [f"| `{path}` | {sum(counts.values())} |" for path, counts in ranked[:25]]
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
    diagnostics = json.loads(raw) if raw.strip() else []
    for diagnostic in diagnostics:
        diagnostic["location"]["path"] = to_repo_relative(diagnostic["location"]["path"], repo_root, cwd)

    if sarif_path:
        if len(diagnostics) > SARIF_RESULT_LIMIT:
            print(
                f"warning: {len(diagnostics)} results exceeds the code scanning limit of "
                f"{SARIF_RESULT_LIMIT}; truncating",
                file=sys.stderr,
            )
            diagnostics = diagnostics[:SARIF_RESULT_LIMIT]
        sarif_path.write_text(json.dumps(build_sarif(diagnostics, args.ty_version), indent=2) + "\n")
        print(f"wrote {sarif_path} ({len(diagnostics)} results)")

    if markdown_path:
        markdown_path.write_text(build_markdown(diagnostics))
        print(f"wrote {markdown_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
