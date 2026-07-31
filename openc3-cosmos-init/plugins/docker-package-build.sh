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
# Always exists so the Dockerfile's `COPY --from=<stage> /openc3/uv_cache/`
# succeeds even for a stage whose plugins have no Python dependencies.
mkdir -p /openc3/uv_cache

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
#
# uv is provided by the openc3-ruby base image (which openc3-node, and therefore
# every plugin build stage, derives from), so it is not checked for here - a
# missing uv or a failed sync means the offline guarantee is silently broken, so
# let set -e fail the build loudly instead of warning and moving on.
if [ -f uv.lock ] && [ -f pyproject.toml ]; then
  echo "--- packageBuild $1 warm UV cache (uv sync --frozen)"
  UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev --no-install-project
  echo "=== packageBuild $1 warm UV cache complete"
fi
