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

# Handle restrictive umasks - Built files need to be world readable
umask 0022
chmod -R +r .

# openc3-ruby
cd openc3-ruby
docker build \
  -f Dockerfile-ubi \
  --network host \
  --build-arg OPENC3_UBI_REGISTRY=$OPENC3_UBI_REGISTRY \
  --build-arg OPENC3_UBI_IMAGE=$OPENC3_UBI_IMAGE \
  --build-arg OPENC3_UBI_TAG=$OPENC3_UBI_TAG \
  --build-arg RUBYGEMS_URL=$RUBYGEMS_URL \
  --build-arg PYPI_URL=$PYPI_URL \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-base
cd openc3
docker build \
  -f Dockerfile-ubi \
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
  --build-arg NPM_URL=$NPM_URL \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-minio
# NOTE: Ensure the release is on IronBank:
# https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Fminio%252Fminio
# NOTE: RELEASE.2023-10-16T04-13-43Z is the last MINIO release to support UBI8
cd openc3-minio
docker build \
  --network host \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
  --build-arg OPENC3_MINIO_RELEASE=RELEASE.2025-04-03T14-56-28Z \
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
  --build-arg OPENC3_REDIS_VERSION="7.2.5" \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-cosmos-cmd-tlm-api
cd openc3-cosmos-cmd-tlm-api
docker build \
  -f Dockerfile-ubi \
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
  -f Dockerfile-ubi \
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
if [[ -z $TRAEFIK_CONFIG ]]; then
  export TRAEFIK_CONFIG=traefik.yaml
fi
# NOTE: Ensure OPENC3_TRAEFIK_RELEASE is on IronBank:
# https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Ftraefik%252Ftraefik
cd openc3-traefik
docker build \
  --network host \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/traefik \
  --build-arg TRAEFIK_CONFIG=$TRAEFIK_CONFIG \
  --build-arg OPENC3_TRAEFIK_RELEASE=v3.3.5 \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik-ubi:${OPENC3_TAG}" \
  .
cd ..

# openc3-cosmos-init
# NOTE: Ensure OPENC3_MC_RELEASE is on IronBank:
# https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Fminio%252Fmc
# NOTE: RELEASE.2023-10-14T01-57-03Z is the last MINIO/MC release to support UBI8
cd openc3-cosmos-init
docker build \
  --network host \
  --build-context docs=../docs.openc3.com \
  --build-arg NPM_URL=$NPM_URL \
  --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
  --build-arg OPENC3_MC_RELEASE=RELEASE.2025-01-17T23-25-50Z \
  --build-arg OPENC3_BASE_IMAGE=openc3-base-ubi \
  --build-arg OPENC3_NODE_IMAGE=openc3-node-ubi \
  --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
  --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
  --build-arg OPENC3_TAG=$OPENC3_TAG \
  --platform linux/amd64 \
  -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init-ubi:${OPENC3_TAG}" \
  .
cd ..
