#!/bin/sh

# TODO: Can this script be replaced by https://github.com/docker/build-push-action

# From this directory, to locally build x86 from an ARM machine (Mac Apple Silicon):
#   Uncomment OPENC3_REGISTRY and OPENC3_ENTERPRISE_REGISTRY lines
# Start the local registry. Note MacOS reserves port 5000 for Airdrop receiver.
# Search for Airdrop in System Prefs and disable Airdrop Receiver, then:
#   % docker run -d -p 5000:5000 --restart=always --name registry registry:2
# Ensure the ENV vars are correct. You probably want defaults:
#   docker.io/openc3inc/<image>:latest
# Export the ENV vars:
#   % export $(grep -v '^#' .env | xargs)
# Create the other necessary ENV vars:
#   % export OPENC3_UPDATE_LATEST=false
# Create the tag version which will be pushed. Something other than latest!!!
#   % export OPENC3_RELEASE_VERSION=gcp
# Create the env and perform the build
#   % docker buildx create --use --name openc3-builder2 --driver-opt network=host
#   % ./build_multi_arch.sh

set -eux
cd ../..
eval $(sed -e '/^#/d' -e 's/^/export /' -e 's/$/;/' .env) ;
# OPENC3_REGISTRY=localhost:5000 # Uncomment for local builds
# OPENC3_ENTERPRISE_REGISTRY=localhost:5000 # Uncomment for local builds

# check if the first parameter is 'ubi'
if [ "${1:-default}" = "ubi" ]; then
  OPENC3_PLATFORMS=linux/amd64
  DOCKERFILE='Dockerfile-ubi'
  SUFFIX='-ubi'
  OPENC3_MINIO_RELEASE=RELEASE.2025-10-15T17-29-55Z
  OPENC3_MC_RELEASE=RELEASE.2025-08-13T08-35-41Z
else
  OPENC3_PLATFORMS=linux/amd64,linux/arm64
  DOCKERFILE='Dockerfile'
  SUFFIX=''
  OPENC3_MINIO_RELEASE=RELEASE.2025-10-15T17-29-55Z
  OPENC3_MC_RELEASE=RELEASE.2025-08-13T08-35-41Z
fi

# Setup cacert.pem
echo "Downloading cert from curl"
curl -q -L https://curl.se/ca/cacert.pem --output ./cacert.pem
if [ $? -ne 0 ]; then
  echo "ERROR: Problem downloading cacert.pem file from https://curl.se/ca/cacert.pem" 1>&2
  echo "openc3_setup FAILED" 1>&2
  exit 1
else
  echo "Successfully downloaded ./cacert.pem file from: https://curl.se/ca/cacert.pem"
fi

cp ./cacert.pem openc3-ruby/cacert.pem
cp ./cacert.pem openc3-redis/cacert.pem
cp ./cacert.pem openc3-tsdb/cacert.pem
cp ./cacert.pem openc3-traefik/cacert.pem
cp ./cacert.pem openc3-minio/cacert.pem

cd openc3-ruby
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg ALPINE_VERSION=${ALPINE_VERSION} \
  --build-arg ALPINE_BUILD=${ALPINE_BUILD} \
  --build-arg APK_URL=${APK_URL} \
  --build-arg RUBYGEMS_URL=${RUBYGEMS_URL} \
  --build-arg PYPI_URL=$PYPI_URL \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_UBI_REGISTRY=$OPENC3_UBI_REGISTRY \
  --build-arg OPENC3_UBI_IMAGE=$OPENC3_UBI_IMAGE \
  --build-arg OPENC3_UBI_TAG=$OPENC3_UBI_TAG \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-ruby${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg ALPINE_VERSION=${ALPINE_VERSION} \
  --build-arg ALPINE_BUILD=${ALPINE_BUILD} \
  --build-arg APK_URL=${APK_URL} \
  --build-arg RUBYGEMS_URL=${RUBYGEMS_URL} \
  --build-arg PYPI_URL=$PYPI_URL \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_UBI_REGISTRY=$OPENC3_UBI_REGISTRY \
  --build-arg OPENC3_UBI_IMAGE=$OPENC3_UBI_IMAGE \
  --build-arg OPENC3_UBI_TAG=$OPENC3_UBI_TAG \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-ruby${SUFFIX}:latest .
fi

cd ../openc3
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-ruby${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-base${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-ruby${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-base${SUFFIX}:latest .
fi

cd ../openc3-node
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg NPM_URL=$NPM_URL \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-node${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg NPM_URL=$NPM_URL \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-node${SUFFIX}:latest .
fi

# Note: Missing OPENC3_REGISTRY build-arg intentionally to default to docker.io
if [ "${1:-default}" = "ubi" ]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/redis
  OPENC3_REDIS_IMAGE=redis7
  OPENC3_REDIS_VERSION=7.2.5
else
  OPENC3_REDIS_IMAGE=redis
  OPENC3_REDIS_VERSION=7.2-alpine
fi
cd ../openc3-redis
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_REDIS_IMAGE=${OPENC3_REDIS_IMAGE} \
  --build-arg OPENC3_REDIS_VERSION=${OPENC3_REDIS_VERSION} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_REDIS_IMAGE=${OPENC3_REDIS_IMAGE} \
  --build-arg OPENC3_REDIS_VERSION=${OPENC3_REDIS_VERSION} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:latest .
fi

if [ "${1:-default}" = "ubi" ]; then
  OPENC3_TSDB_VERSION_EXT="-rhel"
else
  OPENC3_TSDB_VERSION_EXT=""
fi
cd ../openc3-tsdb
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_TSDB_VERSION_EXT=$OPENC3_TSDB_VERSION_EXT \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-tsdb${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-tsdb${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_TSDB_VERSION_EXT=$OPENC3_TSDB_VERSION_EXT \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-tsdb${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-tsdb${SUFFIX}:latest .
fi

if [ "${1:-default}" = "ubi" ]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource
fi
cd ../openc3-minio
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_MINIO_RELEASE=${OPENC3_MINIO_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-minio${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-minio${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_MINIO_RELEASE=${OPENC3_MINIO_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-minio${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-minio${SUFFIX}:latest .
fi

cd ../openc3-cosmos-cmd-tlm-api
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:latest .
fi

cd ../openc3-cosmos-script-runner-api
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:latest .
fi

cd ../openc3-operator
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-operator${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-operator${SUFFIX}:latest .
fi

# Note: Missing OPENC3_REGISTRY build-arg intentionally to default to docker.io
if [ "${1:-default}" = "ubi" ]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/traefik
  OPENC3_TRAEFIK_RELEASE=v3.5.4
else
  OPENC3_TRAEFIK_RELEASE=v3.5.4
fi
cd ../openc3-traefik
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_TRAEFIK_RELEASE=${OPENC3_TRAEFIK_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-traefik${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_TRAEFIK_RELEASE=${OPENC3_TRAEFIK_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-traefik${SUFFIX}:latest .
fi

if [ "${1:-default}" = "ubi" ]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource
fi
cd ../openc3-cosmos-init
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=${NPM_URL} \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_MC_RELEASE=${OPENC3_MC_RELEASE} \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_BASE_IMAGE=openc3-base${SUFFIX} \
  --build-arg OPENC3_NODE_IMAGE=openc3-node${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-init${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [ $OPENC3_UPDATE_LATEST = true ]
then
docker buildx build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=${NPM_URL} \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_MC_RELEASE=${OPENC3_MC_RELEASE} \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_BASE_IMAGE=openc3-base${SUFFIX} \
  --build-arg OPENC3_NODE_IMAGE=openc3-node${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-init${SUFFIX}:latest .
fi
