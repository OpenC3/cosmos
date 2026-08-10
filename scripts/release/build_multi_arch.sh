#!/bin/bash

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
# Load .env as DEFAULTS only. Variables already set in the environment (e.g. by
# the GitHub Actions release workflow) win, so CI can point OPENC3_ENTERPRISE_REGISTRY
# at ghcr.io even though .env defaults it to repos.openc3.com.
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  printf -v "$key" '%s' "${!key:-$value}"
  export "$key"
done < .env
# OPENC3_REGISTRY=localhost:5000 # Uncomment for local builds
# OPENC3_ENTERPRISE_REGISTRY=localhost:5000 # Uncomment for local builds

# Registries intermittently fail the push with transient auth or network errors,
# e.g. "failed to authorize: failed to fetch oauth token: denied: denied" from
# ghcr.io. buildx has no built in retry, so a single hiccup kills an otherwise
# good release partway through and every remaining image has to be rebuilt.
# Wrap the build so each one gets a few attempts with exponential backoff.
# Retries are cheap: the layers are already cached, only the push repeats.
OPENC3_BUILD_ATTEMPTS=${OPENC3_BUILD_ATTEMPTS:-3}
OPENC3_BUILD_RETRY_DELAY=${OPENC3_BUILD_RETRY_DELAY:-15}
retry_build() {
  local attempt=1
  local delay=$OPENC3_BUILD_RETRY_DELAY
  while true; do
    if docker buildx build "$@"; then
      return 0
    fi
    if [[ $attempt -ge $OPENC3_BUILD_ATTEMPTS ]]; then
      echo "ERROR: docker buildx build failed after ${attempt} attempts" 1>&2
      return 1
    fi
    echo "WARNING: docker buildx build attempt ${attempt} failed, retrying in ${delay}s" 1>&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

# check if the first parameter is 'ubi'
if [[ "${1:-default}" == "ubi" ]]; then
  OPENC3_PLATFORMS=linux/amd64
  DOCKERFILE='Dockerfile-ubi'
  SUFFIX='-ubi'
  OPENC3_VERSITYGW_VERSION=v1.7.0
else
  OPENC3_PLATFORMS=linux/amd64,linux/arm64
  DOCKERFILE='Dockerfile'
  SUFFIX=''
  OPENC3_VERSITYGW_VERSION=v1.7.0
fi

# Setup cacert.pem
echo "Downloading cert from curl"
curl -q -L https://curl.se/ca/cacert.pem --output ./cacert.pem
if [[ $? -ne 0 ]]; then
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
cp ./cacert.pem openc3-buckets/cacert.pem

cd openc3-ruby
retry_build \
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

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-ruby${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-base${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
retry_build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg NPM_URL=$NPM_URL \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-node${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
cd ../openc3-redis
if [[ "${1:-default}" == "ubi" ]]; then
  # UBI build uses Dockerfile-ubi which builds Valkey from source
  retry_build \
    --file Dockerfile-ubi \
    --platform ${OPENC3_PLATFORMS} \
    --progress plain \
    --build-arg OPENC3_UBI_REGISTRY=${OPENC3_UBI_REGISTRY} \
    --build-arg OPENC3_UBI_IMAGE=${OPENC3_UBI_IMAGE} \
    --build-arg OPENC3_UBI_TAG=${OPENC3_UBI_TAG} \
    --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} \
    --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} .

  if [[ $OPENC3_UPDATE_LATEST == true ]]
  then
  retry_build \
    --file Dockerfile-ubi \
    --platform ${OPENC3_PLATFORMS} \
    --progress plain \
    --build-arg OPENC3_UBI_REGISTRY=${OPENC3_UBI_REGISTRY} \
    --build-arg OPENC3_UBI_IMAGE=${OPENC3_UBI_IMAGE} \
    --build-arg OPENC3_UBI_TAG=${OPENC3_UBI_TAG} \
    --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:latest \
    --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:latest .
  fi
else
  # Standard build uses Valkey alpine image
  # OPENC3_REDIS_IMAGE and OPENC3_REDIS_VERSION default in the Dockerfile
  retry_build \
    --platform ${OPENC3_PLATFORMS} \
    --progress plain \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
    --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} \
    --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:${OPENC3_RELEASE_VERSION} .

  if [[ $OPENC3_UPDATE_LATEST == true ]]
  then
  retry_build \
    --platform ${OPENC3_PLATFORMS} \
    --progress plain \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
    --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis${SUFFIX}:latest \
    --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-redis${SUFFIX}:latest .
  fi
fi

if [[ "${1:-default}" == "ubi" ]]; then
  OPENC3_TSDB_VERSION_EXT="-rhel"
else
  OPENC3_TSDB_VERSION_EXT=""
fi
cd ../openc3-tsdb
retry_build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_TSDB_VERSION_EXT=$OPENC3_TSDB_VERSION_EXT \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-tsdb${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-tsdb${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_TSDB_VERSION_EXT=$OPENC3_TSDB_VERSION_EXT \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-tsdb${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-tsdb${SUFFIX}:latest .
fi

cd ../openc3-buckets
retry_build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_VERSITYGW_VERSION=${OPENC3_VERSITYGW_VERSION} \
  --build-arg OPENC3_UBI_REGISTRY=${OPENC3_UBI_REGISTRY} \
  --build-arg OPENC3_UBI_IMAGE=${OPENC3_UBI_IMAGE} \
  --build-arg OPENC3_UBI_TAG=${OPENC3_UBI_TAG} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-buckets${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-buckets${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
  --file ${DOCKERFILE} \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_VERSITYGW_VERSION=${OPENC3_VERSITYGW_VERSION} \
  --build-arg OPENC3_UBI_REGISTRY=${OPENC3_UBI_REGISTRY} \
  --build-arg OPENC3_UBI_IMAGE=${OPENC3_UBI_IMAGE} \
  --build-arg OPENC3_UBI_TAG=${OPENC3_UBI_TAG} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-buckets${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-buckets${SUFFIX}:latest .
fi

cd ../openc3-cosmos-cmd-tlm-api
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-cmd-tlm-api${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-script-runner-api${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_IMAGE=openc3-base${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-operator${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
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
if [[ "${1:-default}" == "ubi" ]]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/traefik
  OPENC3_TRAEFIK_RELEASE=v3.7.10
else
  OPENC3_TRAEFIK_RELEASE=v3.7.10
fi
cd ../openc3-traefik
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_TRAEFIK_RELEASE=${OPENC3_TRAEFIK_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-traefik${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_TRAEFIK_RELEASE=${OPENC3_TRAEFIK_RELEASE} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-traefik${SUFFIX}:latest .
fi

if [[ "${1:-default}" == "ubi" ]]; then
  OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource
fi
cd ../openc3-cosmos-init
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=${NPM_URL} \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_BASE_IMAGE=openc3-base${SUFFIX} \
  --build-arg OPENC3_NODE_IMAGE=openc3-node${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init${SUFFIX}:${OPENC3_RELEASE_VERSION} \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-init${SUFFIX}:${OPENC3_RELEASE_VERSION} .

if [[ $OPENC3_UPDATE_LATEST == true ]]
then
retry_build \
  --platform ${OPENC3_PLATFORMS} \
  --progress plain \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=${NPM_URL} \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_DEPENDENCY_REGISTRY} \
  --build-arg OPENC3_REGISTRY=${OPENC3_REGISTRY} \
  --build-arg OPENC3_NAMESPACE=${OPENC3_NAMESPACE} \
  --build-arg OPENC3_TAG=${OPENC3_RELEASE_VERSION} \
  --build-arg OPENC3_BASE_IMAGE=openc3-base${SUFFIX} \
  --build-arg OPENC3_NODE_IMAGE=openc3-node${SUFFIX} \
  --push -t ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init${SUFFIX}:latest \
  --push -t ${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-cosmos-init${SUFFIX}:latest .
fi
