#!/bin/bash

set -e

usage() {
  echo "Usage: $1 [encode, hash, save, load, tag, push, clean, hostsetup]" >&2
  echo "*  encode: encode a string to base64" >&2
  echo "*  hash: hash a string using SHA-256" >&2
  echo "*  save: save images to a tar file" >&2
  echo "*  load: load images from a tar file" >&2
  echo "*  tag: tag images" >&2
  echo "*  push: push images" >&2
  echo "*  clean: remove node_modules, coverage, etc" >&2
  echo "*  hostsetup: configure host for redis" >&2
  exit 1
}

saveTar() {
  if [ "$#" -lt 3 ]; then
    echo "Usage: save <REPO> <NAMESPACE> <TAG>" >&2
    echo "e.g. save docker.io openc3inc 5.1.0" >&2
  fi
  repo=$1
  namespace=$2
  tag=$3
  mkdir -p tmp

  set -x
  docker pull $repo/$namespace/openc3-operator:$tag
  docker pull $repo/$namespace/openc3-cosmos-cmd-tlm-api:$tag
  docker pull $repo/$namespace/openc3-cosmos-script-runner-api:$tag
  docker pull $repo/$namespace/openc3-traefik:$tag
  docker pull $repo/$namespace/openc3-redis:$tag
  docker pull $repo/$namespace/openc3-minio:$tag
  docker pull $repo/$namespace/openc3-cosmos-init:$tag

  docker save $repo/$namespace/openc3-operator:$tag -o tmp/openc3-operator-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-cmd-tlm-api:$tag -o tmp/openc3-cosmos-cmd-tlm-api-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-script-runner-api:$tag -o tmp/openc3-cosmos-script-runner-api-$tag.tar
  docker save $repo/$namespace/openc3-traefik:$tag -o tmp/openc3-traefik-$tag.tar
  docker save $repo/$namespace/openc3-redis:$tag -o tmp/openc3-redis-$tag.tar
  docker save $repo/$namespace/openc3-minio:$tag -o tmp/openc3-minio-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-init:$tag -o tmp/openc3-cosmos-init-$tag.tar
  set +x
}

loadTar() {
  if [ -z "$1" ]; then
    tag="latest"
  else
    tag=$1
  fi
  set -x
  docker load -i tmp/openc3-operator-$tag.tar
  docker load -i tmp/openc3-cosmos-cmd-tlm-api-$tag.tar
  docker load -i tmp/openc3-cosmos-script-runner-api-$tag.tar
  docker load -i tmp/openc3-traefik-$tag.tar
  docker load -i tmp/openc3-redis-$tag.tar
  docker load -i tmp/openc3-minio-$tag.tar
  docker load -i tmp/openc3-cosmos-init-$tag.tar
  set +x
}

tag() {
  if [ "$#" -lt 4 ]; then
    echo "Usage: tag <REPO1> <REPO2> <NAMESPACE1> <TAG1> <NAMESPACE2> <TAG2>" >&2
    echo "e.g. tag docker.io localhost:12345 openc3 latest" >&2
    echo "Note: NAMESPACE2 and TAG2 default to NAMESPACE1 and TAG1 if not given" >&2
    exit 1
  fi

  repo1=$1
  repo2=$2
  namespace1=$3
  tag1=$4
  namespace2=$namespace1
  if [[ -n "$5" ]]; then
    namespace2=$5
  fi
  tag2=$tag1
  if [[ -n "$6" ]]; then
    tag2=$6
  fi

  set -x
  docker tag $repo1/$namespace1/openc3-operator:$tag1 $repo2/$namespace2/openc3-operator:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-cmd-tlm-api:$tag1 $repo2/$namespace2/openc3-cosmos-cmd-tlm-api:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-script-runner-api:$tag1 $repo2/$namespace2/openc3-cosmos-script-runner-api:$tag2
  docker tag $repo1/$namespace1/openc3-traefik:$tag1 $repo2/$namespace2/openc3-traefik:$tag2
  docker tag $repo1/$namespace1/openc3-redis:$tag1 $repo2/$namespace2/openc3-redis:$tag2
  docker tag $repo1/$namespace1/openc3-minio:$tag1 $repo2/$namespace2/openc3-minio:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-init:$tag1 $repo2/$namespace2/openc3-cosmos-init:$tag2
  set +x
}

push() {
  if [ "$#" -ne 3 ]; then
    echo "Usage: push <REPO> <NAMESPACE> <TAG>" >&2
    echo "e.g. push localhost:12345 openc3 latest" >&2
    exit 1
  fi
  repo=$1
  namespace=$2
  tag=$3

  set -x
  docker push $repo/$namespace/openc3-operator:$tag
  docker push $repo/$namespace/openc3-cosmos-cmd-tlm-api:$tag
  docker push $repo/$namespace/openc3-cosmos-script-runner-api:$tag
  docker push $repo/$namespace/openc3-traefik:$tag
  docker push $repo/$namespace/openc3-redis:$tag
  docker push $repo/$namespace/openc3-minio:$tag
  docker push $repo/$namespace/openc3-cosmos-init:$tag
  set +x
}

cleanFiles() {
  find . -type d -name "node_modules" | xargs -I {} echo "Removing {}"; rm -rf {}
  find . -type d -name "coverage" | xargs -I {} echo "Removing {}"; rm -rf {}
  # Prompt for removing yarn.lock files
  find . -type f -name "yarn.lock" | xargs -I {} rm -i {}
  # Prompt for removing Gemfile.lock files
  find . -type f -name "Gemfile.lock" | xargs -I {} rm -i {}
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

case $1 in
  encode )
    echo -n $2 | base64
    ;;
  hash )
    echo -n $2 | shasum -a 256 | sed 's/-//'
    ;;
  save )
    saveTar "${@:2}"
    ;;
  load )
    loadTar "${@:2}"
    ;;
  tag )
    tag "${@:2}"
    ;;
  push )
    push "${@:2}"
    ;;
  clean )
    cleanFiles
    ;;
  hostsetup )
    if [ "$#" -ne 4 ]; then
      echo "Usage: hostsetup <REPO> <NAMESPACE> <TAG>" >&2
      echo "e.g. hostsetup docker.io openc3inc latest" >&2
      exit 1
    fi
    repo=$2
    namespace=$3
    tag=$4
    docker run --rm --privileged --pid=host --entrypoint='' --user root $repo/$namespace/openc3-operator:$tag nsenter -t 1 -m -u -n -i -- sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
    docker run --rm --privileged --pid=host --entrypoint='' --user root $repo/$namespace/openc3-operator:$tag nsenter -t 1 -m -u -n -i -- sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
    docker run --rm --privileged --pid=host --entrypoint='' --user root $repo/$namespace/openc3-operator:$tag nsenter -t 1 -m -u -n -i -- sh -c "sysctl -w vm.max_map_count=262144"
    ;;
  * )
    usage $0
    ;;
esac
