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
  echo "*  hostenter: sh into vm host" >&2
  exit 1
}

saveTar() {
  if [ "$#" -lt 3 ]; then
    echo "Usage: save <REPO> <NAMESPACE> <TAG> <SUFFIX>" >&2
    echo "e.g. save docker.io openc3inc 5.1.0" >&2
  fi
  repo=$1
  namespace=$2
  tag=$3
  suffix=""
  if [[ -n "$4" ]]; then
    suffix=$4
  fi
  mkdir -p tmp

  set -x
  docker pull $repo/$namespace/openc3-ruby$suffix:$tag
  docker pull $repo/$namespace/openc3-node$suffix:$tag
  docker pull $repo/$namespace/openc3-base$suffix:$tag
  docker pull $repo/$namespace/openc3-operator$suffix:$tag
  docker pull $repo/$namespace/openc3-cosmos-cmd-tlm-api$suffix:$tag
  docker pull $repo/$namespace/openc3-cosmos-script-runner-api$suffix:$tag
  docker pull $repo/$namespace/openc3-traefik$suffix:$tag
  docker pull $repo/$namespace/openc3-redis$suffix:$tag
  docker pull $repo/$namespace/openc3-tsdb$suffix:$tag
  docker pull $repo/$namespace/openc3-minio$suffix:$tag
  docker pull $repo/$namespace/openc3-cosmos-init$suffix:$tag

  docker save $repo/$namespace/openc3-ruby$suffix:$tag -o tmp/openc3-ruby$suffix-$tag.tar
  docker save $repo/$namespace/openc3-node$suffix:$tag -o tmp/openc3-node$suffix-$tag.tar
  docker save $repo/$namespace/openc3-base$suffix:$tag -o tmp/openc3-base$suffix-$tag.tar
  docker save $repo/$namespace/openc3-operator$suffix:$tag -o tmp/openc3-operator$suffix-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-cmd-tlm-api$suffix:$tag -o tmp/openc3-cosmos-cmd-tlm-api$suffix-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-script-runner-api$suffix:$tag -o tmp/openc3-cosmos-script-runner-api$suffix-$tag.tar
  docker save $repo/$namespace/openc3-traefik$suffix:$tag -o tmp/openc3-traefik$suffix-$tag.tar
  docker save $repo/$namespace/openc3-redis$suffix:$tag -o tmp/openc3-redis$suffix-$tag.tar
  docker save $repo/$namespace/openc3-tsdb$suffix:$tag -o tmp/openc3-tsdb$suffix-$tag.tar
  docker save $repo/$namespace/openc3-minio$suffix:$tag -o tmp/openc3-minio$suffix-$tag.tar
  docker save $repo/$namespace/openc3-cosmos-init$suffix:$tag -o tmp/openc3-cosmos-init$suffix-$tag.tar
  set +x
}

loadTar() {
  if [ -z "$1" ]; then
    tag="latest"
  else
    tag=$1
  fi
  suffix=""
  if [[ -n "$2" ]]; then
    suffix=$2
  fi
  set -x
  docker load -i tmp/openc3-ruby$suffix-$tag.tar
  docker load -i tmp/openc3-node$suffix-$tag.tar
  docker load -i tmp/openc3-base$suffix-$tag.tar
  docker load -i tmp/openc3-operator$suffix-$tag.tar
  docker load -i tmp/openc3-cosmos-cmd-tlm-api$suffix-$tag.tar
  docker load -i tmp/openc3-cosmos-script-runner-api$suffix-$tag.tar
  docker load -i tmp/openc3-traefik$suffix-$tag.tar
  docker load -i tmp/openc3-redis$suffix-$tag.tar
  docker load -i tmp/openc3-tsdb$suffix-$tag.tar
  docker load -i tmp/openc3-minio$suffix-$tag.tar
  docker load -i tmp/openc3-cosmos-init$suffix-$tag.tar
  set +x
}

tag() {
  if [ "$#" -lt 4 ]; then
    echo "Usage: tag <REPO1> <REPO2> <NAMESPACE1> <TAG1> <NAMESPACE2> <TAG2> <SUFFIX>" >&2
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
  suffix=""
  if [[ -n "$7" ]]; then
    suffix=$7
  fi

  set -x
  docker tag $repo1/$namespace1/openc3-ruby$suffix:$tag1 $repo2/$namespace2/openc3-ruby$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-node$suffix:$tag1 $repo2/$namespace2/openc3-node$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-base$suffix:$tag1 $repo2/$namespace2/openc3-base$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-operator$suffix:$tag1 $repo2/$namespace2/openc3-operator$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-cmd-tlm-api$suffix:$tag1 $repo2/$namespace2/openc3-cosmos-cmd-tlm-api$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-script-runner-api$suffix:$tag1 $repo2/$namespace2/openc3-cosmos-script-runner-api$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-traefik$suffix:$tag1 $repo2/$namespace2/openc3-traefik$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-redis$suffix:$tag1 $repo2/$namespace2/openc3-redis$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-tsdb$suffix:$tag1 $repo2/$namespace2/openc3-tsdb$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-minio$suffix:$tag1 $repo2/$namespace2/openc3-minio$suffix:$tag2
  docker tag $repo1/$namespace1/openc3-cosmos-init$suffix:$tag1 $repo2/$namespace2/openc3-cosmos-init$suffix:$tag2
  set +x
}

push() {
  if [ "$#" -lt 3 ]; then
    echo "Usage: push <REPO> <NAMESPACE> <TAG> <SUFFIX>" >&2
    echo "e.g. push localhost:12345 openc3 latest" >&2
    exit 1
  fi
  repo=$1
  namespace=$2
  tag=$3
  suffix=""
  if [[ -n "$4" ]]; then
    suffix=$4
  fi

  set -x
  docker push $repo/$namespace/openc3-ruby$suffix:$tag
  docker push $repo/$namespace/openc3-node$suffix:$tag
  docker push $repo/$namespace/openc3-base$suffix:$tag
  docker push $repo/$namespace/openc3-operator$suffix:$tag
  docker push $repo/$namespace/openc3-cosmos-cmd-tlm-api$suffix:$tag
  docker push $repo/$namespace/openc3-cosmos-script-runner-api$suffix:$tag
  docker push $repo/$namespace/openc3-traefik$suffix:$tag
  docker push $repo/$namespace/openc3-redis$suffix:$tag
  docker push $repo/$namespace/openc3-tsdb$suffix:$tag
  docker push $repo/$namespace/openc3-minio$suffix:$tag
  docker push $repo/$namespace/openc3-cosmos-init$suffix:$tag
  set +x
}

cleanFiles() {
  find . -type d -name "node_modules" | xargs -I {} echo "Removing {}"; rm -rf {}
  find . -type d -name "coverage" | xargs -I {} echo "Removing {}"; rm -rf {}
  # Prompt for removing pnpm-lock.yaml files
  find . -type f -name "pnpm-lock.yaml" | xargs -I {} rm -i {}
  # Prompt for removing Gemfile.lock files
  find . -type f -name "Gemfile.lock" | xargs -I {} rm -i {}
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  usage $0
fi

case $1 in
  encode )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 encode STRING"
      echo ""
      echo "Encode a string to base64."
      echo ""
      echo "Arguments:"
      echo "  STRING    The string to encode (required)"
      echo ""
      echo "Example:"
      echo "  $0 encode \"my secret password\""
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    echo -n $2 | base64
    ;;
  hash )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 hash STRING"
      echo ""
      echo "Hash a string using SHA-256."
      echo ""
      echo "Arguments:"
      echo "  STRING    The string to hash (required)"
      echo ""
      echo "Example:"
      echo "  $0 hash \"my password\""
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    echo -n $2 | shasum -a 256 | sed 's/-//'
    ;;
  save )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 save REPO NAMESPACE TAG [SUFFIX]"
      echo ""
      echo "Pull and save all OpenC3 docker images to tar files in tmp/ directory."
      echo ""
      echo "Arguments:"
      echo "  REPO        Docker repository (e.g., docker.io)"
      echo "  NAMESPACE   Image namespace (e.g., openc3inc)"
      echo "  TAG         Image tag (e.g., latest or 5.1.0)"
      echo "  SUFFIX      Optional suffix for image names (e.g., -ubi)"
      echo ""
      echo "Example:"
      echo "  $0 save docker.io openc3inc 5.1.0"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    saveTar "${@:2}"
    ;;
  load )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 load [TAG] [SUFFIX]"
      echo ""
      echo "Load OpenC3 docker images from tar files in tmp/ directory."
      echo ""
      echo "Arguments:"
      echo "  TAG      Image tag (default: latest)"
      echo "  SUFFIX   Optional suffix for image names (e.g., -ubi)"
      echo ""
      echo "Example:"
      echo "  $0 load 5.1.0"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    loadTar "${@:2}"
    ;;
  tag )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 tag REPO1 REPO2 NAMESPACE1 TAG1 [NAMESPACE2] [TAG2] [SUFFIX]"
      echo ""
      echo "Tag OpenC3 images from one repository to another."
      echo ""
      echo "Arguments:"
      echo "  REPO1        Source repository (e.g., docker.io)"
      echo "  REPO2        Target repository (e.g., localhost:12345)"
      echo "  NAMESPACE1   Source namespace (e.g., openc3inc)"
      echo "  TAG1         Source tag (e.g., latest)"
      echo "  NAMESPACE2   Target namespace (default: same as NAMESPACE1)"
      echo "  TAG2         Target tag (default: same as TAG1)"
      echo "  SUFFIX       Optional suffix for image names (e.g., -ubi)"
      echo ""
      echo "Example:"
      echo "  $0 tag docker.io localhost:12345 openc3inc latest"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    tag "${@:2}"
    ;;
  push )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 push REPO NAMESPACE TAG [SUFFIX]"
      echo ""
      echo "Push all OpenC3 images to a docker repository."
      echo ""
      echo "Arguments:"
      echo "  REPO        Docker repository (e.g., localhost:12345)"
      echo "  NAMESPACE   Image namespace (e.g., openc3inc)"
      echo "  TAG         Image tag (e.g., latest)"
      echo "  SUFFIX      Optional suffix for image names (e.g., -ubi)"
      echo ""
      echo "Example:"
      echo "  $0 push localhost:12345 openc3 latest"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    push "${@:2}"
    ;;
  clean )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 clean"
      echo ""
      echo "Clean up development files from the project."
      echo ""
      echo "This command removes:"
      echo "  - All node_modules directories"
      echo "  - All coverage directories"
      echo "  - pnpm-lock.yaml files (with prompt)"
      echo "  - Gemfile.lock files (with prompt)"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    cleanFiles
    ;;
  hostsetup )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 hostsetup REPO NAMESPACE TAG"
      echo ""
      echo "Configure Docker host for Redis optimal performance."
      echo ""
      echo "This command:"
      echo "  - Disables transparent huge pages"
      echo "  - Sets vm.max_map_count to 262144"
      echo ""
      echo "Arguments:"
      echo "  REPO        Docker repository (e.g., docker.io)"
      echo "  NAMESPACE   Image namespace (e.g., openc3inc)"
      echo "  TAG         Image tag (e.g., latest)"
      echo ""
      echo "Example:"
      echo "  $0 hostsetup docker.io openc3inc latest"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
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
  hostenter )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 hostenter"
      echo ""
      echo "Enter a shell on the Docker VM host."
      echo ""
      echo "This uses nsenter to access the VM host running Docker."
      echo "Useful for debugging Docker host issues."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    docker run -it --rm --privileged --pid=host ${OPENC3_DEPENDENCY_REGISTRY}/alpine:${ALPINE_VERSION}.${ALPINE_BUILD} nsenter -t 1 -m -u -n -i sh
    ;;
  * )
    usage $0
    ;;
esac
