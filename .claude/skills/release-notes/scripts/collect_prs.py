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

"""Collect the PRs in a release for writing release notes.

Usage:
  python3 collect_prs.py --repo OpenC3/cosmos --tag v7.6.0 --previous v7.5.1 \
      --out /path/to/dir [--target main]

Writes two files to --out (prefixed with the repo name, e.g. cosmos-):
  <name>-generated.md  GitHub's "Generate release notes" output (What's Changed,
                       New Contributors, Full Changelog). Same as the button.
  <name>-prs.md        One entry per PR: title, author, the PR's "Release notes"
                       section when it has one, otherwise the start of the body.

--target is the branch or commit to release from when --tag doesn't exist yet.
Requires an authenticated `gh`.
"""

import argparse
import json
import re
import subprocess
import sys

BODY_EXCERPT_CHARS = 1500


def gh(*args, input_text=None):
    result = subprocess.run(["gh", *args], input=input_text, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"gh {' '.join(args)} failed:\n{result.stderr}")
    return result.stdout


def generate_notes(repo, tag, previous, target):
    args = ["api", f"repos/{repo}/releases/generate-notes", "-X", "POST", "-f", f"tag_name={tag}", "-f", f"previous_tag_name={previous}"]
    if target:
        args += ["-f", f"target_commitish={target}"]
    return json.loads(gh(*args))["body"]


def fetch_prs(repo, numbers):
    owner, name = repo.split("/")
    prs = {}
    for i in range(0, len(numbers), 40):
        chunk = numbers[i : i + 40]
        fields = "number title body author { login } labels(first: 20) { nodes { name } }"
        aliases = "\n".join(f"pr{n}: pullRequest(number: {n}) {{ {fields} }}" for n in chunk)
        query = f'query {{ repository(owner: "{owner}", name: "{name}") {{ {aliases} }} }}'
        data = json.loads(gh("api", "graphql", "-f", f"query={query}"))
        for pr in data["data"]["repository"].values():
            if pr:
                prs[pr["number"]] = pr
    return prs


def strip_comments(text):
    return re.sub(r"<!--.*?-->", "", text or "", flags=re.S).strip()


def release_notes_section(body):
    """Return the PR template's '## Release notes' section, or None if absent."""
    match = re.search(r"^##+\s*Release notes\s*$(.*?)(?=^##?\s|\Z)", body or "", flags=re.S | re.M | re.I)
    if not match:
        return None
    return strip_comments(match.group(1))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--previous", required=True)
    parser.add_argument("--target")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    prefix = f"{args.out}/{args.repo.split('/')[1]}"
    generated = generate_notes(args.repo, args.tag, args.previous, args.target)
    with open(f"{prefix}-generated.md", "w") as f:
        f.write(generated)

    pr_url = re.compile(rf"https://github\.com/{re.escape(args.repo)}/pull/(\d+)")
    whats_changed = generated.split("## New Contributors")[0]
    numbers = list(dict.fromkeys(int(n) for n in pr_url.findall(whats_changed)))
    prs = fetch_prs(args.repo, numbers)

    with_notes = 0
    lines = [f"# PRs in {args.repo} {args.previous}...{args.tag} ({len(numbers)} PRs)", ""]
    for n in numbers:
        pr = prs.get(n)
        if not pr:
            lines += [f"## #{n} (could not fetch)", ""]
            continue
        author = (pr.get("author") or {}).get("login", "unknown")
        labels = ", ".join(label["name"] for label in pr["labels"]["nodes"])
        lines.append(f"## #{n} {pr['title']}")
        lines.append(f"author: {author}" + (f" | labels: {labels}" if labels else ""))
        notes = release_notes_section(pr["body"])
        if notes is not None:
            with_notes += 1
            lines.append(f"RELEASE NOTES: {notes or 'None'}")
        else:
            body = strip_comments(pr["body"])
            excerpt = body[:BODY_EXCERPT_CHARS] + ("..." if len(body) > BODY_EXCERPT_CHARS else "")
            lines.append("body: " + (excerpt or "(empty)"))
        lines.append("")

    with open(f"{prefix}-prs.md", "w") as f:
        f.write("\n".join(lines))
    print(f"{len(numbers)} PRs ({with_notes} with a Release notes section)")
    print(f"wrote {prefix}-generated.md and {prefix}-prs.md")


if __name__ == "__main__":
    main()
