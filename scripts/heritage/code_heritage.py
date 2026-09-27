#!/usr/bin/env python3
"""
code_heritage.py -- How much of the current code base is still Ball Aerospace
COSMOS 5.0.5?

The question "what percentage of this code is still the original 5.0.5 release"
has no single objectively correct answer, so this tool answers it with two
independent, reproducible measurements and reports both.  See METHODOLOGY.md
for the full rationale.

METHOD 1 -- line provenance via `git blame` (primary, default)
    Every line of every in-scope file at HEAD is attributed, by git blame, to
    the commit that last modified it.  A line is "5.0.5 heritage" if and only
    if that commit is an ancestor of (or is) the baseline tag.  This is the
    standard "code survival" technique (cf. git-of-theseus) and it is exact:
    ancestry is computed from the commit graph, not estimated.

    Because git blame attributes a line to the commit that last *touched* it,
    Method 1 is a LOWER BOUND.  The OpenC3 fork mechanically rewrote the
    Cosmos/COSMOS identifiers to OpenC3/OPENC3 across the tree; every line
    carrying such an identifier is genuinely different text today and is
    correctly, but perhaps unsatisfyingly, counted as post-5.0.5.

METHOD 2 -- normalized content similarity (optional, --content-similarity)
    Each in-scope file at HEAD is mapped back to its 5.0.5 counterpart using
    git's rename/copy detection.  Both versions are normalized (the
    Cosmos->OpenC3 rebranding is undone and license headers are collapsed to a
    single token), then compared with a longest-common-subsequence diff.  The
    number of matching lines is an UPPER BOUND on 5.0.5 heritage: it credits
    any line that is unchanged apart from rebranding, but it cannot tell
    coincidental matches (`end`, `}`, blank lines) from real inheritance.

The truth lies between the two numbers, and the gap between them is itself the
interesting quantity: it is the volume of code that is textually 5.0.5 but was
mechanically rewritten by the fork.

Usage:
    scripts/heritage/code_heritage.py
    scripts/heritage/code_heritage.py --content-similarity
    scripts/heritage/code_heritage.py --scope all --json report.json --csv per-file.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import threading
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher

# --------------------------------------------------------------------------
# Scope definition.  Everything here is deliberately explicit and auditable:
# the credibility of the result depends entirely on what is counted.
# --------------------------------------------------------------------------

# Paths excluded from BOTH trees, because they are not human-authored source.
# Counting generated or vendored third-party files would measure the churn of
# other people's build tools rather than the heritage of this code base.
EXCLUSIONS: list[tuple[str, re.Pattern]] = [
    # `docs/` is the committed output of `docusaurus build --out-dir=../docs`.
    # The human-authored source for it lives in `docs.openc3.com/`.
    ("generated-docs-site", re.compile(r"^docs/")),
    ("generated-lockfile", re.compile(
        r"(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|uv\.lock|"
        r"poetry\.lock|Gemfile\.lock|Cargo\.lock|composer\.lock)$")),
    ("minified-or-sourcemap", re.compile(r"(\.min\.(js|css)|\.map)$")),
    ("vendored", re.compile(r"(^|/)(node_modules|vendor|third_party|thirdparty)(/|$)")),
    ("build-output", re.compile(r"(^|/)(dist|staticdocs|\.yarn|coverage)/")),
    # Third-party browser libraries checked into the tool-base plugin.  They are
    # identified by the version number in the filename (vue-2.6.14.min.js,
    # astro-web-components-7.24.0.css) -- OpenC3's own files there (auth.js,
    # bootstrap.js, browsercheck.js) carry no version and MUST still be counted.
    ("vendored-web-asset", re.compile(
        r"(^|/)(openc3|cosmosc2)-tool-base/public/(js|css)/[^/]*-v?\d+\.\d+[^/]*$")),
    # Google Fonts-generated @font-face stylesheet, shipped verbatim.
    ("vendored-web-asset", re.compile(r"(^|/)roboto\.css$")),
    ("ci-temp", re.compile(r"^\.github/\.tmp/")),
]

# extension -> (language, category)
EXT_MAP: dict[str, tuple[str, str]] = {
    ".rb": ("Ruby", "source"), ".rake": ("Ruby", "source"),
    ".gemspec": ("Ruby", "source"), ".ru": ("Ruby", "source"),
    ".erb": ("Ruby", "source"),
    ".py": ("Python", "source"),
    ".js": ("JavaScript", "source"), ".mjs": ("JavaScript", "source"),
    ".cjs": ("JavaScript", "source"), ".jsx": ("JavaScript", "source"),
    ".ts": ("TypeScript", "source"), ".tsx": ("TypeScript", "source"),
    ".vue": ("Vue", "source"),
    ".c": ("C", "source"), ".h": ("C", "source"),
    ".sh": ("Shell", "source"), ".bat": ("Batch", "source"),
    ".ps1": ("PowerShell", "source"),
    ".css": ("CSS", "source"), ".scss": ("CSS", "source"),
    ".html": ("HTML", "source"),
    # COSMOS target/plugin definitions (cmd.txt, tlm.txt, screens, plugin.txt)
    # are a configuration DSL -- real COSMOS content, but not program source.
    ".txt": ("COSMOS config", "config"),
    ".json": ("JSON", "config"), ".yaml": ("YAML", "config"),
    ".yml": ("YAML", "config"), ".toml": ("TOML", "config"),
    ".xsd": ("XML", "config"), ".xml": ("XML", "config"),
    ".md": ("Markdown", "docs"),
    ".csv": ("Data", "data"), ".bin": ("Data", "data"),
}

BASENAME_MAP: dict[str, tuple[str, str]] = {
    "Rakefile": ("Ruby", "source"), "Gemfile": ("Ruby", "config"),
    "Dockerfile": ("Docker", "source"), "justfile": ("Just", "config"),
    "Makefile": ("Make", "source"),
}

TEST_PATTERNS = re.compile(
    r"(^|/)(spec|test|tests|__tests__)/"
    r"|_spec\.(rb|py)$|_test\.(rb|py)$|(^|/)test_[^/]*\.py$"
    r"|\.(spec|test)\.(js|mjs|cjs|ts|tsx|jsx)$"
)

SCOPES = {
    "code": {"source", "test"},   # default headline scope
    "source": {"source"},         # non-test program source only
    "all": {"source", "test", "config", "docs", "data", "other"},
}

COPY_DETECTION = {
    "none": [],
    "moves": ["-M"],
    "commit": ["-M", "-C"],          # default: also detect copies from files
    "deep": ["-M", "-C", "-C"],      # touched by the same commit
}

# --------------------------------------------------------------------------
# git plumbing helpers
# --------------------------------------------------------------------------


def git(repo: str, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", "-C", repo, *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed ({proc.returncode}): "
            f"{proc.stderr.decode('utf-8', 'replace').strip()}"
        )
    return proc.stdout.decode("utf-8", "replace")


def list_tree(repo: str, ref: str) -> dict[str, str]:
    """Return {path: blob_sha} for regular files in `ref` (no symlinks/submodules)."""
    out = git(repo, "ls-tree", "-r", "-z", ref)
    tree: dict[str, str] = {}
    for entry in out.split("\0"):
        if not entry:
            continue
        meta, path = entry.split("\t", 1)
        mode, obj_type, sha = meta.split()
        if obj_type == "blob" and mode in ("100644", "100755"):
            tree[path] = sha
    return tree


def iter_blobs(repo: str, shas: list[str]):
    """Stream (sha, content_bytes) for each requested blob via one cat-file process."""
    if not shas:
        return
    proc = subprocess.Popen(
        ["git", "-C", repo, "cat-file", "--batch"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    )

    def feed():
        try:
            for sha in shas:
                proc.stdin.write(f"{sha}\n".encode())
            proc.stdin.close()
        except (BrokenPipeError, ValueError):
            pass

    threading.Thread(target=feed, daemon=True).start()
    try:
        for _ in shas:
            header = proc.stdout.readline()
            if not header:
                break
            parts = header.split()
            if len(parts) < 3:
                continue
            sha, size = parts[0].decode(), int(parts[2])
            data = proc.stdout.read(size)
            proc.stdout.read(1)  # trailing newline
            yield sha, data
    finally:
        proc.stdout.close()
        proc.wait()


def count_lines(data: bytes) -> int:
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def is_binary(data: bytes) -> bool:
    return b"\0" in data[:8192]


# --------------------------------------------------------------------------
# classification
# --------------------------------------------------------------------------


def excluded_reason(path: str) -> str | None:
    for reason, pattern in EXCLUSIONS:
        if pattern.search(path):
            return reason
    return None


def classify(path: str) -> tuple[str, str]:
    """Return (language, category) for a path."""
    base = os.path.basename(path)
    _, ext = os.path.splitext(base)
    if base in BASENAME_MAP:
        lang, category = BASENAME_MAP[base]
    elif base.startswith("Dockerfile"):
        lang, category = ("Docker", "source")
    elif ext.lower() in EXT_MAP:
        lang, category = EXT_MAP[ext.lower()]
    else:
        lang, category = ("Other", "other")
    if category == "source" and TEST_PATTERNS.search(path):
        category = "test"
    return lang, category


def component_of(path: str) -> str:
    """Top-level component a path belongs to."""
    head = path.split("/", 1)[0]
    return head if "/" in path else "(root)"


# --------------------------------------------------------------------------
# Method 1 -- blame line provenance
# --------------------------------------------------------------------------

BLAME_HEADER = re.compile(r"^([0-9a-f]{40}) \d+ \d+ (\d+)$")


def blame_file(repo: str, ref: str, path: str, flags: list[str]) -> Counter:
    """Return Counter{commit_sha: line_count} for `path` at `ref`."""
    proc = subprocess.run(
        ["git", "-C", repo, "blame", "--incremental", *flags, ref, "--", path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    counts: Counter = Counter()
    if proc.returncode != 0:
        return counts
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        match = BLAME_HEADER.match(line)
        if match:
            counts[match.group(1)] += int(match.group(2))
    return counts


# --------------------------------------------------------------------------
# Method 2 -- normalized content similarity
# --------------------------------------------------------------------------

LICENSE_LINE = re.compile(
    r"^(?:\#|//|/\*+|\*|<!--|;|@?rem\b|--)\s*.*?\b(?:"
    r"Modified by (?:OpenC3|Ball Aerospace)|if purchased from OpenC3"
    r"|All Rights Reserved|Affero|AGPL|GNU General Public"
    r"|This program is (free|distributed)|Copyright\s+\d{4}"
    r"|under the terms of|as published by the Free Software Foundation"
    r"|Licensed for Government|without any warranty)",
    re.IGNORECASE,
)
COSMOS_TOKEN = re.compile(r"cosmosc2|cosmos", re.IGNORECASE)


def _rebrand(match: re.Match) -> str:
    token = match.group(0)
    if token.isupper():
        return "OPENC3"
    if token[0].isupper():
        return "OpenC3"
    return "openc3"


def normalize(data: bytes, rebrand: bool) -> list[str]:
    """Normalize a blob into comparable lines."""
    text = data.decode("utf-8", "replace")
    out: list[str] = []
    for line in text.splitlines():
        line = " ".join(line.split())  # collapse whitespace, matches blame -w
        if rebrand:
            if LICENSE_LINE.search(line):
                # License headers were replaced wholesale by the fork; collapse
                # recognized comment lines on both sides to a shared token.
                out.append("<<LICENSE>>")
                continue
            line = COSMOS_TOKEN.sub(_rebrand, line)
        out.append(line)
    return out


def matching_lines(old: list[str], new: list[str], max_lines: int) -> int:
    """Count lines of `new` that appear in a longest-common-subsequence with `old`."""
    if not old or not new:
        return 0
    if len(old) > max_lines or len(new) > max_lines:
        # Fall back to an order-insensitive multiset intersection on very large
        # files, where the quadratic LCS is not worth the wall clock.
        return sum((Counter(old) & Counter(new)).values())
    matcher = SequenceMatcher(None, old, new, autojunk=False)
    return sum(block.size for block in matcher.get_matching_blocks())


def build_pairs(repo: str, baseline: str, head: str, threshold: int,
                head_tree: dict, base_tree: dict) -> dict[str, str]:
    """Map {head_path: baseline_path} using git rename/copy detection."""
    out = git(
        repo, "diff", "--name-status", "-z", "-M", "-C",
        f"--find-renames={threshold}%", f"--find-copies={threshold}%",
        "-l5000", baseline, head,
    )
    fields = out.split("\0")
    pairs: dict[str, str] = {}
    i = 0
    while i < len(fields):
        status = fields[i]
        if not status:
            i += 1
            continue
        if status[0] in ("R", "C"):
            old_path, new_path = fields[i + 1], fields[i + 2]
            i += 3
            if new_path in head_tree and old_path in base_tree:
                pairs[new_path] = old_path
        else:
            path = fields[i + 1]
            i += 2
            if status[0] == "M" and path in head_tree and path in base_tree:
                pairs[path] = path
    # Files identical in both trees never appear in the diff at all.
    for path, sha in head_tree.items():
        if path not in pairs and base_tree.get(path) == sha:
            pairs[path] = path
    return pairs


# --------------------------------------------------------------------------
# reporting helpers
# --------------------------------------------------------------------------


def pct(part: int, whole: int) -> float:
    return (100.0 * part / whole) if whole else 0.0


def table(headers: list[str], rows: list[list], aligns: str) -> str:
    cells = [[str(c) for c in row] for row in rows]
    widths = [len(h) for h in headers]
    for row in cells:
        for idx, cell in enumerate(row):
            widths[idx] = max(widths[idx], len(cell))

    def fmt(row, pad=" "):
        parts = []
        for idx, cell in enumerate(row):
            parts.append(cell.ljust(widths[idx], pad) if aligns[idx] == "l"
                         else cell.rjust(widths[idx], pad))
        return "  ".join(parts)

    lines = [fmt(headers), fmt(["-" * w for w in widths], "-")]
    lines.extend(fmt(row) for row in cells)
    return "\n".join("  " + line for line in lines)


def rule(char: str = "=") -> str:
    return char * 78


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure how much of the current code base dates to a baseline release.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--repo", default=".", help="repository path (default: .)")
    parser.add_argument("--baseline", default="v5.0.5",
                        help="baseline ref (default: v5.0.5, the last Ball Aerospace release)")
    parser.add_argument("--head", default="HEAD", help="ref to measure (default: HEAD)")
    parser.add_argument("--scope", choices=sorted(SCOPES), default="code",
                        help="which categories form the headline number (default: code = source+test)")
    parser.add_argument("--copy-detection", choices=sorted(COPY_DETECTION), default="commit",
                        help="git blame move/copy detection level (default: commit = -M -C)")
    parser.add_argument("--no-ignore-whitespace", action="store_true",
                        help="count pure reindentation as a change (default: blame -w)")
    parser.add_argument("--content-similarity", action="store_true",
                        help="also run Method 2 (normalized content similarity upper bound)")
    parser.add_argument("--rename-threshold", type=int, default=30,
                        help="rename/copy similarity threshold for Method 2 (default: 30%%)")
    parser.add_argument("--lcs-max-lines", type=int, default=20000,
                        help="file size above which Method 2 uses a cheaper approximation")
    parser.add_argument("--jobs", type=int, default=min(16, (os.cpu_count() or 4) * 2),
                        help="parallel git blame workers")
    parser.add_argument("--top", type=int, default=15, help="rows per breakdown table")
    parser.add_argument("--json", metavar="PATH", help="write full results as JSON")
    parser.add_argument("--csv", metavar="PATH", help="write per-file results as CSV")
    parser.add_argument("--quiet", action="store_true", help="suppress progress output")
    args = parser.parse_args()

    repo = os.path.abspath(args.repo)
    log = (lambda *a: None) if args.quiet else (lambda *a: print(*a, file=sys.stderr))

    # --- resolve refs and validate the baseline is actually in our history ---
    try:
        baseline_sha = git(repo, "rev-parse", "--verify", f"{args.baseline}^{{commit}}").strip()
        head_sha = git(repo, "rev-parse", "--verify", f"{args.head}^{{commit}}").strip()
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    ancestor = subprocess.run(
        ["git", "-C", repo, "merge-base", "--is-ancestor", baseline_sha, head_sha]
    ).returncode == 0
    if not ancestor:
        print(f"error: {args.baseline} is not an ancestor of {args.head}; "
              "line provenance would be meaningless.", file=sys.stderr)
        return 2

    baseline_desc = git(repo, "log", "-1", "--format=%h %ad %s", "--date=short", baseline_sha).strip()
    head_desc = git(repo, "log", "-1", "--format=%h %ad %s", "--date=short", head_sha).strip()
    commits_since = git(repo, "rev-list", "--count", f"{baseline_sha}..{head_sha}").strip()

    # --- the exact set of commits that constitute "5.0.5 and everything before it" ---
    log("Building baseline commit set...")
    baseline_commits = set(git(repo, "rev-list", baseline_sha).split())

    sha_year: dict[str, str] = {}
    for line in git(repo, "log", "--format=%H %cd", "--date=format:%Y", head_sha).splitlines():
        if " " in line:
            sha, year = line.split(" ", 1)
            sha_year[sha] = year.strip()

    # --- build the in-scope file universe on both sides ---
    log("Listing trees...")
    head_tree_all = list_tree(repo, head_sha)
    base_tree_all = list_tree(repo, baseline_sha)

    excluded: Counter = Counter()
    binary_skipped = 0

    def in_scope_tree(tree: dict[str, str]) -> dict[str, str]:
        kept = {}
        for path, sha in tree.items():
            reason = excluded_reason(path)
            if reason:
                excluded[reason] += 1
                continue
            kept[path] = sha
        return kept

    head_tree = in_scope_tree(head_tree_all)
    base_tree = in_scope_tree(base_tree_all)

    # --- measure blobs: drop binaries, record line counts ---
    log(f"Reading {len(head_tree)} HEAD blobs...")
    head_shas = sorted(set(head_tree.values()))
    blob_lines: dict[str, int] = {}
    blob_binary: dict[str, bool] = {}
    for sha, data in iter_blobs(repo, head_shas):
        blob_binary[sha] = is_binary(data)
        blob_lines[sha] = 0 if blob_binary[sha] else count_lines(data)

    head_files: dict[str, dict] = {}
    for path, sha in head_tree.items():
        if blob_binary.get(sha, True):
            binary_skipped += 1
            excluded["binary"] += 1
            continue
        lang, category = classify(path)
        head_files[path] = {
            "path": path, "sha": sha, "lines": blob_lines[sha],
            "language": lang, "category": category,
            "component": component_of(path), "baseline_lines": 0,
        }

    log(f"Reading {len(base_tree)} baseline blobs...")
    base_shas = sorted(set(base_tree.values()))
    base_blob_lines: dict[str, int] = {}
    base_blob_binary: dict[str, bool] = {}
    for sha, data in iter_blobs(repo, base_shas):
        base_blob_binary[sha] = is_binary(data)
        base_blob_lines[sha] = 0 if base_blob_binary[sha] else count_lines(data)

    base_files: dict[str, dict] = {}
    for path, sha in base_tree.items():
        if base_blob_binary.get(sha, True):
            continue
        lang, category = classify(path)
        base_files[path] = {"sha": sha, "lines": base_blob_lines[sha],
                            "language": lang, "category": category,
                            "component": component_of(path)}

    # --- Method 1: blame every in-scope HEAD file ---
    flags = list(COPY_DETECTION[args.copy_detection])
    if not args.no_ignore_whitespace:
        flags.insert(0, "-w")

    paths = sorted(head_files)
    log(f"Blaming {len(paths)} files with {args.jobs} workers (git blame {' '.join(flags)})...")
    done = 0
    year_lines: Counter = Counter()

    def work(path: str):
        return path, blame_file(repo, head_sha, path, flags)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for path, counts in pool.map(work, paths):
            entry = head_files[path]
            blamed = 0
            heritage = 0
            for sha, n in counts.items():
                blamed += n
                if sha in baseline_commits:
                    heritage += n
                year_lines[sha_year.get(sha, "?")] += n
            entry["baseline_lines"] = heritage
            entry["blamed_lines"] = blamed
            # Trust blame's own line count; it is authoritative for what it measured.
            if blamed:
                entry["lines"] = blamed
            done += 1
            if not args.quiet and done % 250 == 0:
                log(f"  {done}/{len(paths)}")

    # --- aggregate ---
    scope_categories = SCOPES[args.scope]

    def totals(entries, key_fn):
        agg = defaultdict(lambda: [0, 0, 0])  # [files, lines, baseline_lines]
        for e in entries:
            k = key_fn(e)
            agg[k][0] += 1
            agg[k][1] += e["lines"]
            agg[k][2] += e["baseline_lines"]
        return agg

    scoped = [e for e in head_files.values() if e["category"] in scope_categories]
    all_entries = list(head_files.values())

    cur_lines = sum(e["lines"] for e in scoped)
    heritage_lines = sum(e["baseline_lines"] for e in scoped)
    base_scoped_lines = sum(f["lines"] for f in base_files.values()
                            if f["category"] in scope_categories)

    # ------------------------------------------------------------------
    # report
    # ------------------------------------------------------------------
    out: list[str] = []
    add = out.append

    add(rule())
    add(" CODE HERITAGE REPORT")
    add(rule())
    add(f" Baseline : {args.baseline}  ({baseline_desc})")
    add(f" Current  : {args.head}  ({head_desc})")
    add(f" Commits since baseline : {commits_since}")
    add(f" Scope    : {args.scope}  (categories: {', '.join(sorted(scope_categories))})")
    add(f" Blame    : git blame --incremental {' '.join(flags)}")
    add("")

    add(rule("-"))
    add(" METHOD 1 -- line provenance via git blame   [PRIMARY / LOWER BOUND]")
    add(rule("-"))
    add(" Each line at HEAD is attributed to the commit that last modified it;")
    add(" a line is baseline heritage iff that commit is an ancestor of the tag.")
    add("")
    add(f"   Current in-scope lines .................. {cur_lines:>12,}")
    add(f"   ... dating to {args.baseline} or earlier ....... {heritage_lines:>12,}"
        f"   ({pct(heritage_lines, cur_lines):5.2f}%)  <-- RETENTION")
    add(f"   ... written after {args.baseline} ............. {cur_lines - heritage_lines:>12,}"
        f"   ({pct(cur_lines - heritage_lines, cur_lines):5.2f}%)")
    add("")
    add(f"   {args.baseline} in-scope lines ................. {base_scoped_lines:>12,}")
    add(f"   ... still present at HEAD ............... {heritage_lines:>12,}"
        f"   ({pct(heritage_lines, base_scoped_lines):5.2f}%)  <-- SURVIVAL")
    add(f"   Growth factor since baseline ............ {(cur_lines / base_scoped_lines if base_scoped_lines else 0):>12.2f}x")
    add("")

    # per-category (always over all text files, so the reader sees what scope omits)
    cat_agg = totals(all_entries, lambda e: e["category"])
    rows = []
    for cat in sorted(cat_agg, key=lambda c: -cat_agg[c][1]):
        files, lines, herit = cat_agg[cat]
        rows.append([cat + (" *" if cat in scope_categories else ""), f"{files:,}",
                     f"{lines:,}", f"{herit:,}", f"{pct(herit, lines):.2f}%"])
    add(" By category (* = included in the headline scope)")
    add(table(["category", "files", "lines", "from baseline", "retention"],
              rows, "lrrrr"))
    add("")

    lang_agg = totals(scoped, lambda e: e["language"])
    rows = []
    for lang in sorted(lang_agg, key=lambda x: -lang_agg[x][1])[:args.top]:
        files, lines, herit = lang_agg[lang]
        rows.append([lang, f"{files:,}", f"{lines:,}", f"{herit:,}", f"{pct(herit, lines):.2f}%"])
    add(f" By language (scope: {args.scope})")
    add(table(["language", "files", "lines", "from baseline", "retention"], rows, "lrrrr"))
    add("")

    comp_agg = totals(scoped, lambda e: e["component"])
    rows = []
    for comp in sorted(comp_agg, key=lambda x: -comp_agg[x][1])[:args.top]:
        files, lines, herit = comp_agg[comp]
        rows.append([comp, f"{files:,}", f"{lines:,}", f"{herit:,}", f"{pct(herit, lines):.2f}%"])
    add(f" By component (top {args.top}, scope: {args.scope})")
    add(table(["component", "files", "lines", "from baseline", "retention"], rows, "lrrrr"))
    add("")

    add(" Code age profile -- current lines by year of authoring commit")
    total_year = sum(year_lines.values())
    rows = []
    for year in sorted(year_lines):
        n = year_lines[year]
        bar = "#" * max(1, round(40 * n / max(total_year, 1)))
        marker = "  <= baseline" if year <= baseline_desc.split()[1][:4] else ""
        rows.append([year, f"{n:,}", f"{pct(n, total_year):5.2f}%", bar + marker])
    add(table(["year", "lines", "share", ""], rows, "lrrl"))
    add("")

    method2 = None
    if args.content_similarity:
        log("Method 2: mapping files back to baseline...")
        pairs = build_pairs(repo, baseline_sha, head_sha, args.rename_threshold,
                            head_tree, base_tree)
        pairs = {new: old for new, old in pairs.items()
                 if new in head_files and old in base_files}
        log(f"Method 2: comparing {len(pairs)} file pairs...")

        need = sorted({head_files[n]["sha"] for n in pairs} |
                      {base_files[o]["sha"] for o in pairs.values()})
        contents: dict[str, bytes] = dict(iter_blobs(repo, need))

        matched_raw = matched_norm = 0
        paired_lines = paired_m1 = paired_pairs = 0
        for new_path, old_path in pairs.items():
            entry = head_files[new_path]
            if entry["category"] not in scope_categories:
                continue
            new_data = contents.get(entry["sha"], b"")
            old_data = contents.get(base_files[old_path]["sha"], b"")
            paired_pairs += 1
            paired_lines += entry["lines"]
            paired_m1 += entry["baseline_lines"]
            matched_raw += matching_lines(normalize(old_data, False),
                                          normalize(new_data, False), args.lcs_max_lines)
            m = matching_lines(normalize(old_data, True),
                               normalize(new_data, True), args.lcs_max_lines)
            matched_norm += m
            entry["similarity_lines"] = m
            entry["baseline_path"] = old_path

        # Method 2 can only speak about files it could map back to the baseline.
        # Heritage that blame found in files with no baseline counterpart (code
        # extracted or split out of an original file, which blame's -C follows
        # but file-level rename detection does not) is invisible to Method 2 and
        # must be carried over from Method 1, or the two are not comparable.
        unpaired_m1 = heritage_lines - paired_m1
        unpaired_lines = cur_lines - paired_lines

        # A single, uniform ceiling rule: for each file take the stronger of the
        # two pieces of evidence.  For unpaired files Method 2 contributes 0, so
        # the rule reduces to Method 1 there.
        ceiling = sum(max(e["baseline_lines"], e.get("similarity_lines", 0))
                      for e in scoped)

        method2 = {
            "pairs": paired_pairs,
            "paired_lines": paired_lines,
            "paired_method1_lines": paired_m1,
            "matched_verbatim": matched_raw,
            "matched_normalized": matched_norm,
            "unpaired_lines": unpaired_lines,
            "unpaired_method1_lines": unpaired_m1,
            "ceiling_lines": ceiling,
            "ceiling_pct": round(pct(ceiling, cur_lines), 4),
        }

        add(rule("-"))
        add(" METHOD 2 -- normalized content similarity   [UPPER BOUND]")
        add(rule("-"))
        add(" Each HEAD file is mapped to its baseline counterpart via git rename")
        add(" detection, both are normalized (Cosmos->OpenC3 rebranding undone,")
        add(" license headers collapsed), then diffed for common subsequences.")
        add(" Percentages below are against the PAIRED subset, not the full scope:")
        add(" Method 2 is blind to files with no baseline counterpart.")
        add("")
        add(f"   Files traced back to {args.baseline} ............ {paired_pairs:>12,}")
        add(f"   Current lines in those files ........... {paired_lines:>12,}")
        add(f"     Method 1 heritage there .............. {paired_m1:>12,}"
            f"   ({pct(paired_m1, paired_lines):5.2f}% of paired)")
        add(f"     Lines matching verbatim .............. {matched_raw:>12,}"
            f"   ({pct(matched_raw, paired_lines):5.2f}% of paired)")
        add(f"     Lines matching after normalization ... {matched_norm:>12,}"
            f"   ({pct(matched_norm, paired_lines):5.2f}% of paired)")
        add(f"     Gained by undoing the rebranding ..... {matched_norm - matched_raw:>12,}")
        if matched_norm < paired_m1:
            add("   WARNING: Method 2 fell below Method 1 on the paired subset;")
            add("            the normalization or rename threshold needs review.")
        add("")
        add(f"   Files with no {args.baseline} counterpart ....... {len(scoped) - paired_pairs:>12,}")
        add(f"   Current lines in those files ........... {unpaired_lines:>12,}")
        add(f"     Method 1 heritage there .............. {unpaired_m1:>12,}"
            f"   ({pct(unpaired_m1, unpaired_lines):5.2f}% of unpaired)")
        add("     (code blame traced to pre-baseline commits through moves and")
        add("      extractions that file-level rename detection cannot follow)")
        add("")
        add("   Ceiling over the full scope, per file taking the stronger of the")
        add(f"   two measurements ....................... {ceiling:>12,}"
            f"   ({pct(ceiling, cur_lines):5.2f}% of scope)")
        add("")

    add(rule("="))
    add(" BOTTOM LINE")
    add(rule("="))
    add(f"   Of the {cur_lines:,} lines in scope ({args.scope}) in the current tree,")
    add(f"   {heritage_lines:,} ({pct(heritage_lines, cur_lines):.2f}%) are unmodified since"
        f" {args.baseline} or earlier.")
    if method2:
        add("   Crediting every line that is unchanged apart from the mechanical")
        add(f"   Cosmos->OpenC3 rebranding raises that to {ceiling:,} lines"
            f" ({pct(ceiling, cur_lines):.2f}%).")
        add("")
        add(f"   DEFENSIBLE RANGE: {pct(heritage_lines, cur_lines):.1f}% - "
            f"{pct(ceiling, cur_lines):.1f}% of the current code base is 5.0.5-era code.")
        add("")
    add(f"   Conversely, {pct(heritage_lines, base_scoped_lines):.2f}% of {args.baseline}'s"
        f" {base_scoped_lines:,} lines survive today.")
    add("")
    add(" Excluded from all counts (not human-authored source):")
    for reason, n in sorted(excluded.items(), key=lambda kv: -kv[1]):
        add(f"   {n:>6,}  {reason}")
    add("")

    print("\n".join(out))

    # ------------------------------------------------------------------
    # machine-readable outputs
    # ------------------------------------------------------------------
    if args.json:
        payload = {
            "baseline": {"ref": args.baseline, "sha": baseline_sha, "describe": baseline_desc},
            "head": {"ref": args.head, "sha": head_sha, "describe": head_desc},
            "commits_since_baseline": int(commits_since),
            "scope": args.scope,
            "blame_flags": flags,
            "method1": {
                "current_lines": cur_lines,
                "baseline_heritage_lines": heritage_lines,
                "retention_pct": round(pct(heritage_lines, cur_lines), 4),
                "baseline_lines": base_scoped_lines,
                "survival_pct": round(pct(heritage_lines, base_scoped_lines), 4),
            },
            "method2": method2,
            "by_category": {k: {"files": v[0], "lines": v[1], "baseline_lines": v[2]}
                            for k, v in cat_agg.items()},
            "by_language": {k: {"files": v[0], "lines": v[1], "baseline_lines": v[2]}
                            for k, v in lang_agg.items()},
            "by_component": {k: {"files": v[0], "lines": v[1], "baseline_lines": v[2]}
                             for k, v in comp_agg.items()},
            "lines_by_year": dict(sorted(year_lines.items())),
            "excluded": dict(excluded),
        }
        with open(args.json, "w") as handle:
            json.dump(payload, handle, indent=2)
        log(f"wrote {args.json}")

    if args.csv:
        with open(args.csv, "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["path", "component", "language", "category", "lines",
                             "baseline_lines", "retention_pct", "baseline_path",
                             "similarity_lines"])
            for e in sorted(head_files.values(), key=lambda x: x["path"]):
                writer.writerow([
                    e["path"], e["component"], e["language"], e["category"],
                    e["lines"], e["baseline_lines"],
                    f"{pct(e['baseline_lines'], e['lines']):.2f}",
                    e.get("baseline_path", ""), e.get("similarity_lines", ""),
                ])
        log(f"wrote {args.csv}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
