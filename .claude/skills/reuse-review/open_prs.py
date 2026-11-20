#!/usr/bin/env python3
"""Fetch open PRs that touch a set of roots, then grep their diffs.

Usage:
  python3 open_prs.py fetch <out-dir> <root> [<root> ...]
  python3 open_prs.py grep <out-dir> <regex> [<regex> ...]

fetch: lists open PRs (gh pr list), keeps those changing a file under any
root, and saves pr<N>.diff and pr<N>.md (title + body) plus index.tsv.
Run it from the repo so gh resolves the remote.

grep: for each regex, prints every PR hunk whose changed lines or enclosing
function match (the last declaration seen in the hunk, else the @@ header), as "#N file [function] (+adds/-dels) first line".
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


# A method or function declaration (Python, Ruby, JS/Vue). The @@ header names
# the nearest declaration above the hunk, which is wrong when the declaration is
# inside the hunk, so declarations seen in the hunk (context or changed) win.
DECL = re.compile(
    r"^[ +-]\s*(?:(?:export|async|static|public|private|protected)\s+)*"
    r"(?:(?:def|function|class|module)\s+[\w.?!=]+|(?!(?:if|for|while|switch|catch|return)\b)[A-Za-z_]\w*\s*\([^)]*\)\s*\{\s*$)"
)


def load(out):
    diffs = {}
    for path in sorted(glob.glob(os.path.join(out, "pr*.diff"))):
        n = os.path.basename(path)[2:-5]
        cur, hdr, rows = None, "", []
        with open(path, errors="replace") as f:
            for line in f:
                if line.startswith("diff --git "):
                    cur, hdr = None, ""
                elif line.startswith("--- a/"):
                    cur = line[6:].strip()  # kept when the file is deleted (+++ /dev/null)
                elif line.startswith("+++ b/"):
                    cur = line[6:].strip()
                elif line.startswith("@@"):
                    hdr = line.split("@@")[-1].strip()
                elif line.startswith((" ", "+", "-")) and not line.startswith(("+++", "---")):
                    if DECL.match(line):
                        hdr = line[1:].strip()
                    if line[0] != " ":
                        rows.append((cur, hdr, line.rstrip()))
        diffs[n] = rows
    return diffs


def grep(out, patterns):
    diffs = load(out)
    for pattern in patterns:
        rx = re.compile(pattern)
        found = []
        for n, rows in diffs.items():
            hunks = {}
            for f, h, line in rows:
                if f and "/test" not in f and "/spec/" not in f and (rx.search(line) or rx.search(h)):
                    hunks.setdefault((f, h), []).append(line)
            for (f, h), lines in hunks.items():
                adds = sum(1 for x in lines if x[0] == "+")
                found.append(f"  #{n} {f} [{h[:50]}] (+{adds}/-{len(lines) - adds}) {lines[0][:100]}")
        print(f"{pattern}: {'none' if not found else ''}")
        if found:
            print("\n".join(found))


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] not in ("fetch", "grep"):
        sys.exit(__doc__)
    (fetch if sys.argv[1] == "fetch" else grep)(sys.argv[2], sys.argv[3:])
