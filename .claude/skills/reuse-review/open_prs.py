#!/usr/bin/env python3
"""Fetch open PRs that touch a set of roots, then grep their diffs.

Usage:
  python3 open_prs.py fetch <out-dir> <root> [<root> ...]
  python3 open_prs.py grep <out-dir> <regex> [<regex> ...]

fetch: lists open PRs (gh pr list), keeps those changing a file under any
root, and saves pr<N>.diff and pr<N>.md (title + body) plus index.tsv.
Run it from the repo so gh resolves the remote.

grep: for each regex, prints every PR hunk whose changed lines or enclosing
function (the @@ header) match, as "#N file [function] (+adds/-dels) first line".
A match is a lead: read the hunk to tell a fix from an overlap.
"""

import glob
import json
import os
import re
import subprocess
import sys


def fetch(out, roots):
    os.makedirs(out, exist_ok=True)
    prs = json.loads(
        subprocess.check_output(
            ["gh", "pr", "list", "--state", "open", "--limit", "300", "--json", "number,title,body,files"]
        )
    )
    rows = []
    for pr in prs:
        paths = [f["path"] for f in pr["files"]]
        hits = [p for p in paths if any(p.startswith(r.rstrip("/") + "/") or p == r for r in roots)]
        if not hits:
            continue
        n = pr["number"]
        with open(os.path.join(out, f"pr{n}.diff"), "w") as f:
            f.write(subprocess.check_output(["gh", "pr", "diff", str(n)], text=True))
        with open(os.path.join(out, f"pr{n}.md"), "w") as f:
            f.write(f"# #{n} {pr['title']}\n\n{pr['body'] or ''}\n")
        rows.append(f"{n}\t{pr['title']}\t{len(hits)}")
    with open(os.path.join(out, "index.tsv"), "w") as f:
        f.write("\n".join(rows) + "\n")
    print(f"{len(rows)} open PRs touch {', '.join(roots)}; saved to {out}")
    print("\n".join(rows))


def load(out):
    diffs = {}
    for path in sorted(glob.glob(os.path.join(out, "pr*.diff"))):
        n = os.path.basename(path)[2:-5]
        cur, hdr, rows = None, "", []
        for line in open(path, errors="replace"):
            if line.startswith("+++ b/"):
                cur = line[6:].strip()
            elif line.startswith("@@"):
                hdr = line.split("@@")[-1].strip()
            elif line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
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
