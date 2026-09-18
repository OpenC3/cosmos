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

if [ "${PYPI_URL:-https://pypi.org}" = "https://pypi.org" ]; then
  echo "--- relock skipped in $(pwd): PYPI_URL=${PYPI_URL:-<unset>} is the public index"
  exit 0
fi

if [ ! -f pyproject.toml ] || [ ! -f uv.lock ]; then
  echo "--- relock skipped in $(pwd): no pyproject.toml + uv.lock to relock"
  exit 0
fi

echo "--- relock $(pwd)/uv.lock against ${PYPI_URL}"
uv lock --no-config --no-sources --default-index "${PYPI_URL}/simple" "$@"
echo "=== relock complete"
