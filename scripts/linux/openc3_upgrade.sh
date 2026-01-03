#!/bin/bash

set -e

if ! command -v git &> /dev/null
then
  echo "git not found!!!"
  exit 1
fi

# Determine if this is Core or Enterprise installation
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [ -d "$REPO_ROOT/openc3-enterprise-traefik" ]; then
  IS_ENTERPRISE=true
else
  IS_ENTERPRISE=false
fi

usage() {
  echo "Usage: openc3.sh upgrade <tag> --preview" >&2
  echo "e.g. openc3.sh upgrade v6.4.1" >&2
  echo "The '--preview' flag will show the diff without applying changes." >&2
  if [ "$IS_ENTERPRISE" = false ]; then
    echo "" >&2
    echo "You can also upgrade to Enterprise versions of OpenC3 if you have access" >&2
    echo "e.g. openc3.sh upgrade enterprise-v6.4.1" >&2
    echo "NOTE: Upgrading to Enterprise preserves all your existing data" >&2
    echo "but is a one-way operation and cannot be undone." >&2
  fi
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  usage $0
fi

tag="$1"

# Setup the 'cosmos' remote based on IS_ENTERPRISE or if upgrading to enterprise
if [ "$IS_ENTERPRISE" = true ] || echo "$1" | grep -qi "enterprise"; then
  COSMOS_URL="https://github.com/OpenC3/cosmos-enterprise-project.git"
  if git remote -v | grep -q '^cosmos[[:space:]]'; then
    echo "Setting 'cosmos' remote to the enterprise repository."
    git remote set-url cosmos "$COSMOS_URL"
  else
    echo "Adding 'cosmos' remote for the enterprise repository."
    git remote add cosmos "$COSMOS_URL"
  fi

  # Warn if upgrading from core to enterprise (but not if just previewing)
  if [ "$IS_ENTERPRISE" = false ] && echo "$1" | grep -qi "enterprise" && [ "$2" != "--preview" ]; then
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
else
  COSMOS_URL="https://github.com/OpenC3/cosmos-project.git"
  if git remote -v | grep -q '^cosmos[[:space:]]'; then
    echo "Setting 'cosmos' remote to the core repository."
    git remote set-url cosmos "$COSMOS_URL"
  else
    echo "Adding 'cosmos' remote for the core repository."
    git remote add cosmos "$COSMOS_URL"
  fi
fi

# Strip a leading "enterprise-" from the tag argument if present
case "$1" in
  enterprise-*) tag="${1#enterprise-}" ;;
  *) tag="$1" ;;
esac

# Fetch the latest changes from the 'cosmos' remote
echo "Fetching latest changes from 'cosmos' remote."
git fetch cosmos

# Check the tag is valid
if ! git tag | grep -q "^$tag$"; then
  echo "Error: '$tag' is not a valid git tag." >&2
  echo "Available tags:" >&2
  git tag | sort
  usage $0
fi

# Get the commit hash for the tag
hash="$(git ls-remote cosmos refs/tags/$tag | awk '{print $1}')"

# If the --preview flag is set, show the diff without applying changes
if [ "$2" == "--preview" ]; then
  git diff -R $hash
  exit 0
fi

git diff -R $hash --binary | git apply --whitespace=fix --exclude="plugins/*"
echo "Applied changes from tag '$1'."
echo "We recommend committing these changes to your local repository."
echo "e.g. git commit -am 'Upgrade to $1'"
echo "You can now run 'openc3.sh run' to start the upgraded OpenC3 environment."
echo
