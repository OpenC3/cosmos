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

# Build-time assertion: every plugin gem shipped in this image that declares
# BOTH uv.lock and pyproject.toml must be able to install its Python
# dependencies from the baked UV cache with NO network.
#
# Scope, precisely: this covers exactly the plugins docker-package-build.sh
# warms, which is uvinstall's path 1 (`uv sync --frozen`). uvinstall's fallback
# paths (requirements.txt, or a pyproject.toml with no uv.lock) are NOT warmed
# at image build and so are NOT verified here - a plugin using them installs
# online at runtime. Gems in that shape are reported below as UNVERIFIED so the
# gap is visible in the build log rather than silent. Closing it means teaching
# docker-package-build.sh to warm those paths too, then extending the loop here.
#
# Why this exists: the wheels a plugin needs are warmed in a throwaway build
# stage (docker-package-build.sh) and only reach the final image through an
# explicit `COPY --from=<stage> /openc3/uv_cache_plugins/`. Forgetting that COPY
# for a new Python plugin fails silently - the image builds, the deploy works on
# a networked cluster, and the breakage only shows up as a hang or a failed
# plugin install in an air-gapped one. Running the real offline install here
# turns that into a build failure instead.
#
# Usage: verify-uv-cache.sh [cache_dir] [gems_dir]
set -e

CACHE_DIR="${1:-/openc3/uv_cache}"
GEMS_DIR="${2:-/openc3/plugins/gems}"

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# uv needs a WRITABLE cache directory - it creates lock and marker files under
# UV_CACHE_DIR before it reads anything, and caches its interpreter probe there
# on a miss. The baked seed is root-owned and we run as the image user, so
# pointing UV_CACHE_DIR straight at it fails outright:
#   error: Failed to initialize cache
#     Caused by: failed to open file `.../sdists-v9/.git`: Permission denied
# That this ever worked was an accident of layering: the
# `COPY --from=<stage> --chown=... /openc3/uv_cache_plugins/ /openc3/uv_cache/`
# lines happened to re-own whichever subdirectories the plugin warm produced,
# and a build where the plugin cache stopped covering one of them broke it.
#
# So work against a writable copy, exactly as init.sh does at runtime
# (cp -ruf /openc3/uv_cache/. /gems/uv/). Same bytes, so the assertion is
# unchanged and --offline still proves the wheels came from the seed - it just
# no longer depends on which directories a COPY happened to chown. The copy
# lives in ${WORK} and is removed by the trap, so it adds no image layer.
RUN_CACHE="${WORK}/uv_cache"
mkdir -p "${RUN_CACHE}"
cp -a "${CACHE_DIR}/." "${RUN_CACHE}/"

CHECKED=0
UNVERIFIED=""
for GEM in "${GEMS_DIR}"/*.gem; do
    [ -f "${GEM}" ] || continue
    NAME=$(basename "${GEM}" .gem)
    DEST="${WORK}/${NAME}"
    mkdir -p "${DEST}"
    gem unpack "${GEM}" --target "${DEST}" > /dev/null
    SRC=$(find "${DEST}" -mindepth 1 -maxdepth 1 -type d | head -1)

    # Only plugins with both uv.lock and pyproject.toml take uvinstall's
    # reproducible path (see openc3/bin/uvinstall path 1), and that is the only
    # path docker-package-build.sh warms - so it is the only one with a cache to
    # assert against. A gem declaring Python dependencies some other way still
    # installs at runtime, just online, so call it out rather than dropping it
    # in with the plugins that have no Python dependencies at all.
    if [ -z "${SRC}" ] || [ ! -f "${SRC}/uv.lock" ] || [ ! -f "${SRC}/pyproject.toml" ]; then
        if [ -n "${SRC}" ] && { [ -f "${SRC}/requirements.txt" ] || [ -f "${SRC}/pyproject.toml" ]; }; then
            UNVERIFIED="${UNVERIFIED} ${NAME}"
        fi
        rm -rf "${DEST}"
        continue
    fi

    echo "--- verifying offline UV cache for ${NAME}"
    # --offline mirrors what uvinstall attempts first at runtime.
    # UV_PYTHON_DOWNLOADS=never keeps a requires-python mismatch from silently
    # reaching for a managed Python download instead of failing here.
    # --no-build matches docker-package-build.sh so no setup.py runs during the
    # image build, and asserts the cache holds real wheels rather than sdists
    # this step would have to build.
    # UV_COMPILE_BYTECODE=0 overrides the base image's UV_COMPILE_BYTECODE=1:
    # this step only asserts the wheels INSTALL offline from the cache, so
    # byte-compiling every module into a venv we are about to delete is pure
    # build time.
    if ! (cd "${SRC}" && UV_CACHE_DIR="${RUN_CACHE}" UV_PYTHON_DOWNLOADS=never \
            UV_COMPILE_BYTECODE=0 \
            uv sync --frozen --no-dev --no-install-project --offline --no-build); then
        {
            echo "ERROR: ${NAME} cannot install its Python dependencies from the baked UV cache."
            echo "       Add a 'COPY --from=<build stage> /openc3/uv_cache_plugins/ /openc3/uv_cache/'"
            echo "       for the stage that builds ${NAME} in openc3-cosmos-init/Dockerfile."
        } >&2
        exit 1
    fi
    CHECKED=$((CHECKED + 1))
    rm -rf "${DEST}"
done

if [ -n "${UNVERIFIED}" ]; then
    # Not a build failure: these plugins install fine on a networked cluster,
    # and failing here would break a build for a gap that predates this check.
    echo "WARNING: UNVERIFIED (no uv.lock - not warmed, will install online):${UNVERIFIED}" >&2
fi

# Verifying nothing is indistinguishable from verifying everything successfully,
# so treat it as a failure: it means GEMS_DIR moved, the gem glob stopped
# matching, or the last uv.lock plugin left the image. Every build ships at
# least openc3-cosmos-demo, which declares uv.lock + pyproject.toml.
if [ "${CHECKED}" -eq 0 ]; then
    {
        echo "ERROR: no plugin gem with uv.lock was verified - expected at least one."
        echo "       Checked ${GEMS_DIR}/*.gem; confirm that path still holds the shipped gems."
    } >&2
    exit 1
fi

echo "=== offline UV cache verified for ${CHECKED} plugin gem(s) taking uv sync --frozen"
