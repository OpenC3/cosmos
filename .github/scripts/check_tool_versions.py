#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["requests==2.34.2"]
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

"""Report pinned tool versions that have fallen behind upstream.

Dependabot covers most of this repository, but three kinds of pin are invisible
to it, and those are exactly the ones this script watches:

  * versions inside a GitHub Actions input (setup-trivy's `version`) --
    dependabot bumps the action's SHA but never reads its inputs
  * Dockerfile ARGs consumed by `pip install` (OPENC3_UV_VERSION), which follow
    the uv pin in openc3/python/pyproject.toml rather than upstream, so the
    images run the uv that CI does
  * PEP 723 script headers and their lockfiles (*.py.lock). The stub
    generator's ruff follows pyproject.toml's, like the Dockerfile ARGs

Everything else used to be watched here too and moved to dependabot: the
setup-uv action (including majors, through the github-actions-major group),
CI's uv (the `uv` dependency group, read by setup-uv's version-file), and ruff
and ty in pyproject.toml.

Prints a markdown report on stdout and exits 1 when anything is behind, so a
scheduled workflow can turn that into a pull request.

    uv run --script --locked .github/scripts/check_tool_versions.py
    uv run --script --locked .github/scripts/check_tool_versions.py --quiet
    uv run --script --locked .github/scripts/check_tool_versions.py --fix

--fix rewrites every stale pin in place. It does not regenerate the lockfiles
that some of those pins feed (openc3/python/uv.lock, the PEP 723 *.py.lock);
the caller does that, because uv is the only thing that can.
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple

import requests


REPO_ROOT = Path(__file__).resolve().parents[2]
TIMEOUT = 30

# The only two hosts this script talks to, keyed by the prefix a source uses.
# fetch_json builds every request URL from one of these literals plus a path,
# so no caller can aim a request at another host: appending to a scheme-and-host
# base cannot change the host, which makes the property structural rather than
# a check on a URL that was already assembled somewhere else.
BASES = {
    "pypi": "https://pypi.org",
    "gh": "https://api.github.com",
}

# Upstream sources. "pypi:<name>" looks up the newest release on PyPI;
# "gh:<owner>/<repo>" uses the latest GitHub release tag; "repo:<name>" is a
# pin elsewhere in this repository, from REPO_PINS, for a copy that has to
# track it.
PYPROJECT_UV = "repo:uv"
PYPROJECT_RUFF = "repo:ruff"
MYPY = "pypi:mypy"
REQUESTS = "pypi:requests"
TRIVY = "gh:aquasecurity/trivy"

# repo: sources, as (file, regex whose first group captures the version).
# Dependabot raises these in pyproject.toml; the copies follow, so the images
# run CI's uv and the stub generator formats with the ruff that checks it.
REPO_PINS = {
    "uv": ("openc3/python/pyproject.toml", r'uv = \["uv==([\d.]+)"\]'),
    "ruff": ("openc3/python/pyproject.toml", r'"ruff==([\d.]+)"'),
}


class Surface(NamedTuple):
    """A pinned version to watch."""

    label: str
    path: str  # repository-relative file holding the pin
    pattern: str  # regex whose first group captures the pinned version
    source: str  # upstream to compare against


SURFACES = [
    Surface(
        "uv (openc3-ruby image)",
        "openc3-ruby/Dockerfile",
        r"ARG OPENC3_UV_VERSION=([\d.]+)",
        PYPROJECT_UV,
    ),
    Surface(
        "uv (openc3-ruby ubi image)",
        "openc3-ruby/Dockerfile-ubi",
        r"ARG OPENC3_UV_VERSION=([\d.]+)",
        PYPROJECT_UV,
    ),
    # The trivy release every image scan installs. It sits in a composite
    # action rather than the three scan workflows because GITHUB_TOKEN cannot
    # push a change under .github/workflows/, which the bump pull request would
    # otherwise have to do.
    Surface(
        "trivy (image scans)",
        ".github/actions/setup-trivy/action.yml",
        r'(?s)trivy-version:.*?default:\s*"(v[\d.]+)"',
        TRIVY,
    ),
    Surface(
        "mypy (stub generator script)",
        "openc3/python/tools/generate_singleton_stubs.py",
        r'"mypy==([\d.]+)"',
        MYPY,
    ),
    Surface(
        "requests (this script)",
        ".github/scripts/check_tool_versions.py",
        r'"requests==([\d.]+)"',
        REQUESTS,
    ),
    Surface(
        "ruff (stub generator script)",
        "openc3/python/tools/generate_singleton_stubs.py",
        r'"ruff==([\d.]+)"',
        PYPROJECT_RUFF,
    ),
]


def fetch_json(kind: str, path: str) -> dict:
    """GET a JSON document from one upstream, named by its BASES key."""
    base = BASES.get(kind)
    if base is None:
        raise ValueError(f"no upstream registered for {kind!r}")
    url = f"{base}/{path.lstrip('/')}"

    headers = {"User-Agent": "openc3-tool-version-check"}
    # GitHub's unauthenticated rate limit is low; use the workflow token if present
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and kind == "gh":
        headers["Authorization"] = f"Bearer {token}"
    # No redirects: a 3xx is the one way an upstream could still send this
    # request, and the workflow token with it, somewhere else.
    response = requests.get(url, headers=headers, timeout=TIMEOUT, allow_redirects=False)
    response.raise_for_status()
    return response.json()


def latest_version(source: str, cache: dict) -> str | None:
    if source in cache:
        return cache[source]
    kind, name = source.split(":", 1)
    if kind == "repo":
        path, pattern = REPO_PINS[name]
        match = re.search(pattern, (REPO_ROOT / path).read_text())
        version = match.group(1) if match else None
        if version is None:
            print(f"warning: no {name} pin matched in {path}", file=sys.stderr)
        cache[source] = version
        return version
    try:
        if kind == "pypi":
            version = fetch_json(kind, f"pypi/{name}/json")["info"]["version"]
        else:
            version = fetch_json(kind, f"repos/{name}/releases/latest")["tag_name"]
    except (requests.RequestException, KeyError, ValueError) as error:
        print(f"warning: could not resolve latest for {source}: {error}", file=sys.stderr)
        version = None
    cache[source] = version
    return version


def as_tuple(version: str) -> tuple[int, ...]:
    """Numeric prefix of a version, for ordering. 'v10.0.1' -> (10, 0, 1)."""
    return tuple(int(part) for part in re.findall(r"\d+", version)) or (0,)


class Result(NamedTuple):
    """A surface with the versions resolved for it."""

    surface: Surface
    pinned: str
    latest: str

    @property
    def stale(self) -> bool:
        return as_tuple(self.pinned) < as_tuple(self.latest)

    @property
    def major(self) -> bool:
        """Stale across a major boundary, which dependabot may not raise at all."""
        return self.stale and as_tuple(self.pinned)[0] != as_tuple(self.latest)[0]

    @property
    def status(self) -> str:
        """How this row is marked in the report."""
        if self.major:
            return "**major**"
        return "behind" if self.stale else "ok"


def apply_fix(result: Result) -> str | None:
    """Rewrite one stale pin in place. Returns a description, or None if skipped."""
    surface = result.surface
    path = REPO_ROOT / surface.path
    text = path.read_text()

    # The report compares loosely (as_tuple ignores a leading "v"), but the
    # file has to keep whatever form it already used.
    latest = result.latest
    if latest.startswith("v") and not result.pinned.startswith("v"):
        latest = latest[1:]

    match = re.search(surface.pattern, text)
    if match is None:  # pragma: no cover - the caller already matched once
        return None
    text = text[: match.start(1)] + latest + text[match.end(1) :]
    detail = f"{surface.label}: {result.pinned} -> {latest}"

    path.write_text(text)
    return detail


def latest_cell(source: str, latest: str) -> str:
    """The report's latest column: a link upstream, or the file for a repo pin."""
    kind, name = source.split(":", 1)
    if kind == "repo":
        return f"`{latest}` (`{REPO_PINS[name][0]}`)"
    return f"[`{latest}`]({source_url(source)})"


def source_url(source: str) -> str:
    kind, name = source.split(":", 1)
    return f"https://pypi.org/project/{name}/" if kind == "pypi" else f"https://github.com/{name}/releases"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true", help="suppress the report, return the exit code only")
    parser.add_argument("--fix", action="store_true", help="rewrite every stale pin in place")
    args = parser.parse_args()

    cache: dict[str, str | None] = {}
    results: list[Result] = []
    unresolved: list[str] = []

    for surface in SURFACES:
        path = REPO_ROOT / surface.path
        if not path.exists():
            unresolved.append(f"{surface.label}: {surface.path} not found")
            continue
        match = re.search(surface.pattern, path.read_text())
        if not match:
            unresolved.append(f"{surface.label}: no version matched in {surface.path}")
            continue

        latest = latest_version(surface.source, cache)
        if latest is None:
            unresolved.append(f"{surface.label}: upstream lookup failed")
            continue

        results.append(Result(surface, match.group(1), latest))

    behind = [result.surface.label for result in results if result.stale]

    fixed: list[str] = []
    if args.fix:
        for result in results:
            if not result.stale:
                continue
            detail = apply_fix(result)
            if detail:
                fixed.append(detail)
            else:
                unresolved.append(f"{result.surface.label}: could not rewrite the pin")

    if not args.quiet:
        print("## Pinned tool versions\n")
        print("| tool | pinned | latest | file | status |")
        print("| --- | --- | --- | --- | --- |")
        for result in results:
            surface = result.surface
            latest = latest_cell(surface.source, result.latest)
            print(f"| {surface.label} | `{result.pinned}` | {latest} | `{surface.path}` | {result.status} |")
        if unresolved:
            print("\n### Could not check\n")
            for note in unresolved:
                print(f"- {note}")
        if fixed:
            print("\n### Rewritten\n")
            for detail in fixed:
                print(f"- {detail}")
            print("\nLockfiles that depend on these pins still need regenerating.")
        elif behind:
            print(f"\n{len(behind)} pin(s) behind upstream: {', '.join(behind)}.")
            print("\nDependabot does not raise these, so they need a manual bump.")
        elif not unresolved:
            print("\nAll watched pins are current.")

    return 1 if behind or unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
