#!/bin/sh
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

# Re-resolve the uv.lock in the current directory against the PyPI mirror given
# by PYPI_URL.
#
# uv.lock records an absolute https://files.pythonhosted.org/... URL for every
# wheel and sdist, and `uv sync --frozen` fetches exactly those URLs. The
# UV_DEFAULT_INDEX the base image derives from PYPI_URL only steers dependency
# *resolution*, so by itself it does nothing for a frozen sync - an air-gapped
# build still reaches for pythonhosted.org and fails, mirror or no mirror.
# Re-resolving is what rewrites those URLs, so do it here, and only when a
# mirror is actually configured: a stock build stays frozen against the
# committed lockfile and is unaffected by this script.
#
# Run from a directory holding pyproject.toml and uv.lock. Extra arguments are
# passed through to `uv lock`. Note the re-resolve covers every dependency
# group, dev included, so the mirror has to serve the dev dependencies too even
# though the images never install them.
#
# Every outcome is announced, including the skips. A silent no-op here is
# indistinguishable in a build log from a relock that ran, and that is exactly
# how an air-gapped build quietly regains the failure this script exists to
# prevent - most plausibly when PYPI_URL never reached this image because it
# was built against a base image that predates the current .env.
#
# --no-config --no-sources keep the resolve inside the mirror. --default-index
# does not win on its own: uv searches a named index declared in the project's
# own [tool.uv].index table first, and a package pinned with [tool.uv].sources
# is project metadata that survives --no-config, so without both flags a plugin
# that configures its author's index resolves against it and the air-gapped
# build fails at exactly the point this script exists to prevent. Only the
# mirror is consulted, which is the premise of pointing PYPI_URL at one.
#
# Usage: uv-mirror-relock [uv lock args...]
set -e

# Strip trailing slashes so https://pypi.org/ counts as the public index and a
# mirror URL ending in / does not become .../pypi//simple below.
MIRROR_URL="${PYPI_URL:-https://pypi.org}"
while [ "${MIRROR_URL%/}" != "${MIRROR_URL}" ]; do
  MIRROR_URL="${MIRROR_URL%/}"
done

if [ "${MIRROR_URL}" = "https://pypi.org" ]; then
  echo "--- relock skipped in $(pwd): ${MIRROR_URL} is the public index"
  exit 0
fi

# The same URL without any user:password@ credentials. uv strips credentials
# from the registry URLs it writes to uv.lock, so this is the form to compare
# the lockfile against, and the only form safe to print into a build log.
MIRROR_REST="${MIRROR_URL#*://}"
MIRROR_HOST="${MIRROR_REST%%/*}"
MIRROR_PATH="${MIRROR_REST#"${MIRROR_HOST}"}"
REDACTED_URL="${MIRROR_URL%%://*}://${MIRROR_HOST##*@}${MIRROR_PATH}"

if [ ! -f pyproject.toml ] || [ ! -f uv.lock ]; then
  echo "--- relock skipped in $(pwd): no pyproject.toml + uv.lock to relock"
  exit 0
fi

# A lockfile already generated against the mirror on the host (see the Offline
# Building docs) is kept as committed, so the build installs exactly what was
# locked instead of re-resolving it.
if ! grep -o 'registry = "[^"]*"' uv.lock | grep -qvF "registry = \"${REDACTED_URL}/simple\""; then
  echo "--- relock skipped in $(pwd): uv.lock already resolves only against ${REDACTED_URL}"
  exit 0
fi

echo "--- relock $(pwd)/uv.lock against ${REDACTED_URL}"
uv lock --no-config --no-sources --default-index "${MIRROR_URL}/simple" "$@"
echo "=== relock complete"
