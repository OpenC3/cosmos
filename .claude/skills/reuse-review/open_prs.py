#!/usr/bin/env python3
"""Fetch open PRs that touch a set of roots, then grep their diffs.

Usage:
  python3 open_prs.py fetch <out-dir> <root> [<root> ...]
  python3 open_prs.py grep <out-dir> <regex> [<regex> ...]

fetch: lists open PRs (gh pr list), keeps those changing a file under any
root, and saves pr<N>.diff and pr<N>.md (title + body) plus index.tsv.
Run it from the repo so gh resolves the remote.

grep: for each regex, prints every PR hunk whose changed lines or enclosing
function match. The function is the last declaration seen in the hunk, else
the enclosing one in the local file, else the @@ header. A code hunk that
can't be placed in the local file has no known method, so it matches when its
file mentions the regex anywhere, and is marked "local file differs". Output lines
are "#N file [function] (+adds/-dels) first line". Run from the repo.
A match is a lead: read the hunk to tell a fix from an overlap.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def fetch(out, roots):
    # Repo-relative roots: "./openc3/lib" -> "openc3/lib"; "." matches every file
    roots = [os.path.normpath(r) for r in roots]
    prs = json.loads(
        subprocess.check_output(
            ["gh", "pr", "list", "--state", "open", "--limit", "300", "--json", "number,title,body,files"]
        )
    )
    selected = []
    for pr in prs:
        paths = [f["path"] for f in pr["files"]]
        hits = [p for p in paths if any(r == "." or p == r or p.startswith(r + "/") for r in roots)]
        if hits:
            selected.append(
                (pr, len(hits), subprocess.check_output(["gh", "pr", "diff", str(pr["number"])], text=True))
            )
    # Write the new snapshot to a staging dir first, so a failed write leaves the old one intact
    os.makedirs(out, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=".staging-", dir=out)
    try:
        rows = []
        for pr, hits, diff in selected:
            n = pr["number"]
            with open(os.path.join(staging, f"pr{n}.diff"), "w") as f:
                f.write(diff)
            with open(os.path.join(staging, f"pr{n}.md"), "w") as f:
                f.write(f"# #{n} {pr['title']}\n\n{pr['body'] or ''}\n")
            rows.append(f"{n}\t{pr['title']}\t{hits}")
        with open(os.path.join(staging, "index.tsv"), "w") as f:
            f.write("\n".join(rows) + "\n")
        # Publish: drop a closed PR's files, then rename each new file in (same filesystem, so no copy fails)
        new = set(os.listdir(staging))
        for old in glob.glob(os.path.join(out, "pr*.diff")) + glob.glob(os.path.join(out, "pr*.md")):
            if os.path.basename(old) not in new:
                os.remove(old)
        for name in sorted(new - {"index.tsv"}) + ["index.tsv"]:
            os.replace(os.path.join(staging, name), os.path.join(out, name))
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print(f"{len(rows)} open PRs touch {', '.join(roots)}; saved to {out}")
    print("\n".join(rows))


# A method or function declaration (Python, Ruby, JS/Vue), after the one-char
# diff prefix. Git names a hunk by the nearest unindented line above it, so a
# Python method body change is usually credited to its class. Method identity
# comes from, in order: a declaration seen in the hunk (context or changed); the
# enclosing declaration in the local copy of the file, found from the hunk's old
# line numbers; the @@ header.
DECL = re.compile(
    r"^[ +-]\s*(?:(?:export|async|static|public|private|protected)\s+)*"
    r"(?:(?:def|function|class|module)\s+[\w.?!=]+|(?!(?:if|for|while|switch|catch|return)\b)[A-Za-z_]\w*\s*\([^)]*\)\s*\{\s*$)"
)
HUNK = re.compile(r"^@@ -(\d+)")
CODE = (".py", ".rb", ".js", ".ts", ".vue")


def indent(text):
    return len(text) - len(text.lstrip())


def enclosing(lines, line_no, body):
    """Return the nearest declaration above line_no (1-based) indented less than body."""
    limit = indent(body) if body.strip() else None
    for text in reversed(lines[: max(line_no - 1, 0)]):
        if DECL.match(" " + text) and (limit is None or indent(text) < limit):
            return text.strip()
    return None


def locate(lines, old, start):
    """Return where (1-based) the hunk's old-side lines sit in lines, or None.

    The hunk's line numbers refer to the PR's base, which can differ from the
    local checkout, so check the stated start, then the nearest exact match.
    """
    if not old:
        return start
    size = len(old)
    hits = [i + 1 for i in range(len(lines) - size + 1) if lines[i : i + size] == old]
    return min(hits, key=lambda i: abs(i - start), default=None)


def parse(path):
    """Return the hunks of a diff file as (file, @@ header, old start, lines)."""
    hunks, cur = [], None
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("diff --git "):
                cur = None
            elif line.startswith("--- a/"):
                cur = line[6:].strip()  # kept when the file is deleted (+++ /dev/null)
            elif line.startswith("+++ b/"):
                cur = line[6:].strip()
            elif line.startswith("@@"):
                m = HUNK.match(line)
                hunks.append((cur, line.split("@@")[-1].strip(), int(m.group(1)) if m else 0, []))
            elif hunks and line.startswith((" ", "+", "-")) and not line.startswith(("+++", "---")):
                hunks[-1][3].append(line)
    return hunks


def load(out):
    try:
        root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        root = os.getcwd()
    root = os.path.realpath(root)
    cache = {}

    def local(rel):
        # rel comes from a PR diff, so read only files inside the repo
        if rel not in cache:
            target = os.path.realpath(os.path.join(root, rel))
            cache[rel] = []
            if os.path.commonpath([root, target]) == root:
                try:
                    with open(target, errors="replace") as f:
                        cache[rel] = f.read().splitlines()
                except OSError:
                    pass  # added in the PR or missing locally: no lookup, use the @@ header
        return cache[rel]

    diffs = {}
    for path in sorted(glob.glob(os.path.join(out, "pr*.diff"))):
        rows = []
        for cur, hdr, start, lines in parse(path):
            text = local(cur) if cur else []
            old_ln = locate(text, [x[1:] for x in lines if x[0] != "+"], start) if text else None
            # Unplaced code hunk whose header names no method (a class, say):
            # the method is unknown, so grep falls back to matching anywhere in the
            # file (local copy and the hunk itself)
            method_hdr = DECL.match(" " + hdr) and not re.match(r"(class|module)\b", hdr)
            unplaced = text and old_ln is None and cur.endswith(CODE) and not method_hdr
            scope = "\n".join(text + lines) if unplaced else None
            decl = None
            for line in lines:
                if DECL.match(line):
                    decl = line[1:].strip()
                if line[0] != " ":
                    where = decl or (old_ln and enclosing(text, old_ln, line[1:])) or hdr
                    rows.append((cur, where, line, None if decl else scope))
                if line[0] != "+" and old_ln:
                    old_ln += 1
        diffs[os.path.basename(path)[2:-5]] = rows
    return diffs


def grep(out, patterns):
    diffs = load(out)
    for pattern in patterns:
        rx = re.compile(pattern)
        found = []
        for n, rows in diffs.items():
            hunks = {}
            for f, h, line, scope in rows:
                if not f or "/test" in f or "/spec/" in f:
                    continue
                if rx.search(line) or rx.search(h):
                    hunks.setdefault((f, h, scope is not None), []).append(line)
                elif scope is not None and rx.search(scope):
                    hunks.setdefault((f, h, True), []).append(line)
            for (f, h, unsure), lines in hunks.items():
                adds = sum(1 for x in lines if x[0] == "+")
                note = " (local file differs: method unknown, read the hunk)" if unsure else ""
                found.append(f"  #{n} {f} [{h[:50]}]{note} (+{adds}/-{len(lines) - adds}) {lines[0][:100]}")
        print(f"{pattern}: {'none' if not found else ''}")
        if found:
            print("\n".join(found))


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] not in ("fetch", "grep"):
        sys.exit(__doc__)
    (fetch if sys.argv[1] == "fetch" else grep)(sys.argv[2], sys.argv[3:])
