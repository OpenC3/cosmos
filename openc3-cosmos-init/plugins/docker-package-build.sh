#!/bin/sh
set -e

PLUGINS="/openc3/plugins"
GEMS="/openc3/plugins/gems/"
PACKAGES="packages"
OPENC3_RELEASE_VERSION=6.9.1-beta0

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
