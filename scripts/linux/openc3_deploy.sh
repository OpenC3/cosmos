#!/bin/bash

# exit when any command fails
set -e

usage() {
  echo "Usage: $1 [repository] [namespace] [tag]" >&2
  echo "*  repository: hostname of the docker repository" >&2
  echo "*  namespace: defaults to 'openc3inc'" >&2
  echo "*  tag: defaults to 'latest'" >&2
  echo "Initial namespace pulled from .env file's OPENC3_NAMESPACE var" >&2
  echo "  For example: docker tag ${OPENC3_NAMESPACE}/openc3-ruby" >&2
  echo "If the push doesn't work ensure you're authenticated" >&2
  echo "  For example with ghcr.io:" >&2
  echo "    docker login ghcr.io -u jmthomas" >&2
  echo "  Paste in the access token as the password, looks like ghp_XXX"
  echo "NOTE: If it doesn't complete just re-run, sometimes the pushes fail"
  exit 1
}
if [ "$#" -eq 0 ]; then
  usage $0
fi

namespace='openc3inc'
if [[ -n "$2" ]]; then
  namespace=${2}
fi
tag='latest'
if [[ -n "$3" ]]; then
  tag=${3}
fi

# Tag and push all the images to the local repository
docker tag $OPENC3_NAMESPACE/openc3-ruby ${1}/${namespace}/openc3-ruby:${tag}
docker tag $OPENC3_NAMESPACE/openc3-node ${1}/${namespace}/openc3-node:${tag}
docker tag $OPENC3_NAMESPACE/openc3-base ${1}/${namespace}/openc3-base:${tag}
docker tag $OPENC3_NAMESPACE/openc3-cmd-tlm-api ${1}/${namespace}/openc3-cmd-tlm-api:${tag}
docker tag $OPENC3_NAMESPACE/openc3-script-runner-api ${1}/${namespace}/openc3-script-runner-api:${tag}
docker tag $OPENC3_NAMESPACE/openc3-operator ${1}/${namespace}/openc3-operator:${tag}
docker tag $OPENC3_NAMESPACE/openc3-init ${1}/${namespace}/openc3-init:${tag}
docker tag $OPENC3_NAMESPACE/openc3-redis ${1}/${namespace}/openc3-redis:${tag}
docker tag $OPENC3_NAMESPACE/openc3-minio ${1}/${namespace}/openc3-minio:${tag}
docker tag $OPENC3_NAMESPACE/openc3-traefik ${1}/${namespace}/openc3-traefik:${tag}

docker push ${1}/${namespace}/openc3-ruby:${tag}
docker push ${1}/${namespace}/openc3-node:${tag}
docker push ${1}/${namespace}/openc3-base:${tag}
docker push ${1}/${namespace}/openc3-cmd-tlm-api:${tag}
docker push ${1}/${namespace}/openc3-script-runner-api:${tag}
docker push ${1}/${namespace}/openc3-operator:${tag}
docker push ${1}/${namespace}/openc3-init:${tag}
docker push ${1}/${namespace}/openc3-redis:${tag}
docker push ${1}/${namespace}/openc3-minio:${tag}
docker push ${1}/${namespace}/openc3-traefik:${tag}
