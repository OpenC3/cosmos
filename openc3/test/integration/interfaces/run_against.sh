#!/usr/bin/env bash
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

# Run the socket throughput tests in this checkout against the openc3 code at
# a different git ref, e.g. to show the problem on main:
#
#   ./run_against.sh main          # Ruby and Python
#   ./run_against.sh main ruby
#   ./run_against.sh main python
#
# The ref is checked out into a temporary git worktree. The Ruby C extensions
# aren't in git so the ones built in this checkout (bundle exec rake build)
# are copied into the worktree.

set -euo pipefail

REF=${1:?usage: $0 <git ref> [ruby|python|all]}
WHICH=${2:-all}

HERE=$(cd "$(dirname "$0")" && pwd)
OPENC3=$(cd "$HERE/../../.." && pwd)
REPO=$(git -C "$OPENC3" rev-parse --show-toplevel)

WORKTREE=$(mktemp -d)
cleanup() {
  git -C "$REPO" worktree remove --force "$WORKTREE" > /dev/null 2>&1 || rm -rf "$WORKTREE"
}
trap cleanup EXIT

git -C "$REPO" worktree add --quiet --detach "$WORKTREE" "$REF"
echo "Testing openc3 at $REF ($(git -C "$WORKTREE" rev-parse --short HEAD))"

status=0

if [[ "$WHICH" == "all" || "$WHICH" == "ruby" ]]; then
  if ! git -C "$REPO" diff --quiet "$REF" HEAD -- openc3/ext; then
    echo "WARNING: openc3/ext differs between $REF and HEAD, the copied C extensions may not match"
  fi
  cp "$OPENC3"/lib/openc3/ext/*.{bundle,so} "$WORKTREE/openc3/lib/openc3/ext/" 2> /dev/null || true
  (cd "$OPENC3" && OPENC3_TEST_LIB="$WORKTREE/openc3/lib" bundle exec rspec test/integration/interfaces/ruby) || status=1
fi

if [[ "$WHICH" == "all" || "$WHICH" == "python" ]]; then
  (cd "$OPENC3/python" && OPENC3_TEST_PYTHON="$WORKTREE/openc3/python" \
    uv run pytest ../test/integration/interfaces/python -s -p no:cacheprovider) || status=1
fi

exit $status
