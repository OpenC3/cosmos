#!/bin/sh
set -e

PLUGINS="/openc3/plugins"
GEMS="/openc3/plugins/gems/"
PACKAGES="packages"
OPENC3_RELEASE_VERSION=6.5.2-beta0

# 2nd argument provides an override for the workspace name,
# but that can be inferred from the 1st argument for most tools
WORKSPACE_NAME=$2
if [ -z "${WORKSPACE_NAME}" ]; then # if WORKSPACE_NAME is unset or empty string
  # "openc3-cosmos-tool-admin" -> "@openc3/cosmos-tool-admin"
  WORKSPACE_NAME=$(echo $1 | sed -e '1s/\-/\//' | awk '{print "@"$0}')
fi

mkdir -p ${GEMS}

echo "<<< packageBuild $1"
cd ${PLUGINS}/
cd ${PACKAGES}/${1}/
echo "--- packageBuild $1 npm run build"
npm run build
echo "=== packageBuild $1 npm run build complete"
echo "--- packageBuild $1 rake build"
rake build VERSION=${OPENC3_RELEASE_VERSION}
echo "=== packageBuild $1 rake build complete"
ls *.gem
echo "--- packageInstall $1 mv gem file"
mv ${1}-*.gem ${GEMS}
echo "=== packageInstall $1 mv gem complete"
