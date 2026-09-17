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

  * versions inside a GitHub Actions input (setup-uv's `version`) or a
    Dockerfile ARG consumed by `pip install` -- dependabot parses neither
  * major releases, because every group in .github/dependabot.yml is limited to
    `update-types: [minor, patch]`
  * PEP 723 script lockfiles (openc3/python/tools/*.py.lock)

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
from urllib.parse import urlparse

import requests


REPO_ROOT = Path(__file__).resolve().parents[2]
TIMEOUT = 30

# Upstream sources. "pypi:<name>" looks up the newest release on PyPI;
# "gh:<owner>/<repo>" uses the latest GitHub release tag.
SETUP_UV = "gh:astral-sh/setup-uv"
UV = "pypi:uv"
RUFF = "pypi:ruff"
TY = "pypi:ty"
MYPY = "pypi:mypy"
REQUESTS = "pypi:requests"


class Surface(NamedTuple):
    """A pinned version to watch."""

    label: str
    path: str  # repository-relative file holding the pin
    pattern: str  # regex whose first group captures the pinned version
    source: str  # upstream to compare against
    # An Actions pin carries the immutable commit SHA and the human-readable
    # tag on the same line. Bumping one without the other leaves a pin whose
    # comment lies about what it runs, so --fix rewrites both. The regex's
    # first group captures the SHA.
    sha_pattern: str | None = None


SURFACES = [
    Surface(
        "setup-uv action",
        ".github/actions/setup-uv-python/action.yml",
        r"astral-sh/setup-uv@[0-9a-f]{40} # v(\S+)",
        SETUP_UV,
        sha_pattern=r"astral-sh/setup-uv@([0-9a-f]{40})",
    ),
    Surface(
        "uv (all CI workflows)",
        ".github/actions/setup-uv-python/action.yml",
        # Anchored to the uv-version input: --fix writes through this pattern,
        # and a bare `default:` would match whichever input came first.
        r'(?s)uv-version:.*?default:\s*"([\d.]+)"',
        UV,
    ),
    Surface(
        "uv (openc3-ruby image)",
        "openc3-ruby/Dockerfile",
        r"ARG UV_VERSION=([\d.]+)",
        UV,
    ),
    Surface(
        "uv (openc3-ruby ubi image)",
        "openc3-ruby/Dockerfile-ubi",
        r"ARG UV_VERSION=([\d.]+)",
        UV,
    ),
    Surface(
        "ruff (python dev dependency)",
        "openc3/python/pyproject.toml",
        r'"ruff==([\d.]+)"',
        RUFF,
    ),
    Surface(
        "ty (python dev dependency)",
        "openc3/python/pyproject.toml",
        r'"ty==([\d.]+)"',
        TY,
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
        RUFF,
    ),
]


def fetch_json(url: str) -> dict:
    headers = {"User-Agent": "openc3-tool-version-check"}
    # GitHub's unauthenticated rate limit is low; use the workflow token if present
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    host = urlparse(url).hostname
    if token and host == "api.github.com":
        headers["Authorization"] = f"Bearer {token}"
    response = requests.get(url, headers=headers, timeout=TIMEOUT)
    response.raise_for_status()
    return response.json()


def latest_version(source: str, cache: dict) -> str | None:
    if source in cache:
        return cache[source]
    kind, name = source.split(":", 1)
    try:
        if kind == "pypi":
            version = fetch_json(f"https://pypi.org/pypi/{name}/json")["info"]["version"]
        else:
            version = fetch_json(f"https://api.github.com/repos/{name}/releases/latest")["tag_name"]
    except (requests.RequestException, KeyError, ValueError) as error:
        print(f"warning: could not resolve latest for {source}: {error}", file=sys.stderr)
        version = None
    cache[source] = version
    return version


def latest_commit_sha(source: str, tag: str, cache: dict) -> str | None:
    """Commit SHA a GitHub release tag points at, for rewriting an Actions pin."""
    key = f"{source}@{tag}"
    if key in cache:
        return cache[key]
    name = source.split(":", 1)[1]
    sha = None
    try:
        ref = fetch_json(f"https://api.github.com/repos/{name}/git/ref/tags/{tag}")["object"]
        # An annotated tag points at a tag object, not the commit; deref it.
        if ref["type"] == "tag":
            ref = fetch_json(f"https://api.github.com/repos/{name}/git/tags/{ref['sha']}")["object"]
        sha = ref["sha"]
    except (requests.RequestException, KeyError, ValueError) as error:
        print(f"warning: could not resolve {tag} of {source} to a commit: {error}", file=sys.stderr)
    cache[key] = sha
    return sha


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


def apply_fix(result: Result, cache: dict) -> str | None:
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

    if surface.sha_pattern:
        sha = latest_commit_sha(surface.source, result.latest, cache)
        if sha is None:
            # Writing the tag without the SHA it names would leave the pin
            # running the old commit under a new label, which is worse than
            # leaving the whole pin alone.
            return None
        sha_match = re.search(surface.sha_pattern, text)
        if sha_match is None:  # pragma: no cover
            return None
        text = text[: sha_match.start(1)] + sha + text[sha_match.end(1) :]
        detail += f" ({sha[:7]})"

    path.write_text(text)
    return detail


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
            detail = apply_fix(result, cache)
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
            latest = f"[`{result.latest}`]({source_url(surface.source)})"
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
