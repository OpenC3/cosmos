#!/bin/bash
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

# Offline regression test for scripts/linux/openc3_upgrade.sh.
#
# Builds a scratch "cosmos-project" with tags v1 and v2 and a user project
# cloned from v1 that has committed its own compose.override.yaml, .env.local
# and plugins/. Then it checks that 'upgrade v2 --preview' and 'upgrade v2'
# leave those files alone, that the upgrade still applies v2, and that the
# v1 script hands off to the v2 script. A git 'insteadOf' rule points the
# script's hard-coded GitHub URL at the scratch repo, so nothing hits the
# network.
#
# Usage: scripts/tests/test_openc3_upgrade.sh [path/to/openc3_upgrade.sh]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${1:-$ROOT/scripts/linux/openc3_upgrade.sh}"
CORE_URL="https://github.com/OpenC3/cosmos-project.git"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Keep the user's git config out of the test.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset OPENC3_UPGRADE_REEXEC

FAILED=0
fail() {
  echo "FAIL: $*" >&2
  FAILED=1
}

# --- Upstream project with tags v1 and v2 ---------------------------------
UPSTREAM="$WORK/upstream"
git init -q -b main "$UPSTREAM"
mkdir -p "$UPSTREAM/scripts/linux"
cp "$SCRIPT" "$UPSTREAM/scripts/linux/openc3_upgrade.sh"
echo "version: v1" > "$UPSTREAM/compose.yaml"
echo "removed in v2" > "$UPSTREAM/dropped.txt"
printf '.env.local\n' > "$UPSTREAM/.gitignore"
git -C "$UPSTREAM" add -A
git -C "$UPSTREAM" commit -q -m v1
git -C "$UPSTREAM" tag v1

echo "version: v2" > "$UPSTREAM/compose.yaml"
git -C "$UPSTREAM" rm -q dropped.txt
# Mark the v2 script so the test can see the handoff ran it.
awk '{ print } /^set -e$/ { print "echo UPGRADE_SCRIPT_FROM_V2" }' "$SCRIPT" > "$UPSTREAM/scripts/linux/openc3_upgrade.sh"
git -C "$UPSTREAM" add -A
git -C "$UPSTREAM" commit -q -m v2
git -C "$UPSTREAM" tag v2

# --- User project on v1 with its own committed files ----------------------
make_project() {
  local project="$1"
  git clone -q --branch v1 "$UPSTREAM" "$project" 2> /dev/null
  git -C "$project" checkout -q -b main
  git -C "$project" config url."file://$UPSTREAM".insteadOf "$CORE_URL"
  printf 'services:\n  openc3-traefik:\n    ports: ["0.0.0.0:2900:2900"]\n' > "$project/compose.override.yaml"
  echo "OPENC3_EXTERNAL_URL=https://mydomain.com" > "$project/.env.local"
  mkdir -p "$project/plugins/DEFAULT/my-plugin"
  echo "my plugin" > "$project/plugins/DEFAULT/my-plugin/plugin.txt"
  git -C "$project" add -f compose.override.yaml .env.local plugins
  git -C "$project" commit -q -m "user files"
}

USER_FILES=(compose.override.yaml .env.local plugins/DEFAULT/my-plugin/plugin.txt)

check_user_files() {
  local project="$1" label="$2" file
  for file in "${USER_FILES[@]}"; do
    if [[ ! -f "$project/$file" ]]; then
      fail "$label: $file was deleted"
    elif ! git -C "$project" diff --quiet HEAD -- "$file"; then
      fail "$label: $file was modified"
    fi
  done
}

# --- upgrade --preview ----------------------------------------------------
PREVIEW="$WORK/preview"
make_project "$PREVIEW"
preview_out="$(cd "$PREVIEW" && "$PREVIEW/scripts/linux/openc3_upgrade.sh" v2 --preview 2>&1)" ||
  fail "--preview exited non-zero: $preview_out"
check_user_files "$PREVIEW" "--preview"
[[ "$preview_out" == *"version: v2"* ]] || fail "--preview did not show the v2 changes"
for file in "${USER_FILES[@]}"; do
  [[ "$preview_out" != *"$file"* ]] || fail "--preview lists $file"
done
git -C "$PREVIEW" diff --quiet HEAD || fail "--preview changed the working tree"

# --- upgrade --------------------------------------------------------------
# Run from a subdirectory: the script must still apply every path.
UPGRADE="$WORK/upgrade"
make_project "$UPGRADE"
upgrade_out="$(cd "$UPGRADE/plugins" && "$UPGRADE/scripts/linux/openc3_upgrade.sh" v2 2>&1)" ||
  fail "upgrade exited non-zero: $upgrade_out"
check_user_files "$UPGRADE" "upgrade"
[[ "$(cat "$UPGRADE/compose.yaml")" == "version: v2" ]] || fail "upgrade did not apply compose.yaml from v2"
[[ ! -e "$UPGRADE/dropped.txt" ]] || fail "upgrade did not delete a file v2 removed"
[[ "$upgrade_out" == *UPGRADE_SCRIPT_FROM_V2* ]] || fail "upgrade did not hand off to the v2 upgrade script"

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "openc3_upgrade.sh tests passed"
