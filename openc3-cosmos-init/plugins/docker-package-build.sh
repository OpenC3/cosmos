#!/bin/sh
set -e

PLUGINS="/openc3/plugins"
GEMS="/openc3/plugins/gems/"
PACKAGES="packages"
OPENC3_RELEASE_VERSION=7.2.2-beta0

# 2nd argument provides an override for the build folder
FOLDER_NAME=$2
if [ -z "${FOLDER_NAME}" ]; then # if WORKSPACE_NAME is unset or empty string
  # "openc3-cosmos-tool-admin" -> "@openc3/cosmos-tool-admin"
  FOLDER_NAME=${PLUGINS}/${PACKAGES}/${1}/
fi

mkdir -p ${GEMS}

echo "<<< packageBuild $1"
cd ${FOLDER_NAME}
echo "--- packageBuild $1 pnpm run build"
pnpm run build
echo "=== packageBuild $1 pnpm run build complete"
echo "--- packageBuild $1 rake build"
rake build VERSION=${OPENC3_RELEASE_VERSION}
echo "=== packageBuild $1 rake build complete"
ls *.gem
echo "--- packageInstall $1 mv gem file"
mv ${1}-*.gem ${GEMS}
echo "=== packageInstall $1 mv gem complete"

# Pre-warm the shared UV wheel cache with this plugin's locked Python
# dependencies (cwd is still FOLDER_NAME from the cd above). Without this the
# runtime per-plugin venv install (uvinstall) must fetch the plugin's exact
# locked wheels from PyPI, because the image only seeds core's own dependency
# versions - a guaranteed cache miss for any plugin pinning a different version
# (e.g. demo numpy 2.4.6 vs core 2.2.6). Seeding here makes the runtime install
# an offline cache hit: fast, deterministic, and works in air-gapped clusters.
if command -v uv > /dev/null 2>&1 && [ -f uv.lock ] && [ -f pyproject.toml ]; then
  echo "--- packageBuild $1 warm UV cache (uv sync --frozen)"
  UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev --no-install-project \
    || echo "Warning: UV cache warm failed for $1 - runtime install will fall back to network"
  echo "=== packageBuild $1 warm UV cache complete"
fi
