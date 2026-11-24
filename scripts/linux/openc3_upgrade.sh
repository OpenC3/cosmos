#!/bin/bash

set -e

if ! command -v git &> /dev/null
then
  echo "git not found!!!"
  exit 1
fi

# Determine if this is Core or Enterprise installation
REPO_ROOT="$(git rev-parse --show-toplevel)"
# Run from the project root so the diff, pathspecs and 'git apply' all agree
# on paths no matter which directory openc3.sh was started from.
cd "$REPO_ROOT"
if [[ -d "$REPO_ROOT/openc3-enterprise-traefik" ]]; then
  IS_ENTERPRISE=true
else
  IS_ENTERPRISE=false
fi

# Files the user owns. COSMOS never ships these, so the upgrade must never
# touch them. Without the exclude, a committed compose.override.yaml shows up
# in 'git diff -R <tag>' as a deletion (it doesn't exist in the tag) and would
# be removed. plugins/ holds the user's own plugins, and custom/ the Dockerfiles
# for images that extend COSMOS (docs/guides/container-extension.md).
EXCLUDE_PATHSPECS=(
  ':(exclude)plugins/'
  ':(exclude)compose.override.yaml'
  ':(exclude).env.local'
  ':(exclude)custom/'
)

usage() {
  echo "Usage: openc3.sh upgrade <tag> --preview" >&2
  echo "e.g. openc3.sh upgrade v6.4.1" >&2
  echo "The '--preview' flag will show the diff without applying changes." >&2
  if [[ "$IS_ENTERPRISE" == false ]]; then
    echo "" >&2
    echo "You can also upgrade to Enterprise versions of OpenC3 if you have access" >&2
    echo "e.g. openc3.sh upgrade enterprise-v6.4.1" >&2
    echo "NOTE: Upgrading to Enterprise preserves all your existing data" >&2
    echo "but is a one-way operation and cannot be undone." >&2
  fi
  exit 1
}

if [[ "$#" -eq 0 ]]; then
  usage $0
fi

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage $0
fi

if [[ "$IS_ENTERPRISE" == true ]] || echo "$1" | grep -qi "enterprise"; then
  UPGRADING_TO_ENTERPRISE=true
else
  UPGRADING_TO_ENTERPRISE=false
fi

# Strip a leading "enterprise-" from the tag argument if present
case "$1" in
  enterprise-*) tag="${1#enterprise-}" ;;
  *) tag="$1" ;;
esac

# OPENC3_UPGRADE_REEXEC is set when this script was started by an older
# version of itself (see below), which already set up the remote and fetched.
if [[ -z "$OPENC3_UPGRADE_REEXEC" ]]; then
  # Setup the 'cosmos' remote for core or enterprise
  if [[ "$UPGRADING_TO_ENTERPRISE" == true ]]; then
    COSMOS_URL="https://github.com/OpenC3/cosmos-enterprise-project.git"
    REMOTE_DESC="enterprise"
  else
    COSMOS_URL="https://github.com/OpenC3/cosmos-project.git"
    REMOTE_DESC="core"
  fi
  if git remote -v | grep -q '^cosmos[[:space:]]'; then
    echo "Setting 'cosmos' remote to the $REMOTE_DESC repository."
    git remote set-url cosmos "$COSMOS_URL"
  else
    echo "Adding 'cosmos' remote for the $REMOTE_DESC repository."
    git remote add cosmos "$COSMOS_URL"
  fi

  # Fetch the latest changes from the 'cosmos' remote
  echo "Fetching latest changes from 'cosmos' remote."
  git fetch cosmos
fi

# Check the tag is valid
if ! git tag | grep -q "^$tag$"; then
  echo "Error: '$tag' is not a valid git tag." >&2
  echo "Available tags:" >&2
  git tag | sort
  usage $0
fi

# Get the commit hash for the tag
hash="$(git ls-remote cosmos refs/tags/$tag | awk '{print $1}')"

# Run the upgrade logic from the version being installed rather than this
# (older) copy, so fixes to the upgrade itself - like new files to exclude -
# apply to the upgrade that delivers them. Only hand off to a script that
# knows about OPENC3_UPGRADE_REEXEC; an older tag's script would hand back.
if [[ -z "$OPENC3_UPGRADE_REEXEC" ]]; then
  new_script="$(git cat-file -p "$hash:scripts/linux/openc3_upgrade.sh" 2> /dev/null || true)"
  if [[ "$new_script" == *OPENC3_UPGRADE_REEXEC* ]]; then
    echo "Running the upgrade script from '$tag'."
    OPENC3_UPGRADE_REEXEC=1 exec bash -c "$new_script" "$0" "$@"
  fi
fi

# Warn if upgrading from core to enterprise (but not if just previewing)
if [[ "$IS_ENTERPRISE" == false ]] && [[ "$UPGRADING_TO_ENTERPRISE" == true ]] && [[ "$2" != "--preview" ]]; then
  echo "" >&2
  echo "WARNING: You are upgrading from OpenC3 Core to OpenC3 Enterprise." >&2
  echo "This is a ONE-WAY operation and CANNOT be undone." >&2
  echo "All your existing data will be preserved, but you will not be able" >&2
  echo "to downgrade back to the Core version." >&2
  echo "" >&2
  read -p "Are you sure you want to continue? (yes/no): " -r
  echo
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Upgrade cancelled."
    exit 1
  fi
fi

# Run the release's project migrations, if it ships any, before its files
# replace the user's. They carry user settings forward when a release moves
# them (e.g. out of a file the upgrade is about to replace) and print anything
# the user must still do. With --preview they only report. A failure stops the
# upgrade before anything changes.
migrate_script="$(git cat-file -p "$hash:scripts/linux/openc3_upgrade_migrate.sh" 2> /dev/null || true)"
if [[ -n "$migrate_script" ]]; then
  bash -c "$migrate_script" openc3_upgrade_migrate.sh "$hash" "$2"
fi

# If the --preview flag is set, show the diff without applying changes
if [[ "$2" == "--preview" ]]; then
  git diff -R $hash -- . "${EXCLUDE_PATHSPECS[@]}"
  exit 0
fi

git diff -R $hash --binary -- . "${EXCLUDE_PATHSPECS[@]}" | git apply --whitespace=fix
echo "Applied changes from tag '$1'."
echo "We recommend committing these changes to your local repository."
echo "e.g. git commit -am 'Upgrade to $1'"
echo "You can now run 'openc3.sh run' to start the upgraded OpenC3 environment."
echo
