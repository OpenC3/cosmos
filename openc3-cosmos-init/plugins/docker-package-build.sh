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
# Plugin wheels are warmed into their OWN directory, not /openc3/uv_cache. The
# docs stage (openc3-tmp5) copies all of /openc3 in from openc3-base, so it
# already has base's /openc3/uv_cache; warming into that same path would make
# the Dockerfile's COPY duplicate the entire base cache into the final image.
# A dedicated dir keeps every stage's contribution to just its own plugins,
# which is what lets the Dockerfile COPY unconditionally from all stages.
# Created unconditionally so that COPY succeeds even for a stage whose plugins
# have no Python dependencies.
UV_CACHE_PLUGINS=/openc3/uv_cache_plugins
mkdir -p ${UV_CACHE_PLUGINS}

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
#
# --no-build forbids building source distributions, so no third-party setup.py
# runs during the image build. This script only ever handles first-party plugins
# (the Dockerfile invokes it with hardcoded package names), and every Python
# dependency they declare today publishes wheels. If a future first-party plugin
# genuinely needs an sdist, drop --no-build here AND in verify-uv-cache.sh and
# document why. Runtime plugin installs (uvinstall) intentionally stay
# permissive - user plugins are allowed to depend on sdist-only packages.
if [ -f uv.lock ] && [ -f pyproject.toml ]; then
  echo "--- packageBuild $1 warm UV cache (uv sync --frozen)"
  UV_CACHE_DIR=${UV_CACHE_PLUGINS} uv sync --frozen --no-dev --no-install-project --no-build
  echo "=== packageBuild $1 warm UV cache complete"
fi
