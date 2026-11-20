#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["packaging"]
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

"""Upgrade only the packages `uv audit` flags, to at least their fixed versions.

Runs against the uv project in the current directory. For each advisory it
takes the lowest fix version above the locked version, then the highest of
those per package, and relocks with `uv lock --upgrade-package "name>=version"`.
uv picks the newest version the project's constraints allow, which is at least
that version, and keeps every other package at its locked version unless a fix
needs it changed. Any other package that moves is listed after the relock. If
a constraint in pyproject.toml or a parent package rules the fix out, `uv lock`
fails and says which one.

Left alone and listed instead:
- advisories with no released fix;
- packages locked at more than one version (one per Python version marker),
  because one unconditional lower bound would apply to every marker.

uv audit reports fix versions, not affected ranges, so a version above the fix
can still fall in a later affected range. `just audit-fix` audits again after
syncing to catch that.

This only changes uv.lock. Run `uv sync` afterwards to install it.

Usage:
    uv run --script --locked tools/audit_fix.py
"""

import json
import re
import subprocess
import sys
from pathlib import Path

from packaging.version import InvalidVersion, Version


AUDIT = [
    "uv",
    "audit",
    "--frozen",
    "--output-format",
    "json",
    "--preview-features",
    "audit-command,json-output",
]


def run_audit() -> list[dict]:
    """Return the vulnerabilities `uv audit` reports for the locked project."""
    result = subprocess.run(AUDIT, capture_output=True, text=True, check=False)
    # uv audit exits 1 when it finds vulnerabilities; anything else is an error
    if result.returncode not in (0, 1):
        sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    return json.loads(result.stdout)["vulnerabilities"]


def lowest_fix(current: Version, fix_versions: list[str]) -> Version | None:
    """Return the lowest fix version above the locked one, or None if none is released.

    Advisories can list one fix per release line (e.g. 1.26.18 and 2.0.7), so
    fixes at or below the locked version belong to an older line and are skipped.
    """
    candidates = []
    for fix in fix_versions:
        try:
            version = Version(fix)
        except InvalidVersion:
            continue
        if version > current:
            candidates.append(version)
    return min(candidates, default=None)


def plan(vulnerabilities: list[dict]) -> tuple[dict[str, Version], dict[str, list[str]]]:
    """Return the minimum version per package, and the unfixed advisory IDs per package."""
    targets: dict[str, Version] = {}
    unfixed: dict[str, list[str]] = {}
    for vuln in vulnerabilities:
        name = vuln["dependency"]["name"]
        fix = lowest_fix(Version(vuln["dependency"]["version"]), vuln.get("fix_versions") or [])
        if fix is None:
            unfixed.setdefault(name, []).append(vuln["display_id"])
        else:
            targets[name] = max(fix, targets.get(name, fix))
    return targets, unfixed


def locked_versions() -> dict[str, set[str]]:
    """Return every version of each package in uv.lock."""
    versions: dict[str, set[str]] = {}
    text = Path("uv.lock").read_text()
    for name, version in re.findall(r'^\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"', text, re.M):
        versions.setdefault(name, set()).add(version)
    return versions


def main() -> int:
    """Relock the vulnerable packages and return uv's exit code."""
    vulnerabilities = run_audit()
    if not vulnerabilities:
        print("uv audit found no vulnerabilities")
        return 0

    locked: dict[str, set[str]] = {}
    for vuln in vulnerabilities:
        locked.setdefault(vuln["dependency"]["name"], set()).add(vuln["dependency"]["version"])
    split = {name for name, versions in locked.items() if len(versions) > 1}
    targets, unfixed = plan([v for v in vulnerabilities if v["dependency"]["name"] not in split])

    for name in sorted(split):
        print(f"Locked at several versions, fix by hand: {name} {', '.join(sorted(locked[name]))}")
    for name, ids in sorted(unfixed.items()):
        print(f"No fix released: {name} {', '.join(sorted(locked[name]))} ({', '.join(ids)})")
    if not targets:
        return 0

    upgrade_args = []
    for name, version in sorted(targets.items()):
        print(f"Upgrading: {name} {', '.join(sorted(locked[name]))} -> >={version}")
        upgrade_args += ["--upgrade-package", f"{name}>={version}"]
    sys.stdout.flush()
    before = locked_versions()
    returncode = subprocess.run(["uv", "lock", *upgrade_args], check=False).returncode
    if returncode == 0:
        after = locked_versions()
        for name in sorted(set(before) | set(after)):
            if name not in targets and before.get(name) != after.get(name):
                old = ", ".join(sorted(before.get(name, set()))) or "none"
                new = ", ".join(sorted(after.get(name, set()))) or "removed"
                print(f"Also changed to allow the fixes: {name} {old} -> {new}")
    return returncode


if __name__ == "__main__":
    sys.exit(main())
