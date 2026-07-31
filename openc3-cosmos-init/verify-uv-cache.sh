#!/bin/sh
# Build-time assertion: every plugin gem shipped in this image must be able to
# install its Python dependencies from the baked UV cache with NO network.
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

CHECKED=0
for GEM in "${GEMS_DIR}"/*.gem; do
    [ -f "${GEM}" ] || continue
    NAME=$(basename "${GEM}" .gem)
    DEST="${WORK}/${NAME}"
    mkdir -p "${DEST}"
    gem unpack "${GEM}" --target "${DEST}" > /dev/null
    SRC=$(find "${DEST}" -mindepth 1 -maxdepth 1 -type d | head -1)

    # Only plugins with a uv.lock take uvinstall's reproducible path (see
    # openc3/bin/uvinstall path 1); everything else has nothing to verify.
    if [ -z "${SRC}" ] || [ ! -f "${SRC}/uv.lock" ] || [ ! -f "${SRC}/pyproject.toml" ]; then
        rm -rf "${DEST}"
        continue
    fi

    echo "--- verifying offline UV cache for ${NAME}"
    # --offline mirrors what uvinstall attempts first at runtime.
    # UV_PYTHON_DOWNLOADS=never keeps a requires-python mismatch from silently
    # reaching for a managed Python download instead of failing here.
    if ! (cd "${SRC}" && UV_CACHE_DIR="${CACHE_DIR}" UV_PYTHON_DOWNLOADS=never \
            uv sync --frozen --no-dev --no-install-project --offline); then
        echo "ERROR: ${NAME} cannot install its Python dependencies from the baked UV cache."
        echo "       Add a 'COPY --from=<build stage> /openc3/uv_cache_plugins/ /openc3/uv_cache/'"
        echo "       for the stage that builds ${NAME} in openc3-cosmos-init/Dockerfile."
        exit 1
    fi
    CHECKED=$((CHECKED + 1))
    rm -rf "${DEST}"
done

echo "=== offline UV cache verified for ${CHECKED} plugin gem(s)"
