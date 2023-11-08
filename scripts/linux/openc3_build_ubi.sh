#!/bin/bash

set -e

if ! command -v docker &> /dev/null
then
  if command -v podman &> /dev/null
  then
    function docker() {
      podman $@
    }
  else
    echo "Neither docker nor podman found!!!"
    exit 1
  fi
fi

# openc3-ruby
cd openc3-ruby
curl -G https://cache.ruby-lang.org/pub/ruby/3.2/ruby-3.2.2.tar.gz > ruby-3.2.tar.gz
if command -v shasum &> /dev/null
then
  echo '96c57558871a6748de5bc9f274e93f4b5aad06cd8f37befa0e8d94e7b8a423bc  ruby-3.2.tar.gz' | shasum -a 256 -c
fi

docker build \
  -f Dockerfile-ubi \
  --network host \
  --build-arg OPENC3_UBI_REGISTRY=$OPENC3_UBI_REGISTRY \
  --build-arg OPENC3_UBI_IMAGE=$OPENC3_UBI_IMAGE \
  --build-arg OPENC3_UBI_TAG=$OPENC3_UBI_TAG \
  --build-arg RUBYGEMS_URL=$RUBYGEMS_URL \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-base
cd openc3
docker build \
  --network host \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --build-arg OPENC3_IMAGE=openc3-ruby-ubi \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-node
cd openc3-node
docker build \
  -f Dockerfile-ubi \
  --network host \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-minio
cd openc3-minio
docker build \
  --network host \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-minio-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-redis
cd openc3-redis
docker build \
  --network host \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/redis \
  --build-arg OPENC3_REDIS_IMAGE=redis7 \
  --build-arg OPENC3_REDIS_VERSION="7.2.3" \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-cosmos-cmd-tlm-api
cd openc3-cosmos-cmd-tlm-api
docker build \
  --network host \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --build-arg OPENC3_IMAGE=openc3-base-ubi \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-cmd-tlm-api-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-cosmos-script-runner-api
cd openc3-cosmos-script-runner-api
docker build \
  --network host \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --build-arg OPENC3_IMAGE=openc3-base-ubi \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-script-runner-api-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-operator
cd openc3-operator
docker build \
  --network host \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --build-arg OPENC3_IMAGE=openc3-base-ubi \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-traefik
cd openc3-traefik
docker build \
  --network host \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/traefik \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-cosmos-init
cd openc3-cosmos-init
docker build \
  --network host \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=$NPM_URL \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
  --build-arg OPENC3_BASE_IMAGE=openc3-base-ubi \
  --build-arg OPENC3_NODE_IMAGE=openc3-node-ubi \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init-ubi:${OPENC3_TAG}" \
  .
cd ..
