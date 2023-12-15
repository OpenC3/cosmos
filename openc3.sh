#!/bin/bash

set +e

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

export DOCKER_COMPOSE_COMMAND="docker compose"
${DOCKER_COMPOSE_COMMAND} version &> /dev/null
if [ "$?" -ne 0 ]; then
  export DOCKER_COMPOSE_COMMAND="docker-compose"
fi

docker info | grep -e "rootless$" -e "rootless: true"
if [ "$?" -ne 0 ]; then
  export OPENC3_ROOTFUL=1
  export OPENC3_USER_ID=`id -u`
  export OPENC3_GROUP_ID=`id -g`
else
  export OPENC3_ROOTLESS=1
  export OPENC3_USER_ID=0
  export OPENC3_GROUP_ID=0
fi

set -e

usage() {
  echo "Usage: $1 [cli, cliroot, start, stop, cleanup, build, run, dev, test, util]" >&2
  echo "*  cli: run a cli command as the default user ('cli help' for more info)" 1>&2
  echo "*  cliroot: run a cli command as the root user ('cli help' for more info)" 1>&2
  echo "*  start: start the docker compose openc3" >&2
  echo "*  stop: stop the running dockers for openc3" >&2
  echo "*  cleanup: cleanup network and volumes for openc3" >&2
  echo "*  build: build the containers for openc3" >&2
  echo "*  run: run the prebuilt containers for openc3" >&2
  echo "*  dev: run openc3 in a dev mode" >&2
  echo "*  test: test openc3" >&2
  echo "*  util: various helper commands" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

case $1 in
  cli )
    # Source the .env file to setup environment variables
    set -a
    . "$(dirname -- "$0")/.env"
    # Start (and remove when done --rm) the openc3-operator container with the current working directory
    # mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
    # This allows tools running in the container to have a consistent path to the current working directory.
    # Run the command "ruby /openc3/bin/openc3cli" with all parameters starting at 2 since the first is 'openc3'
    args=`echo $@ | { read _ args; echo $args; }`
    # Make sure the network exists
    (docker network create openc3-cosmos-network || true) &> /dev/null
    docker run -it --rm --env-file "$(dirname -- "$0")/.env" --user=$OPENC3_USER_ID:$OPENC3_GROUP_ID --network openc3-cosmos-network -v `pwd`:/openc3/local:z -w /openc3/local $OPENC3_REGISTRY/$OPENC3_NAMESPACE/openc3-operator$OPENC3_IMAGE_SUFFIX:$OPENC3_TAG ruby /openc3/bin/openc3cli $args
    set +a
    ;;
  cliroot )
    set -a
    . "$(dirname -- "$0")/.env"
    args=`echo $@ | { read _ args; echo $args; }`
    (docker network create openc3-cosmos-network || true) &> /dev/null
    docker run -it --rm --env-file "$(dirname -- "$0")/.env" --user=root --network openc3-cosmos-network -v `pwd`:/openc3/local:z -w /openc3/local $OPENC3_REGISTRY/$OPENC3_NAMESPACE/openc3-operator$OPENC3_IMAGE_SUFFIX:$OPENC3_TAG ruby /openc3/bin/openc3cli $args
    set +a
    ;;
  start )
    ./openc3.sh build
    ./openc3.sh run
    ;;
  start-ubi )
    ./openc3.sh build-ubi
    ./openc3.sh run-ubi
    ;;
  stop )
    ${DOCKER_COMPOSE_COMMAND} stop openc3-operator
    ${DOCKER_COMPOSE_COMMAND} stop openc3-cosmos-script-runner-api
    ${DOCKER_COMPOSE_COMMAND} stop openc3-cosmos-cmd-tlm-api
    sleep 5
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml down -t 30
    ;;
  cleanup )
    if [ "$2" == "force" ]
    then
      ${DOCKER_COMPOSE_COMMAND} -f compose.yaml down -t 30 -v
    else
      echo "Are you sure? Cleanup removes ALL docker volumes and all COSMOS data! (1-Yes / 2-No)"
      select yn in "Yes" "No"; do
        case $yn in
          Yes ) ${DOCKER_COMPOSE_COMMAND} -f compose.yaml down -t 30 -v; break;;
          No ) exit;;
        esac
      done
    fi
    ;;
  build )
    scripts/linux/openc3_setup.sh
    # Handle restrictive umasks - Built files need to be world readable
    umask 0022
    chmod -R +r .
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-build.yaml build openc3-ruby
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-build.yaml build openc3-base
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-build.yaml build openc3-node
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-build.yaml build
    ;;
  build-ubi )
    set -a
    . "$(dirname -- "$0")/.env"
    if test -f /etc/ssl/certs/ca-bundle.crt
    then
      cp /etc/ssl/certs/ca-bundle.crt ./cacert.pem
    fi
    scripts/linux/openc3_setup.sh
    scripts/linux/openc3_build_ubi.sh
    set +a
    ;;
  run )
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml up -d
    ;;
  run-ubi )
    OPENC3_IMAGE_SUFFIX=-ubi OPENC3_REDIS_VOLUME=/home/data ${DOCKER_COMPOSE_COMMAND} -f compose.yaml up -d
    ;;
  dev )
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-dev.yaml up -d
    ;;
  test )
    scripts/linux/openc3_setup.sh
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml -f compose-build.yaml build
    scripts/linux/openc3_test.sh $2
    ;;
  util )
    set -a
    . "$(dirname -- "$0")/.env"
    scripts/linux/openc3_util.sh "${@:2}"
    set +a
    ;;
  * )
    usage $0
    ;;
esac
