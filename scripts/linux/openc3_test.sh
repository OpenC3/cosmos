#!/bin/bash

set +e

export DOCKER_COMPOSE_COMMAND="docker compose"
${DOCKER_COMPOSE_COMMAND} version
if [ "$?" -ne 0 ]; then
  export DOCKER_COMPOSE_COMMAND="docker-compose"
fi

set -e

usage() {
  echo "Usage: $1 [rspec, playwright]" >&2
  echo "*  rspec: run tests against Ruby code" >&2
  echo "*  playwright: run end-to-end tests" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

case $1 in
  rspec )
    cd openc3
    rspec
    cd -
    ;;

  playwright )
    case $2 in
      install-playwright )
        cd playwright
        ./playwright.sh install-playwright
        cd -
        ;;

      build-plugin )
        cd playwright
        ./playwright.sh build-plugin
        cd -
        ;;

      run-chromium )
        cd playwright
        ./playwright.sh run-chromium "${@:3}"
        cd -
        ;;

      reset-storage-state )
        cd playwright
        ./playwright.sh reset-storage-state
        cd -
        ;;

      * )
        echo "Usage:" >&2
        echo "*  install-playwright: installs playwright and its dependencies" >&2
        echo "*  build-plugin: builds the plugin to be used in the playwright tests" >&2
        echo "*  run-chromium: runs the playwright tests against a locally running version of Cosmos using Chrome" >&2
        echo "*  reset-storage-state: clear out cached data" >&2
        ;;

    esac
    ;;

  hash )
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml up -d
    cd playwright
    yarn run fixlinux
    yarn playwright test
    yarn coverage
    cd -
    ;;
  * )
    usage $0
    ;;
esac
