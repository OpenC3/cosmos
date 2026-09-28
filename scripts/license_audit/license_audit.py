#!/usr/bin/env python3
"""
license_audit.py -- Does anything OpenC3 COSMOS depends on carry a license we
cannot ship under?

COSMOS itself is distributed under the OpenC3 Builder's License (see
LICENSE.md), a source-available license that is NOT compatible with a strong
copyleft obligation.  A GPL, AGPL or SSPL dependency pulled into a shipped
container would either force us to relicense or put us in violation, so those
licenses have to be caught before they are released, not after.  This tool
enumerates every resolved dependency of the repository, determines each one's
license, classifies it against an explicit policy, and exits non-zero if
anything restrictive got in.

WHAT IS AUDITED
    Resolved *lockfiles*, not manifests -- the audit covers the exact,
    transitively-closed set of packages a build actually installs, which is the
    only set that matters legally.  The lockfiles in scope are listed
    explicitly in MANIFESTS below; the tool reports any lockfile it finds that
    is neither in that table nor in IGNORED_MANIFESTS, so a new service or
    plugin cannot be added to the repo and silently skip the audit.

HOW LICENSES ARE DETERMINED
    Each package's license comes from the first source that has an answer:

    1. Locally installed package metadata -- the gemspecs in the local RubyGems
       store, `*.dist-info/METADATA` in the uv virtualenvs, and
       `node_modules/.pnpm/*/package.json`.  This is the same metadata the
       package's own author shipped, and it needs no network.
    2. The package registry -- rubygems.org, pypi.org, registry.npmjs.org,
       queried for the exact locked version and cached on disk.

    A package whose license cannot be established either way is reported as
    `unknown` rather than assumed benign, because "we could not tell" and "it
    is fine" are very different answers to a licensing question.

HOW LICENSES ARE CLASSIFIED
    License strings are evaluated as SPDX expressions, so `MIT OR GPL-2.0`
    resolves to the permissive branch (we may take the MIT option) while
    `MIT AND GPL-2.0` resolves to the restrictive one (both obligations apply).
    Free-text and non-SPDX strings ("Apache Software License", "GNU General
    Public License v3 (GPLv3)") are normalized by the ordered pattern table in
    LICENSE_PATTERNS below.  Ordering there is load-bearing: `affero` and
    `lesser` are matched before the generic `GPL` fallback.

    Four verdicts, defined by policy in this file and nowhere else:
      permissive      -- ship it (MIT, BSD, Apache-2.0, ISC, ...)
      weak-copyleft   -- review; obligations attach to the dependency itself,
                         not to COSMOS, as long as we do not modify and
                         statically embed it (LGPL, MPL-2.0, EPL, CDDL, ...)
      unknown         -- review; license could not be determined
      restricted      -- FAIL (GPL, AGPL, SSPL, OSL, BUSL, non-commercial, ...)

Usage:
    scripts/license_audit/license_audit.py
    scripts/license_audit/license_audit.py --show all
    scripts/license_audit/license_audit.py --fail-on review
    scripts/license_audit/license_audit.py --offline
    scripts/license_audit/license_audit.py --json report.json --csv packages.csv

Exit status:
    0  no findings at or above --fail-on (default: restricted)
    1  findings at or above --fail-on
    2  the audit could not be completed (missing lockfile, parse failure)
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

# ==========================================================================
# POLICY
#
# Everything in this section is a deliberate legal judgement, not a technical
# detail.  It is kept in one place, in the open, so that a reviewer can audit
# the policy as easily as the code.
# ==========================================================================

FIRST_PARTY = "first-party"
PERMISSIVE = "permissive"
WEAK = "weak-copyleft"
UNKNOWN = "unknown"
RESTRICTED = "restricted"

# Ordered worst-last.  An SPDX `OR` takes the best (lowest) category of its
# branches, an `AND` takes the worst (highest).  `unknown` sits below
# `restricted` so that `SomethingUnrecognized OR GPL-3.0` lands in review
# rather than being failed outright.
RANK = {FIRST_PARTY: 0, PERMISSIVE: 1, WEAK: 2, UNKNOWN: 3, RESTRICTED: 4}

VERDICT_ORDER = [RESTRICTED, UNKNOWN, WEAK, PERMISSIVE, FIRST_PARTY]

# Ordered list of (regex, canonical name, category).  First match wins, so
# narrow patterns must precede the broad ones they would otherwise be eaten by:
# AGPL and LGPL before GPL, BSL-1.0 (Boost) before BSL-1.1 (Business Source),
# UNLICENSED (npm for "proprietary") before Unlicense (public domain).
LICENSE_PATTERNS: list[tuple[str, str, str]] = [
    # -- our own code ------------------------------------------------------
    (r"openc3", "OpenC3 Builder's License", FIRST_PARTY),
    # -- proprietary / no grant -------------------------------------------
    (r"^unlicensed$|^none$|proprietary|all rights reserved", "Proprietary", RESTRICTED),
    # -- network and strong copyleft ---------------------------------------
    (r"agpl|affero", "AGPL", RESTRICTED),
    (r"\bsspl|server side public", "SSPL", RESTRICTED),
    # LGPL and GPL-with-linking-exceptions before the generic GPL fallback.
    (r"lgpl|lesser general public|library general public", "LGPL", WEAK),
    (r"\bgpl|general public license|gnu public license", "GPL", RESTRICTED),
    (r"\bosl\b|open software license", "OSL", RESTRICTED),
    (r"\brpl\b|reciprocal public license", "RPL", RESTRICTED),
    (r"\bcpal\b|common public attribution", "CPAL", RESTRICTED),
    (r"\beupl|european union public", "EUPL", RESTRICTED),
    (r"\bqpl\b|q public license", "QPL", RESTRICTED),
    (r"sleepycat|berkeley database", "Sleepycat", RESTRICTED),
    (r"cecill-[bc]", "CeCILL-B/C", WEAK),
    (r"cecill", "CeCILL", RESTRICTED),
    # -- source-available / field-of-use restricted ------------------------
    (r"\bbsl-1\.0|boost software", "BSL-1.0", PERMISSIVE),
    (r"\bbusl|bsl-1\.1|business source", "BUSL-1.1", RESTRICTED),
    (r"elastic-2\.0|elastic license", "Elastic-2.0", RESTRICTED),
    (r"commons clause", "Commons Clause", RESTRICTED),
    (r"polyform", "PolyForm", RESTRICTED),
    (r"\bnc\b|non-?commercial|cc-by-nc", "Non-Commercial", RESTRICTED),
    (r"\bjrl\b|java research license", "JRL", RESTRICTED),
    # -- weak / file-level copyleft ----------------------------------------
    (r"\bmpl|mozilla public", "MPL", WEAK),
    (r"\bepl|eclipse public", "EPL", WEAK),
    (r"\bcddl|common development and distribution", "CDDL", WEAK),
    (r"\bcpl-|common public license", "CPL", WEAK),
    (r"ms-pl|microsoft public", "Ms-PL", WEAK),
    (r"ms-rl|microsoft reciprocal", "Ms-RL", RESTRICTED),
    (r"\bapsl|apple public source", "APSL", WEAK),
    (r"\bipl-|ibm public license", "IPL", WEAK),
    (r"\bsissl|sun industry", "SISSL", WEAK),
    (r"\bofl-|open font license", "OFL", WEAK),
    (r"artistic-1\.0|^artistic license 1", "Artistic-1.0", WEAK),
    (r"share-?alike|cc-by-sa", "CC-BY-SA", WEAK),
    (r"^json$|json license", "JSON", WEAK),  # the "do no evil" clause
    # -- permissive --------------------------------------------------------
    (r"\bmit\b|^expat$|mit-0|mit license", "MIT", PERMISSIVE),
    (r"\bisc\b", "ISC", PERMISSIVE),
    (r"\bbsd|freebsd|^0bsd$", "BSD", PERMISSIVE),
    (r"apache", "Apache-2.0", PERMISSIVE),
    (r"\bzlib|libpng|\bzpl\b|zope public", "Zlib/Zope", PERMISSIVE),
    (r"\bunlicense\b|public domain|\bcc0|cc-pddc", "Public Domain", PERMISSIVE),
    (r"cc-by(-\d|$| )|creative commons attribution", "CC-BY", PERMISSIVE),
    (r"python-2|python software foundation|\bpsf\b", "PSF-2.0", PERMISSIVE),
    (r"^ruby'?s?$|ruby license|ruby's own", "Ruby", PERMISSIVE),
    (r"artistic-2|^artistic license 2", "Artistic-2.0", PERMISSIVE),
    (r"\bwtfpl|do what the fuck", "WTFPL", PERMISSIVE),
    (r"\bncsa\b|university of illinois", "NCSA", PERMISSIVE),
    (r"\bupl-|universal permissive", "UPL", PERMISSIVE),
    (r"\bafl-|academic free license", "AFL", PERMISSIVE),
    (r"\bhpnd\b|historical permission", "HPND", PERMISSIVE),
    (r"\bx11\b", "X11", PERMISSIVE),
    (r"\bmiros\b|beerware|blue ?oak|\bfsfap\b|\bwith no warranty\b", "Permissive (other)", PERMISSIVE),
    (r"\bw3c\b", "W3C", PERMISSIVE),
    (r"\bpostgresql\b", "PostgreSQL", PERMISSIVE),
    (r"\bopenssl\b", "OpenSSL", PERMISSIVE),
    (r"\bcurl\b", "curl", PERMISSIVE),
    (r"\bntp\b", "NTP", PERMISSIVE),
    (r"\bzpl-", "ZPL", PERMISSIVE),
]

# GPL-family license *exceptions* that remove the obligation that makes the
# base license restrictive for a downstream consumer.  A GPL'd library carrying
# one of these can be linked from non-GPL code, so it drops to review rather
# than failing.
LINKING_EXCEPTIONS = re.compile(
    r"classpath|linking|gcc|libtool|autoconf|bison|font|llvm|universal-foss|"
    r"openssl|gcc-exception|runtime-library|wxwindows|qt-gpl|ocaml",
    re.IGNORECASE,
)

# Strings that carry no license information at all and must not be pattern
# matched, or they would be mistaken for a real answer.
NON_ANSWERS = re.compile(
    r"^\s*$|^see license|^see the license|^custom$|^other/proprietary$|"
    r"^dual license$|^free$|^osi approved$|^licenseref-",
    re.IGNORECASE,
)

# Packages approved despite their category, each with a reason a lawyer would
# accept.  Keyed by "<ecosystem>:<name>" or "<ecosystem>:<name>@<version>".
# Adding an entry here is a licensing decision -- it belongs in a reviewed
# commit, and the reason is not optional.
EXCEPTIONS: dict[str, str] = {
    # "js:some-gpl-linter": "Build-time only; never linked into or shipped with
    #                        any COSMOS artifact.  Reviewed 2026-01-01.",
}

# ==========================================================================
# SCOPE
#
# The lockfiles that define what COSMOS installs.  Listing them explicitly --
# rather than globbing -- means the audit's coverage is reviewable, and the
# scan below reports any lockfile that appears in the repo without being
# classified here.
# ==========================================================================

# (path, ecosystem, scope, description).  scope "runtime" means the packages
# reach a shipped artifact; "dev" means they only ever run in CI or on a
# developer's machine.
MANIFESTS: list[tuple[str, str, str, str]] = [
    ("openc3/Gemfile.lock", "ruby", "runtime",
     "openc3 core gem -- shipped in every container"),
    ("openc3-cosmos-cmd-tlm-api/Gemfile.lock", "ruby", "runtime",
     "cmd-tlm-api Rails service"),
    ("openc3-cosmos-script-runner-api/Gemfile.lock", "ruby", "runtime",
     "script-runner-api Rails service"),
    ("openc3/python/uv.lock", "python", "runtime",
     "openc3 core Python library -- shipped in every container"),
    ("openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/uv.lock", "python", "runtime",
     "demo plugin Python dependencies"),
    ("openc3-cosmos-init/plugins/pnpm-lock.yaml", "js", "runtime",
     "all frontend tool packages -- shipped to the browser"),
    ("docs.openc3.com/pnpm-lock.yaml", "js", "dev",
     "docs site build (Docusaurus); output in docs/ is static HTML"),
    ("playwright/pnpm-lock.yaml", "js", "dev",
     "end-to-end test harness"),
]

# Lockfiles that exist but are deliberately not audited, each with a reason.
IGNORED_MANIFESTS: list[tuple[str, str]] = [
    (r"(^|/)node_modules/", "vendored install tree, not a source of truth"),
    (r"(^|/)\.venv/", "vendored install tree, not a source of truth"),
    (r"(^|/)\.ruby-lsp/", "generated by the Ruby LSP editor extension"),
    (r"^openc3/templates/", "scaffolding for user-generated plugins; the "
                            "dependencies become the user's, not ours"),
    (r"^openc3/test/integration/", "hand-run integration harnesses"),
    (r"^examples/", "sample plugins, not distributed with COSMOS"),
]

# Out of scope by design, and worth saying so out loud: this tool audits
# language-level package dependencies.  It does NOT audit the Linux
# distribution packages or base images in the Dockerfiles (Alpine, UBI,
# Valkey, Traefik, ...).  Those are covered by container scanning (trivy.yaml,
# .grype.yaml) and by the base image vendors' own license manifests.

ECOSYSTEM_LABEL = {"ruby": "Ruby", "python": "Python", "js": "JavaScript"}

USER_AGENT = "openc3-license-audit/1.0 (+https://github.com/OpenC3/cosmos)"
DEV_GROUPS = {"development", "test", "dev", "tools", "doc", "docs", "ci", "lint", "assets"}


# ==========================================================================
# License expression evaluation
# ==========================================================================

_COMPILED_PATTERNS = [(re.compile(p, re.IGNORECASE), name, cat) for p, name, cat in LICENSE_PATTERNS]
_OPERATORS = {"AND", "OR", "WITH"}


def classify_atom(text: str) -> tuple[str, str]:
    """Classify a single license name.  Returns (canonical name, category)."""
    text = text.strip().strip(",;")
    # Our own LicenseRef first: NON_ANSWERS would otherwise swallow it.
    for pattern, name, category in _COMPILED_PATTERNS:
        if category == FIRST_PARTY and pattern.search(text):
            return (name, category)
    if NON_ANSWERS.match(text):
        return (text or "(none)", UNKNOWN)
    for pattern, name, category in _COMPILED_PATTERNS:
        if pattern.search(text):
            if category == RESTRICTED and re.search(r"with[- ]", text, re.IGNORECASE) \
                    and LINKING_EXCEPTIONS.search(text):
                # Deprecated SPDX spelling of a license exception, e.g.
                # "GPL-2.0-with-classpath-exception": the exception is baked
                # into the id instead of following a WITH operator.
                return (text, WEAK)
            return (name, category)
    return (text, UNKNOWN)


class _ExpressionParser:
    """Recursive-descent parser for SPDX license expressions.

    Only *uppercase* AND/OR/WITH are treated as operators, which lets free-text
    license names ("GNU General Public License v2 or later") pass through as a
    single atom instead of being split on their prose "or".
    """

    def __init__(self, tokens: list[str]):
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> str | None:
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def parse(self) -> tuple[str, str]:
        if not self.tokens:
            return ("(none)", UNKNOWN)
        result = self.parse_or()
        if self.peek() is not None:
            raise ValueError("unconsumed license expression")
        return result

    def parse_or(self) -> tuple[str, str]:
        branches = [self.parse_and()]
        while self.peek() == "OR":
            self.pos += 1
            branches.append(self.parse_and())
        # Dual licensing: we may pick whichever branch we like, so the best one
        # governs.
        best = min(branches, key=lambda b: RANK[b[1]])
        if len(branches) > 1:
            return (" OR ".join(b[0] for b in branches), best[1])
        return best

    def parse_and(self) -> tuple[str, str]:
        parts = [self.parse_atom()]
        while self.peek() == "AND":
            self.pos += 1
            parts.append(self.parse_atom())
        # Conjunction: every obligation applies, so the worst one governs.
        worst = max(parts, key=lambda p: RANK[p[1]])
        if len(parts) > 1:
            return (" AND ".join(p[0] for p in parts), worst[1])
        return worst

    def parse_atom(self) -> tuple[str, str]:
        token = self.peek()
        if token == "(":
            self.pos += 1
            name, category = self.parse_or()
            if self.peek() != ")":
                raise ValueError("unclosed license expression")
            self.pos += 1
            return (f"({name})", category)
        words = self._words()
        if not words:
            raise ValueError("expected a license name")
        name, category = classify_atom(" ".join(words))
        if self.peek() == "WITH":
            self.pos += 1
            exception = " ".join(self._words())
            if not exception:
                raise ValueError("expected a license exception")
            name = f"{name} WITH {exception}"
            if category == RESTRICTED and LINKING_EXCEPTIONS.search(exception):
                category = WEAK
        return (name, category)

    def _words(self) -> list[str]:
        words = []
        while True:
            token = self.peek()
            if token is None or token == ")" or token in _OPERATORS:
                return words
            if token == "(":
                # A parenthesis after a name is descriptive prose, such as
                # "GNU General Public License v2 (GPLv2)", not an SPDX group.
                # Keep it with the name so a later AND/OR is still evaluated.
                if not words:
                    return words
                depth = 0
                while self.peek() is not None:
                    token = self.peek()
                    if token in _OPERATORS:
                        raise ValueError("operator inside a license description")
                    depth += (token == "(") - (token == ")")
                    words.append(token)
                    self.pos += 1
                    if depth == 0:
                        break
                if depth:
                    raise ValueError("unclosed license description")
                continue
            words.append(token)
            self.pos += 1


def classify(licenses: list[str]) -> tuple[str, str]:
    """Classify a package's declared license(s).

    Multiple entries -- a gemspec `licenses` array, npm's legacy `licenses`
    list, several PyPI license classifiers -- are the convention for dual
    licensing, so they are evaluated as a disjunction.
    """
    cleaned = [lic.strip() for lic in licenses if lic and lic.strip()]
    if not cleaned:
        return ("(unknown)", UNKNOWN)
    branches = []
    for expression in cleaned:
        tokens = re.findall(r"\(|\)|[^\s()]+", expression)
        try:
            branches.append(_ExpressionParser(tokens).parse())
        except ValueError:
            # Do not turn a successfully parsed prefix into a clean verdict.
            branches.append((expression, UNKNOWN))
    if len(branches) == 1:
        return branches[0]
    best = min(branches, key=lambda branch: RANK[branch[1]])
    return (" OR ".join(f"({name})" for name, _ in branches), best[1])


# ==========================================================================
# Package model
# ==========================================================================


@dataclass
class Package:
    ecosystem: str
    name: str
    version: str
    api_version: str = ""          # version to query the registry with
    licenses: list[str] = field(default_factory=list)
    license_source: str = ""       # where the license text came from
    manifests: set[str] = field(default_factory=set)
    dev: bool = True               # dev-only until proven to reach a build
    first_party: bool = False
    note: str = ""

    @property
    def key(self) -> str:
        return f"{self.ecosystem}:{self.name}@{self.version}"

    def merge(self, other: Package) -> None:
        self.manifests |= other.manifests
        # A package that is a runtime dependency anywhere is a runtime
        # dependency, period.
        self.dev = self.dev and other.dev
        self.first_party = self.first_party or other.first_party


class AuditError(Exception):
    """The audit could not be completed."""


# ==========================================================================
# Lockfile parsing -- Ruby
# ==========================================================================

_GEM_SPEC = re.compile(r"^    ([A-Za-z0-9_.\-]+) \(([^)]+)\)$")
_GEM_DEP = re.compile(r"^      ([A-Za-z0-9_.\-]+)")
_GEM_ROOT = re.compile(r"^  ([A-Za-z0-9_.\-]+)")


def split_gem_version(version: str) -> str:
    """`1.18.1-x86_64-darwin` -> `1.18.1` (platform gems are the same source)."""
    return version.split("-", 1)[0]


def group_names(text: str) -> set[str]:
    """Group names out of a bundler group list: `:test, :development`."""
    return {name for pair in re.findall(r":(\w+)|[\"'](\w+)[\"']", text) for name in pair if name}


def parse_gemspec_dev_gems(gemfile: Path) -> set[str]:
    """Development dependencies declared by the gemspec a Gemfile pulls in.

    `gemspec` in a Gemfile puts the gemspec's `add_development_dependency`
    entries in the `:development` group, and they land in Gemfile.lock's
    DEPENDENCIES looking exactly like runtime dependencies.  Without reading
    the gemspec, rspec and rubocop would be reported as shipped code.
    """
    dev: set[str] = set()
    text = gemfile.read_text(encoding="utf-8", errors="replace")
    for match in re.finditer(r"^\s*gemspec\b(.*)$", text, re.MULTILINE):
        options = match.group(1)
        name = re.search(r"(?::name\s*=>|name:)\s*[\"']([^\"']+)[\"']", options)
        path = re.search(r"(?::path\s*=>|path:)\s*[\"']([^\"']+)[\"']", options)
        base = (gemfile.parent / path.group(1)) if path else gemfile.parent
        for spec in sorted(base.glob(f"{name.group(1)}.gemspec" if name else "*.gemspec")):
            dev |= set(re.findall(
                r"add_development_dependency\s*\(?\s*[\"']([^\"']+)[\"']",
                spec.read_text(encoding="utf-8", errors="replace"),
            ))
    return dev


def parse_gemfile_dev_gems(gemfile: Path) -> set[str]:
    """Names of gems declared *only* in development/test groups.

    Gemfile.lock does not record bundler groups, so this reads the Gemfile
    next to it.  A gem in both a dev group and the default group counts as
    runtime.
    """
    if not gemfile.exists():
        return set()
    dev: set[str] = set()
    runtime: set[str] = set()
    stack: list[set[str]] = []
    for line in gemfile.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        match = re.match(r"^group\s+(.+?)\s+do\b", line)
        if match:
            stack.append(group_names(match.group(1)))
            continue
        if line == "end" and stack:
            stack.pop()
            continue
        match = re.match(r"^gem\s+[\"']([^\"']+)[\"'](.*)$", line)
        if not match:
            continue
        name, rest = match.group(1), match.group(2)
        groups: set[str] = set()
        for frame in stack:
            groups |= frame
        for inline in re.findall(r"groups?:\s*(\[[^\]]*\]|:\w+|[\"']\w+[\"'])", rest):
            groups |= group_names(inline)
        if groups and groups <= DEV_GROUPS:
            dev.add(name)
        else:
            runtime.add(name)
    return (dev | parse_gemspec_dev_gems(gemfile)) - runtime


def parse_gemfile_lock(path: Path, rel: str) -> list[Package]:
    packages: dict[str, Package] = {}
    graph: dict[str, set[str]] = defaultdict(set)
    roots: set[str] = set()
    section = None
    in_specs = False
    remote = ""
    current: str | None = None

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw and not raw.startswith(" "):
            section, in_specs, remote = raw.strip(), False, ""
            continue
        if section in ("GEM", "PATH", "GIT"):
            stripped = raw.strip()
            if stripped == "specs:":
                in_specs = True
                continue
            if stripped.startswith("remote:"):
                remote = stripped.split(":", 1)[1].strip()
                continue
            if not in_specs:
                continue
            match = _GEM_SPEC.match(raw)
            if match:
                name, version = match.group(1), match.group(2)
                current = name
                package = Package(
                    ecosystem="ruby",
                    name=name,
                    version=version,
                    api_version=split_gem_version(version),
                    manifests={rel},
                    # A gem sourced from a local path or a git remote is either
                    # ours or unpublished; either way the registry cannot
                    # answer for it.
                    first_party=section == "PATH" or name.startswith("openc3"),
                    note="" if section == "GEM" else f"source: {section.lower()} {remote}",
                )
                if name in packages:
                    packages[name].merge(package)
                else:
                    packages[name] = package
                continue
            match = _GEM_DEP.match(raw)
            if match and current:
                graph[current].add(match.group(1))
        elif section == "DEPENDENCIES":
            match = _GEM_ROOT.match(raw)
            if match:
                roots.add(match.group(1).rstrip("!"))

    dev_roots = parse_gemfile_dev_gems(path.with_suffix(""))
    runtime = reachable(roots - dev_roots, graph)
    for name, package in packages.items():
        package.dev = name not in runtime
    return list(packages.values())


def reachable(roots: set[str], graph: dict[str, set[str]]) -> set[str]:
    """Names reachable from `roots` through `graph` (iterative, cycle-safe)."""
    seen: set[str] = set()
    stack = list(roots)
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        stack.extend(graph.get(node, ()))
    return seen


# ==========================================================================
# Lockfile parsing -- Python (uv)
# ==========================================================================


def load_toml(path: Path) -> dict:
    try:
        import tomllib
    except ModuleNotFoundError:  # Python 3.10
        try:
            import tomli as tomllib  # type: ignore[no-redef]
        except ModuleNotFoundError as exc:
            raise AuditError(
                f"cannot parse {path}: Python 3.11+ (tomllib) or the tomli "
                f"package is required"
            ) from exc
    with path.open("rb") as handle:
        return tomllib.load(handle)


def parse_uv_lock(path: Path, rel: str) -> list[Package]:
    data = load_toml(path)
    entries = data.get("package", [])
    graph: dict[str, set[str]] = defaultdict(set)
    runtime_roots: set[str] = set()
    dev_roots: set[str] = set()
    packages: dict[str, Package] = {}

    for entry in entries:
        name = entry["name"]
        source = entry.get("source", {})
        local = any(key in source for key in ("editable", "virtual", "directory"))
        for dep in entry.get("dependencies", []):
            graph[name].add(dep["name"])
        for group in entry.get("optional-dependencies", {}).values():
            for dep in group:
                graph[name].add(dep["name"])
        if local:
            # The workspace project itself: its dependency lists are the roots.
            runtime_roots |= {dep["name"] for dep in entry.get("dependencies", [])}
            for group in entry.get("optional-dependencies", {}).values():
                runtime_roots |= {dep["name"] for dep in group}
            for group in entry.get("dev-dependencies", {}).values():
                dev_roots |= {dep["name"] for dep in group}
        for group in entry.get("dev-dependencies", {}).values():
            for dep in group:
                graph[name].add(dep["name"])

        version = entry.get("version", "")
        package = Package(
            ecosystem="python",
            name=name,
            version=version,
            api_version=version,
            manifests={rel},
            first_party=local or name.startswith("openc3"),
            note="" if not local else "local workspace project",
        )
        key = f"{name}@{version}"
        if key in packages:
            packages[key].merge(package)
        else:
            packages[key] = package

    runtime = reachable(runtime_roots, graph)
    for package in packages.values():
        package.dev = package.name not in runtime
    return list(packages.values())


# ==========================================================================
# Lockfile parsing -- JavaScript (pnpm)
# ==========================================================================


def split_pnpm_id(identifier: str) -> tuple[str, str] | None:
    """`@babel/core@7.29.7` -> (`@babel/core`, `7.29.7`)."""
    identifier = identifier.strip().strip("'\"")
    identifier = re.sub(r"\(.*$", "", identifier)  # drop the peer-dependency suffix
    if not identifier or identifier.startswith(("link:", "file:", "workspace:")):
        return None
    at = identifier.rfind("@")
    if at <= 0:
        return None
    name, version = identifier[:at], identifier[at + 1:]
    if not version or not re.match(r"^\d", version):
        return None  # aliased, tarball or git dependency -- no registry version
    return (name, version)


def parse_pnpm_lock(path: Path, rel: str) -> list[Package]:
    text = path.read_text(encoding="utf-8", errors="replace")
    try:
        import yaml
    except ModuleNotFoundError:
        yaml = None  # type: ignore[assignment]

    packages: dict[str, Package] = {}
    graph: dict[str, set[str]] = defaultdict(set)
    runtime_roots: set[str] = set()
    have_graph = False

    def add_package(identifier: str, note: str = "") -> None:
        parsed = split_pnpm_id(identifier)
        if parsed is None:
            raise AuditError(
                f"{rel}: cannot audit dependency {identifier!r}: "
                "nonregistry package sources require a separate license review"
            )
        name, version = parsed
        packages[f"{name}@{version}"] = Package(
            ecosystem="js", name=name, version=version, api_version=version,
            manifests={rel}, first_party=is_first_party_js(name), note=note,
        )

    if yaml is not None:
        data = yaml.safe_load(text) or {}
        for identifier in (data.get("packages") or {}):
            add_package(identifier)
        for identifier, snapshot in (data.get("snapshots") or {}).items():
            parsed = split_pnpm_id(identifier)
            if not parsed:
                continue
            source = f"{parsed[0]}@{parsed[1]}"
            for kind in ("dependencies", "optionalDependencies"):
                for dep_name, dep_version in (snapshot.get(kind) or {}).items():
                    target = split_pnpm_id(f"{dep_name}@{dep_version}")
                    if target:
                        graph[source].add(f"{target[0]}@{target[1]}")
        for importer in (data.get("importers") or {}).values():
            for dep_name, spec in (importer.get("dependencies") or {}).items():
                version = spec.get("version") if isinstance(spec, dict) else spec
                target = split_pnpm_id(f"{dep_name}@{version}")
                if target:
                    runtime_roots.add(f"{target[0]}@{target[1]}")
        have_graph = True
    else:
        # No PyYAML: recover the package set from the `packages:` block by
        # indentation.  Enough to audit licenses, but the dependency graph is
        # lost, so every package is reported without a dev/runtime split.
        in_packages = False
        for line in text.splitlines():
            if line and not line.startswith(" "):
                in_packages = line.strip() == "packages:"
                continue
            if not in_packages:
                continue
            # Package keys can be quoted and contain colons (git/tarball URLs).
            # Recognize those too, so unsupported sources fail instead of vanishing.
            match = re.match(r"^  (\S.*):(?:\s*\{\})?\s*$", line)
            if match:
                add_package(match.group(1), note="dev/runtime unknown (PyYAML not installed)")

    if have_graph:
        runtime = reachable(runtime_roots, graph)
        for key, package in packages.items():
            package.dev = key not in runtime
    else:
        for package in packages.values():
            package.dev = False  # assume the worst when we cannot tell

    return list(packages.values())


def is_first_party_js(name: str) -> bool:
    return name.startswith("@openc3/") or name.startswith("openc3-")


# ==========================================================================
# License resolution -- locally installed package metadata
#
# The authoritative statement of a package's license is the metadata its own
# author shipped.  When the package is installed locally we read that directly:
# it needs no network and cannot drift from what a build actually installed.
# ==========================================================================


def ruby_installed_licenses() -> dict[str, list[str]]:
    """`{"name@version": ["MIT"]}` for every gem in the local RubyGems store."""
    script = (
        'require "json"; require "rubygems"; out = {}; '
        'Gem::Specification.each { |s| out["#{s.name}@#{s.version}"] = s.licenses.to_a }; '
        "puts JSON.generate(out)"
    )
    environment = {key: value for key, value in os.environ.items() if key != "BUNDLE_GEMFILE"}
    try:
        result = subprocess.run(
            ["ruby", "-e", script], capture_output=True, text=True, timeout=120, env=environment
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if result.returncode != 0:
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def normalize_python_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def python_installed_licenses(directories: list[Path]) -> dict[str, list[str]]:
    """Licenses from `*.dist-info/METADATA` in the uv virtualenvs next to the
    audited lockfiles."""
    found: dict[str, list[str]] = {}
    metadata_paths = [
        path
        for directory in directories
        for path in directory.glob(".venv/lib/*/site-packages/*.dist-info/METADATA")
    ]
    for metadata_path in metadata_paths:
        name = version = ""
        expression = ""
        declared: list[str] = []
        classifiers: list[str] = []
        with metadata_path.open(encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if not line.strip():
                    break  # end of headers; the rest is the long description
                if line.startswith("Name:"):
                    name = line.split(":", 1)[1].strip()
                elif line.startswith("Version:"):
                    version = line.split(":", 1)[1].strip()
                elif line.startswith("License-Expression:"):
                    expression = line.split(":", 1)[1].strip()
                elif line.startswith("License:"):
                    declared.append(line.split(":", 1)[1].strip())
                elif line.startswith("Classifier: License"):
                    classifiers.append(line.split(":", 1)[1].strip())
        if name and version:
            licenses = python_licenses(expression, declared, classifiers)
            if licenses:
                found[f"{normalize_python_name(name)}@{version}"] = licenses
    return found


def python_licenses(expression: str, declared: list[str], classifiers: list[str]) -> list[str]:
    """Pick the most trustworthy license statement Python metadata offers.

    PEP 639's `License-Expression` is SPDX and unambiguous, so it wins.  The
    legacy `License` field is free text and is sometimes the *entire* license
    document, which no pattern should be run against, so anything long is
    discarded in favour of the trove classifiers.
    """
    if expression:
        return [expression]
    short = [text for text in declared if text and len(text) <= 80 and "\n" not in text]
    trove = []
    for classifier in classifiers:
        # "License :: OSI Approved :: Apache Software License" -> the tail.
        tail = classifier.split("::")[-1].strip()
        if tail and tail.lower() not in ("license", "osi approved", "dfsg approved"):
            trove.append(tail)
    # A short `License:` field is authoritative only when it actually names a
    # license.  Values like "Dual License" or "Other/Proprietary" do not, and
    # the trove classifiers ("BSD License", "Apache Software License") then
    # carry the real answer.
    if short and classify(short)[1] != UNKNOWN:
        return short
    return trove or short


def js_local_license(lock_dir: Path, name: str, version: str) -> list[str]:
    """License from the pnpm install tree, if this package is installed."""
    mangled = name.replace("/", "+")
    store = lock_dir / "node_modules" / ".pnpm"
    candidates: list[Path] = []
    if store.is_dir():
        candidates.append(store / f"{mangled}@{version}" / "node_modules" / name)
        candidates.extend(
            path / "node_modules" / name for path in sorted(store.glob(f"{mangled}@{version}_*"))
        )
    candidates.append(lock_dir / "node_modules" / name)
    for candidate in candidates:
        manifest = candidate / "package.json"
        if not manifest.is_file():
            continue
        try:
            data = json.loads(manifest.read_text(encoding="utf-8", errors="replace"))
        except json.JSONDecodeError:
            continue
        if data.get("version") not in (None, version):
            continue
        licenses = npm_licenses(data)
        if licenses:
            return licenses
    return []


def npm_licenses(data: dict) -> list[str]:
    """npm's `license` field, plus the deprecated `licenses` array."""
    license_field = data.get("license")
    if isinstance(license_field, str) and license_field.strip():
        return [license_field.strip()]
    if isinstance(license_field, dict) and license_field.get("type"):
        return [str(license_field["type"])]
    legacy = data.get("licenses")
    if isinstance(legacy, list):
        out = []
        for entry in legacy:
            if isinstance(entry, dict) and entry.get("type"):
                out.append(str(entry["type"]))
            elif isinstance(entry, str):
                out.append(entry)
        return out
    return []


# ==========================================================================
# License resolution -- package registries
# ==========================================================================


class LicenseCache:
    """On-disk cache of registry answers, keyed by ecosystem/name/version.

    Locked package versions are immutable, so a hit never needs revalidating;
    `--refresh` throws the cache away when a registry correction is suspected.
    """

    def __init__(self, path: Path | None, refresh: bool = False):
        self.path = path
        self.data: dict[str, list[str]] = {}
        self.dirty = False
        if path and path.is_file() and not refresh:
            try:
                self.data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                self.data = {}

    def get(self, key: str) -> list[str] | None:
        return self.data.get(key)

    def put(self, key: str, licenses: list[str]) -> None:
        if licenses:  # never cache a failure; the next run should retry
            self.data[key] = licenses
            self.dirty = True

    def save(self) -> None:
        if not (self.path and self.dirty):
            return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(self.data, indent=0, sort_keys=True), encoding="utf-8")
        except OSError:
            pass


def http_json(url: str, timeout: float = 20.0, attempts: int = 3) -> dict | None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8", errors="replace"))
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None  # unpublished or yanked version; not worth retrying
            if error.code in (429, 500, 502, 503, 504) and attempt < attempts - 1:
                time.sleep(1.5 * (attempt + 1))
                continue
            return None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            if attempt < attempts - 1:
                time.sleep(1.0 * (attempt + 1))
                continue
            return None
    return None


def registry_licenses(package: Package) -> list[str]:
    name, version = package.name, package.api_version or package.version
    if not version:
        return []
    if package.ecosystem == "ruby":
        data = http_json(
            f"https://rubygems.org/api/v2/rubygems/{urllib.parse.quote(name)}/versions/{urllib.parse.quote(version)}.json"
        )
        return [str(lic) for lic in (data or {}).get("licenses") or [] if lic]
    if package.ecosystem == "python":
        data = http_json(f"https://pypi.org/pypi/{urllib.parse.quote(name)}/{urllib.parse.quote(version)}/json")
        info = (data or {}).get("info") or {}
        declared = [info["license"]] if info.get("license") else []
        classifiers = [c for c in info.get("classifiers") or [] if c.startswith("License")]
        return python_licenses(info.get("license_expression") or "", declared, classifiers)
    if package.ecosystem == "js":
        data = http_json(
            f"https://registry.npmjs.org/{urllib.parse.quote(name, safe='@')}/{urllib.parse.quote(version)}"
        )
        return npm_licenses(data or {})
    return []


def registry_licenses_any_version(package: Package) -> list[str]:
    """License from another published version of the same package.

    Some releases ship with no license metadata at all (a `pyproject.toml`
    with only `license-files`, an old npm package predating the `license`
    field).  A neighbouring release of the same project almost always carries
    the answer, so it is used as a labelled last resort -- reported as coming
    from a different version, never silently.
    """
    name = package.name
    if package.ecosystem == "ruby":
        data = http_json(f"https://rubygems.org/api/v1/versions/{urllib.parse.quote(name)}.json")
        for release in data or []:
            licenses = [str(lic) for lic in release.get("licenses") or [] if lic]
            if licenses:
                return licenses
        return []
    if package.ecosystem == "python":
        data = http_json(f"https://pypi.org/pypi/{urllib.parse.quote(name)}/json")
        info = (data or {}).get("info") or {}
        declared = [info["license"]] if info.get("license") else []
        classifiers = [c for c in info.get("classifiers") or [] if c.startswith("License")]
        return python_licenses(info.get("license_expression") or "", declared, classifiers)
    if package.ecosystem == "js":
        data = http_json(f"https://registry.npmjs.org/{urllib.parse.quote(name, safe='@')}") or {}
        licenses = npm_licenses(data)
        if licenses:
            return licenses
        latest = ((data.get("dist-tags") or {}).get("latest"))
        versions = data.get("versions") or {}
        if latest and latest in versions:
            return npm_licenses(versions[latest])
        for release in reversed(list(versions.values())):
            licenses = npm_licenses(release)
            if licenses:
                return licenses
    return []


def resolve_licenses(
    packages: list[Package],
    lock_dirs: dict[str, Path],
    cache: LicenseCache,
    offline: bool,
    workers: int,
    progress: bool,
) -> None:
    """Fill in `licenses`/`license_source` for every package, in place."""
    ruby_local = ruby_installed_licenses() if any(p.ecosystem == "ruby" for p in packages) else {}
    python_local = (
        python_installed_licenses(sorted(set(lock_dirs.values())))
        if any(p.ecosystem == "python" for p in packages)
        else {}
    )

    pending: list[Package] = []
    for package in packages:
        if package.first_party:
            package.licenses = package.licenses or ["LicenseRef-OpenC3-Builders-License"]
            package.license_source = "first-party"
            continue
        licenses: list[str] = []
        if package.ecosystem == "ruby":
            licenses = ruby_local.get(f"{package.name}@{package.version}", []) or ruby_local.get(
                f"{package.name}@{package.api_version}", []
            )
        elif package.ecosystem == "python":
            licenses = python_local.get(f"{normalize_python_name(package.name)}@{package.version}", [])
        elif package.ecosystem == "js":
            for manifest in sorted(package.manifests):
                lock_dir = lock_dirs.get(manifest)
                if lock_dir is None:
                    continue
                licenses = js_local_license(lock_dir, package.name, package.version)
                if licenses:
                    break
        if licenses:
            package.licenses = licenses
            package.license_source = "installed"
            continue
        cached = cache.get(package.key)
        if cached:
            package.licenses = cached
            package.license_source = "registry (cached)"
            continue
        pending.append(package)

    if not pending:
        return
    if offline:
        for package in pending:
            package.license_source = "unresolved (offline)"
        return

    if progress:
        print(f"Querying registries for {len(pending)} packages...", file=sys.stderr)

    def fetch(package: Package) -> None:
        licenses = registry_licenses(package)
        if licenses:
            package.licenses = licenses
            package.license_source = "registry"
            cache.put(package.key, licenses)
            return
        licenses = registry_licenses_any_version(package)
        if licenses:
            package.licenses = licenses
            package.license_source = "registry (other version)"
            package.note = (package.note + "; " if package.note else "") + (
                f"{package.version} publishes no license metadata; license taken "
                f"from another release of the same package"
            )
            # Not cached: the next run should try this exact version again, in
            # case the release is fixed up.
            return
        package.license_source = "unresolved"

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(fetch, pending))


# ==========================================================================
# Audit
# ==========================================================================

PARSERS = {"ruby": parse_gemfile_lock, "python": parse_uv_lock, "js": parse_pnpm_lock}
LOCKFILE_NAMES = ("Gemfile.lock", "uv.lock", "pnpm-lock.yaml")


def repo_root_from(start: Path) -> Path:
    try:
        result = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        pass
    return start.parents[1]  # scripts/license_audit/ -> repo root


def git_ref(root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "unknown"


def find_unlisted_lockfiles(root: Path) -> list[str]:
    """Lockfiles present in the repo that the policy does not classify.

    Coverage is the part of an audit that rots: someone adds a service, and
    its dependencies are never looked at because nothing complained.  This
    complains.
    """
    listed = {path for path, _, _, _ in MANIFESTS}
    ignored = [re.compile(pattern) for pattern, _ in IGNORED_MANIFESTS]
    unlisted = []
    for directory, subdirectories, filenames in os.walk(root):
        # Pruning install trees here is what keeps this walk to a second: they
        # hold tens of thousands of files and no lockfile that is ours.
        subdirectories[:] = [
            name for name in subdirectories
            if name not in (".git", "node_modules", ".venv", "__pycache__", ".pytest_cache")
        ]
        for filename in filenames:
            if filename not in LOCKFILE_NAMES:
                continue
            rel = Path(directory, filename).relative_to(root).as_posix()
            if rel in listed or any(pattern.search(rel) for pattern in ignored):
                continue
            unlisted.append(rel)
    return sorted(unlisted)


def collect_packages(root: Path, ecosystems: set[str]) -> tuple[list[Package], list[dict], dict[str, Path]]:
    packages: dict[str, Package] = {}
    manifest_rows: list[dict] = []
    lock_dirs: dict[str, Path] = {}
    missing: list[str] = []

    for rel, ecosystem, scope, description in MANIFESTS:
        path = root / rel
        if not path.is_file():
            missing.append(rel)
            continue
        if ecosystem not in ecosystems:
            continue
        lock_dirs[rel] = path.parent
        found = PARSERS[ecosystem](path, rel)
        if scope == "dev":
            # Nothing in a dev-scoped lockfile reaches a shipped artifact.
            for package in found:
                package.dev = True
        for package in found:
            if package.key in packages:
                packages[package.key].merge(package)
            else:
                packages[package.key] = package
        manifest_rows.append({
            "path": rel, "ecosystem": ecosystem, "scope": scope,
            "description": description, "packages": len(found),
        })

    if missing:
        raise AuditError(
            "lockfile(s) listed in MANIFESTS are missing: " + ", ".join(missing) +
            "\nEither restore them or update the MANIFESTS table in this script."
        )
    return (list(packages.values()), manifest_rows, lock_dirs)


def exception_for(package: Package) -> str | None:
    return EXCEPTIONS.get(f"{package.ecosystem}:{package.name}@{package.version}") or EXCEPTIONS.get(
        f"{package.ecosystem}:{package.name}"
    )


def audit(packages: list[Package]) -> list[dict]:
    rows = []
    for package in packages:
        canonical, category = classify(package.licenses)
        if package.first_party:
            # Ours: the license string is our own LicenseRef, and no policy
            # applies to code we wrote.
            category = FIRST_PARTY
        excused = exception_for(package)
        rows.append({
            "ecosystem": package.ecosystem,
            "name": package.name,
            "version": package.version,
            "license": canonical,
            "declared": package.licenses,
            # An exception approves shipping the package; it does not change
            # what the license actually is, so the verdict is reported as-is
            # and only the pass/fail decision is affected.
            "category": category,
            "excused": bool(excused),
            "exception": excused,
            "dev": package.dev,
            "source": package.license_source,
            "manifests": sorted(package.manifests),
            "note": package.note,
        })
    rows.sort(key=lambda row: (-RANK[row["category"]], row["dev"], row["ecosystem"], row["name"].lower()))
    return rows


# ==========================================================================
# Reporting
# ==========================================================================

FAIL_LEVELS = {
    "restricted": {RESTRICTED},
    "unknown": {RESTRICTED, UNKNOWN},
    "review": {RESTRICTED, UNKNOWN, WEAK},
    "never": set(),
}

CATEGORY_BLURB = {
    RESTRICTED: "cannot ship under the OpenC3 Builder's License -- remove, replace, or obtain a commercial license",
    UNKNOWN: "license could not be determined -- resolve by hand",
    WEAK: "shippable as an unmodified dependency; do not embed modified copies",
    PERMISSIVE: "no obligations beyond attribution",
    FIRST_PARTY: "our own code",
}


def format_row(row: dict, width: dict[str, int]) -> str:
    scope = "dev" if row["dev"] else "runtime"
    line = (
        f"  {ECOSYSTEM_LABEL[row['ecosystem']]:<{width['eco']}}  "
        f"{row['name']:<{width['name']}}  {row['version']:<{width['version']}}  "
        f"{row['license']:<{width['license']}}  {scope:<7}  {row['source']}"
    )
    if row["exception"]:
        line += f"\n      APPROVED BY EXCEPTION: {row['exception']}"
    if row["note"]:
        line += f"\n      note: {row['note']}"
    if row["category"] in (UNKNOWN, RESTRICTED, WEAK) and row["declared"]:
        line += f"\n      declared: {'; '.join(row['declared'])[:200]}"
    if row["category"] in (UNKNOWN, RESTRICTED):
        line += f"\n      from: {', '.join(row['manifests'])}"
    return line


def print_report(
    rows: list[dict],
    manifest_rows: list[dict],
    unlisted: list[str],
    root: Path,
    show_all: bool,
    stream=sys.stdout,
) -> None:
    print("OpenC3 COSMOS dependency license audit", file=stream)
    print(f"  repository   {root}", file=stream)
    print(f"  git ref      {git_ref(root)}", file=stream)
    print(f"  generated    {time.strftime('%Y-%m-%d %H:%M:%S %Z')}", file=stream)
    print(file=stream)

    print("Lockfiles audited", file=stream)
    path_width = max((len(row["path"]) for row in manifest_rows), default=0)
    for row in manifest_rows:
        print(
            f"  {row['path']:<{path_width}}  {row['packages']:>4} packages  "
            f"{row['scope']:<7}  {row['description']}",
            file=stream,
        )
    print(file=stream)

    by_category: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_category[row["category"]].append(row)

    print("Summary", file=stream)
    for category in VERDICT_ORDER:
        found = by_category.get(category, [])
        runtime = sum(1 for row in found if not row["dev"])
        excused = sum(1 for row in found if row["excused"])
        suffix = f", {excused} approved by exception" if excused else ""
        print(
            f"  {category:<14} {len(found):>4}  ({runtime} runtime, {len(found) - runtime} dev-only{suffix})"
            f"  -- {CATEGORY_BLURB[category]}",
            file=stream,
        )
    print(file=stream)

    sections = VERDICT_ORDER if show_all else [RESTRICTED, UNKNOWN, WEAK]
    for category in sections:
        found = by_category.get(category, [])
        heading = f"{category.upper()} ({len(found)})"
        print(heading, file=stream)
        print("-" * len(heading), file=stream)
        if not found:
            print("  none", file=stream)
        else:
            width = {
                "eco": max(len(ECOSYSTEM_LABEL[row["ecosystem"]]) for row in found),
                "name": max(len(row["name"]) for row in found),
                "version": max(len(row["version"]) for row in found),
                "license": max(len(row["license"]) for row in found),
            }
            for row in found:
                print(format_row(row, width), file=stream)
        print(file=stream)

    if unlisted:
        print("UNAUDITED LOCKFILES", file=stream)
        print("-------------------", file=stream)
        print("  These lockfiles exist in the repo but are neither listed in", file=stream)
        print("  MANIFESTS nor excluded in IGNORED_MANIFESTS, so their", file=stream)
        print("  dependencies were not checked. Classify them in the script.", file=stream)
        for path in unlisted:
            print(f"    {path}", file=stream)
        print(file=stream)


def write_json(path: Path, rows: list[dict], manifest_rows: list[dict], unlisted: list[str], root: Path) -> None:
    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        counts[row["category"]] += 1
    payload = {
        "tool": "scripts/license_audit/license_audit.py",
        "repository": str(root),
        "git_ref": git_ref(root),
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "policy": {
            "project_license": "LicenseRef-OpenC3-Builders-License",
            "categories": {category: CATEGORY_BLURB[category] for category in VERDICT_ORDER},
            "exceptions": EXCEPTIONS,
        },
        "manifests": manifest_rows,
        "unaudited_lockfiles": unlisted,
        "summary": {category: counts.get(category, 0) for category in VERDICT_ORDER},
        "packages": rows,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["ecosystem", "name", "version", "license", "category", "scope",
             "declared", "license_source", "manifests", "exception"]
        )
        for row in rows:
            writer.writerow([
                row["ecosystem"], row["name"], row["version"], row["license"], row["category"],
                "dev" if row["dev"] else "runtime", "; ".join(row["declared"]),
                row["source"], " ".join(row["manifests"]), row["exception"] or "",
            ])


# ==========================================================================
# Self-test
#
# The classifier is a pile of ordered regexes, and the ordering is exactly
# what keeps `AGPL` from being read as `GPL` and Boost's `BSL-1.0` from being
# read as the Business Source License.  These cases are the proof that the
# policy table still says what it means; `--self-test` runs them.
# ==========================================================================

SELF_TEST_CASES: list[tuple[str, str]] = [
    # strong copyleft, in every spelling the registries actually use
    ("GPL-3.0-only", RESTRICTED),
    ("GPL-2.0-or-later", RESTRICTED),
    ("GPLv3", RESTRICTED),
    ("GNU General Public License v2 (GPLv2)", RESTRICTED),
    ("GNU General Public License version 3", RESTRICTED),
    ("AGPL-3.0-or-later", RESTRICTED),
    ("GNU Affero General Public License v3 or later (AGPLv3+)", RESTRICTED),
    ("SSPL-1.0", RESTRICTED),
    ("Server Side Public License", RESTRICTED),
    ("OSL-3.0", RESTRICTED),
    ("EUPL-1.2", RESTRICTED),
    ("QPL-1.0", RESTRICTED),
    ("Sleepycat", RESTRICTED),
    ("CeCILL-2.1", RESTRICTED),
    ("Ms-RL", RESTRICTED),
    # source-available and field-of-use restrictions
    ("BUSL-1.1", RESTRICTED),
    ("Business Source License 1.1", RESTRICTED),
    ("Elastic-2.0", RESTRICTED),
    ("Apache-2.0 with Commons Clause", RESTRICTED),
    ("CC-BY-NC-4.0", RESTRICTED),
    ("PolyForm-Noncommercial-1.0.0", RESTRICTED),
    ("UNLICENSED", RESTRICTED),
    ("Proprietary", RESTRICTED),
    ("Other/Proprietary License", RESTRICTED),
    ("All Rights Reserved", RESTRICTED),
    # weak / file-level copyleft, and GPL with a linking exception
    ("LGPL-3.0-only", WEAK),
    ("GNU Lesser General Public License v2 or later (LGPLv2+)", WEAK),
    ("MPL-2.0", WEAK),
    ("Mozilla Public License 2.0 (MPL 2.0)", WEAK),
    ("EPL-2.0", WEAK),
    ("CDDL-1.1", WEAK),
    ("Ms-PL", WEAK),
    ("OFL-1.1", WEAK),
    ("CC-BY-SA-4.0", WEAK),
    ("Artistic-1.0", WEAK),
    ("CeCILL-C", WEAK),
    ("GPL-2.0-with-classpath-exception", WEAK),
    ("GPL-2.0-only WITH Classpath-exception-2.0", WEAK),
    ("GPL-3.0-only WITH GCC-exception-3.1", WEAK),
    ("GPL-3.0-only WITH Nonsense-exception-1.0", RESTRICTED),
    # permissive
    ("MIT", PERMISSIVE),
    ("MIT License", PERMISSIVE),
    ("Expat", PERMISSIVE),
    ("Apache-2.0", PERMISSIVE),
    ("Apache Software License", PERMISSIVE),
    ("BSD-3-Clause", PERMISSIVE),
    ("BSD License", PERMISSIVE),
    ("0BSD", PERMISSIVE),
    ("ISC", PERMISSIVE),
    ("Zlib", PERMISSIVE),
    ("Unlicense", PERMISSIVE),
    ("The Unlicense (Unlicense)", PERMISSIVE),
    ("CC0-1.0", PERMISSIVE),
    ("CC-BY-4.0", PERMISSIVE),
    ("BSL-1.0", PERMISSIVE),
    ("Boost Software License 1.0 (BSL-1.0)", PERMISSIVE),
    ("Python Software Foundation License", PERMISSIVE),
    ("PSF-2.0", PERMISSIVE),
    ("Ruby", PERMISSIVE),
    ("Ruby's", PERMISSIVE),
    ("Artistic-2.0", PERMISSIVE),
    ("NCSA", PERMISSIVE),
    ("UPL-1.0", PERMISSIVE),
    ("HPND", PERMISSIVE),
    # SPDX expressions: OR takes the best branch, AND takes the worst
    ("MIT OR GPL-3.0-only", PERMISSIVE),
    ("(MIT OR Apache-2.0)", PERMISSIVE),
    ("Ruby OR BSD-2-Clause", PERMISSIVE),
    ("MIT AND GPL-3.0-only", RESTRICTED),
    ("MPL-2.0 AND (Apache-2.0 OR MIT)", WEAK),
    ("(MIT AND Zlib) OR AGPL-3.0", PERMISSIVE),
    ("LGPL-2.1-only OR MPL-1.1", WEAK),
    # statements that carry no license information must not be guessed at
    ("", UNKNOWN),
    ("Dual License", UNKNOWN),
    ("SEE LICENSE IN LICENSE.md", UNKNOWN),
    ("Custom", UNKNOWN),
    ("OSI Approved", UNKNOWN),
    ("Free", UNKNOWN),
    # our own code
    ("LicenseRef-OpenC3-Builders-License", FIRST_PARTY),
    ("OpenC3", FIRST_PARTY),
]

# (pnpm lockfile identifier, expected (name, version) or None)
PNPM_ID_CASES: list[tuple[str, tuple[str, str] | None]] = [
    ("vue@3.5.40", ("vue", "3.5.40")),
    ("@babel/core@7.29.7", ("@babel/core", "7.29.7")),
    ("string_decoder@1.3.0", ("string_decoder", "1.3.0")),
    ("date-fns-tz@1.3.8(date-fns@2.21.3)", ("date-fns-tz", "1.3.8")),
    ("eslint-plugin-vue@10.5.0(eslint@9.39.1(jiti@2.6.1))", ("eslint-plugin-vue", "10.5.0")),
    ("@openc3/js-common@6.0.0", ("@openc3/js-common", "6.0.0")),
    ("link:../openc3-js-common", None),
    ("foo@workspace:*", None),
    ("some-pkg@github:user/repo", None),
]


def run_self_test() -> int:
    failures = 0
    for text, expected in SELF_TEST_CASES:
        name, category = classify([text])
        if category != expected:
            failures += 1
            print(f"FAIL  {text!r}: expected {expected}, got {category} (as {name!r})")
    for identifier, expected in PNPM_ID_CASES:
        actual = split_pnpm_id(identifier)
        if actual != expected:
            failures += 1
            print(f"FAIL  {identifier!r}: expected {expected}, got {actual}")

    # An `OR` of equals must stay put, and every category must be ranked.
    if set(RANK) != {FIRST_PARTY, PERMISSIVE, WEAK, UNKNOWN, RESTRICTED}:
        failures += 1
        print("FAIL  RANK does not cover exactly the five categories")
    for _, _, category in LICENSE_PATTERNS:
        if category not in RANK:
            failures += 1
            print(f"FAIL  LICENSE_PATTERNS uses unranked category {category!r}")
    for key in EXCEPTIONS:
        if not re.match(r"^(ruby|python|js):.+", key):
            failures += 1
            print(f"FAIL  EXCEPTIONS key {key!r} is not '<ecosystem>:<name>[@<version>]'")
        if not EXCEPTIONS[key].strip():
            failures += 1
            print(f"FAIL  EXCEPTIONS[{key!r}] has no reason")

    total = len(SELF_TEST_CASES) + len(PNPM_ID_CASES)
    if failures:
        print(f"\n{failures} self-test failure(s) out of {total} checks")
        return 1
    print(f"self-test: {total} checks passed")
    return 0


# ==========================================================================
# CLI
# ==========================================================================


def default_cache_path() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    root = Path(base) if base else Path.home() / ".cache"
    return root / "openc3-license-audit" / "licenses.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Audit every resolved COSMOS dependency for restrictive (GPL/AGPL/SSPL/...) licenses.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:")[-1],
    )
    parser.add_argument("--repo-root", type=Path, default=None, help="repository root (default: git toplevel)")
    parser.add_argument(
        "--ecosystem", default="ruby,python,js",
        help="comma-separated subset of ruby,python,js to audit (default: all)",
    )
    parser.add_argument(
        "--fail-on", choices=sorted(FAIL_LEVELS), default="restricted",
        help="lowest verdict that makes the audit fail (default: restricted)",
    )
    parser.add_argument(
        "--show", choices=("findings", "all"), default="findings",
        help="list only restricted/unknown/weak packages (default) or every package",
    )
    parser.add_argument("--prod-only", action="store_true", help="audit only packages that reach a shipped artifact")
    parser.add_argument("--offline", action="store_true", help="never query registries; use local metadata and cache")
    parser.add_argument("--refresh", action="store_true", help="ignore the cache and re-query registries")
    parser.add_argument("--no-cache", action="store_true", help="do not read or write the on-disk cache")
    parser.add_argument("--cache", type=Path, default=None, help=f"cache location (default: {default_cache_path()})")
    parser.add_argument("--workers", type=int, default=12, help="concurrent registry requests (default: 12)")
    parser.add_argument("--json", type=Path, default=None, metavar="FILE", help="write the full report as JSON")
    parser.add_argument("--csv", type=Path, default=None, metavar="FILE", help="write one row per package as CSV")
    parser.add_argument(
        "--allow-unlisted-manifests", action="store_true",
        help="do not fail when a lockfile in the repo is unclassified by the policy",
    )
    parser.add_argument("--quiet", action="store_true", help="only print the verdict and any findings")
    parser.add_argument(
        "--self-test", action="store_true",
        help="check the license classifier against its known-answer cases and exit",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    root = (args.repo_root or repo_root_from(Path(__file__).resolve().parent)).resolve()
    ecosystems = {name.strip() for name in args.ecosystem.split(",") if name.strip()}
    unknown_ecosystems = ecosystems - set(PARSERS)
    if unknown_ecosystems:
        parser.error(f"unknown ecosystem(s): {', '.join(sorted(unknown_ecosystems))}")

    try:
        packages, manifest_rows, lock_dirs = collect_packages(root, ecosystems)
    except AuditError as error:
        print(f"license_audit: {error}", file=sys.stderr)
        return 2

    if args.prod_only:
        packages = [package for package in packages if not package.dev]

    cache = LicenseCache(None if args.no_cache else (args.cache or default_cache_path()), refresh=args.refresh)
    resolve_licenses(
        packages, lock_dirs, cache,
        offline=args.offline, workers=max(1, args.workers), progress=not args.quiet,
    )
    cache.save()

    rows = audit(packages)
    unlisted = find_unlisted_lockfiles(root)
    print_report(rows, manifest_rows, unlisted, root, show_all=args.show == "all")

    if args.json:
        write_json(args.json, rows, manifest_rows, unlisted, root)
        print(f"JSON report written to {args.json}")
    if args.csv:
        write_csv(args.csv, rows)
        print(f"CSV written to {args.csv}")

    failing_categories = FAIL_LEVELS[args.fail_on]
    failures = [row for row in rows if row["category"] in failing_categories and not row["excused"]]
    coverage_failure = bool(unlisted) and not args.allow_unlisted_manifests and args.fail_on != "never"

    if failures:
        worst = sorted({row["category"] for row in failures}, key=lambda c: -RANK[c])
        print(
            f"FAIL: {len(failures)} package(s) at or above '{args.fail_on}' "
            f"({', '.join(worst)}) out of {len(rows)} audited."
        )
        print("      Remove the dependency, replace it, obtain a commercial license, or -- if")
        print("      it genuinely cannot taint a shipped artifact -- add a reviewed entry to")
        print("      EXCEPTIONS in this script explaining why.")
        return 1
    if coverage_failure:
        print(f"FAIL: {len(unlisted)} lockfile(s) in the repository are not covered by this audit.")
        return 1
    print(f"PASS: {len(rows)} dependencies audited, none at or above '{args.fail_on}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
