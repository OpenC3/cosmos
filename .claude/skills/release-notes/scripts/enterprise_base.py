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

"""Turn the published Core release notes into the base for the Enterprise notes.

Usage:
  python3 enterprise_base.py core-notes.md > enterprise-base.md

Core PR numbers like (#4015) don't resolve in the cosmos-enterprise repo, so this
removes them from every section above "What's Changed". It also:
  - renames "OpenC3 COSMOS Core" to "OpenC3 COSMOS Enterprise" (title and intro)
  - renames "## What's Changed" to "## What's Changed in Core" (its entries are
    full https://github.com/OpenC3/cosmos/pull/N links, so they stay)
  - renames "## New Contributors" to "## New Core Contributors"
  - renames "**Full Changelog**" to "**Full Core Changelog**"
"""

import re
import sys

# A parenthesized group of only PR refs: "(#4015)", "(#4058, #4093)", "(#4106, #4109 and #4166)"
REF_GROUP = re.compile(r"\s*\((?:#\d+)(?:\s*(?:,|and|&)\s*#\d+)*\)")
# A ref group inside other parenthesized text: "(#4184): ..." handled above; "(see #4015)" kept
WHATS_CHANGED = re.compile(r"^## What's Changed\s*$", re.M)


def strip_refs(text):
    text = REF_GROUP.sub("", text)
    return re.sub(r"[ \t]+$", "", text, flags=re.M)


def main():
    core = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
    match = WHATS_CHANGED.search(core)
    curated, generated = (core[: match.start()], core[match.start() :]) if match else (core, "")

    curated = strip_refs(curated)
    curated = curated.replace("OpenC3 COSMOS Core", "OpenC3 COSMOS Enterprise")

    generated = WHATS_CHANGED.sub("## What's Changed in Core", generated, count=1)
    generated = re.sub(r"^## New Contributors\s*$", "## New Core Contributors", generated, flags=re.M)
    generated = generated.replace("**Full Changelog**", "**Full Core Changelog**")

    leftover = re.findall(r"#\d{3,}", curated)
    if leftover:
        print(f"warning: PR refs left in curated sections (check by hand): {', '.join(leftover)}", file=sys.stderr)
    sys.stdout.write(curated + generated)


if __name__ == "__main__":
    main()
