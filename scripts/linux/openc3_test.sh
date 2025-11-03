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

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  usage $0
fi

case $1 in
  rspec )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 rspec"
      echo ""
      echo "Run RSpec tests against Ruby code in the openc3 directory."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    cd openc3
    rspec
    cd -
    ;;

  playwright )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 playwright [COMMAND]"
      echo ""
      echo "Run Playwright end-to-end tests."
      echo ""
      echo "Commands:"
      echo "  install-playwright    Install playwright and its dependencies"
      echo "  build-plugin          Build the plugin for playwright tests"
      echo "  run-chromium          Run playwright tests using Chrome"
      echo "  reset-storage-state   Clear out cached data"
      echo ""
      echo "Options:"
      echo "  -h, --help            Show this help message"
      exit 0
    fi
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
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 hash"
      echo ""
      echo "Run comprehensive Playwright tests with coverage."
      echo ""
      echo "This command:"
      echo "  1. Starts OpenC3 containers"
      echo "  2. Runs fixlinux script"
      echo "  3. Executes pnpm test"
      echo "  4. Generates coverage report"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    ${DOCKER_COMPOSE_COMMAND} -f compose.yaml up -d
    cd playwright
    pnpm run fixlinux
    pnpm test
    pnpm coverage
    cd -
    ;;
  * )
    usage $0
    ;;
esac
