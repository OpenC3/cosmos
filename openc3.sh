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

# Helper function to find script - checks PATH first, then falls back to script location
find_script() {
  local script_name="$1"
  if command -v "$script_name" &> /dev/null; then
    echo "$script_name"
  else
    echo "$(dirname -- "$0")/scripts/linux/$script_name"
  fi
}

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
  echo "Usage: $1 [cli, start, stop, cleanup, build, run, test, util]" >&2
  echo "*  cli: run a cli command as the default user ('cli help' for more info)" 1>&2
  echo "*  start: build and run" >&2
  echo "*  stop: stop the containers (compose stop)" >&2
  echo "*  cleanup [local] [force]: REMOVE volumes / data (compose down -v)" >&2
  echo "*  build: build the containers (compose build)" >&2
  echo "*  run: run the containers (compose up)" >&2
  echo "*  test: test openc3" >&2
  echo "*  util: various helper commands" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage $0
fi

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  usage $0
fi

check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "WARNING: COSMOS should not be run as the root user, as permissions for Local Mode will be affected. Do not use sudo when running COSMOS. See more: https://docs.openc3.com/docs/guides/local-mode"
  fi
}

case $1 in
  cli )
    # Source the .env file to setup environment variables
    set -a
    . "$(dirname -- "$0")/.env"
    # Start (and remove when done --rm) the openc3-cosmos-cmd-tlm-api container with the current working directory
    # mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
    # This allows tools running in the container to have a consistent path to the current working directory.
    # Run the command "ruby /openc3/bin/openc3cli" with all parameters starting at 2 since the first is 'openc3'
    args=`echo $@ | { read _ args; echo $args; }`
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" run -it --rm -v `pwd`:/openc3/local:z -w /openc3/local -e OPENC3_API_PASSWORD=$OPENC3_API_PASSWORD --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli $args
    set +a
    ;;
  start )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 start"
      echo ""
      echo "Build and run OpenC3 containers."
      echo ""
      echo "This command:"
      echo "  1. Builds all OpenC3 containers (equivalent to 'openc3.sh build')"
      echo "  2. Starts all containers (equivalent to 'openc3.sh run')"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    openc3.sh build
    openc3.sh run
    ;;
  start-ubi )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 start-ubi"
      echo ""
      echo "Build and run OpenC3 UBI containers."
      echo ""
      echo "This command:"
      echo "  1. Builds all OpenC3 UBI containers (equivalent to 'openc3.sh build-ubi')"
      echo "  2. Starts all UBI containers (equivalent to 'openc3.sh run-ubi')"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    openc3.sh build-ubi
    openc3.sh run-ubi
    ;;
  stop )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 stop"
      echo ""
      echo "Stop all OpenC3 containers gracefully."
      echo ""
      echo "This command:"
      echo "  1. Stops operator, script-runner-api, and cmd-tlm-api containers"
      echo "  2. Waits 5 seconds"
      echo "  3. Runs docker compose down with 30 second timeout"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-operator
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-cosmos-script-runner-api
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-cosmos-cmd-tlm-api
    sleep 5
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30
    ;;
  cleanup )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 cleanup [local] [force]"
      echo ""
      echo "Remove all OpenC3 docker volumes and data."
      echo ""
      echo "WARNING: This is a destructive operation that removes ALL COSMOS data!"
      echo ""
      echo "Arguments:"
      echo "  local    Also remove local plugin files in plugins/DEFAULT/"
      echo "  force    Skip confirmation prompt"
      echo ""
      echo "Examples:"
      echo "  $0 cleanup              # Remove volumes (with confirmation)"
      echo "  $0 cleanup force        # Remove volumes (no confirmation)"
      echo "  $0 cleanup local        # Remove volumes and local plugins"
      echo "  $0 cleanup local force  # Remove volumes and local plugins (no confirmation)"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    # They can specify 'cleanup force' or 'cleanup local force'
    if [ "$2" == "force" ] || [ "$3" == "force" ]
    then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30 -v
    else
      echo "Are you sure? Cleanup removes ALL docker volumes and all COSMOS data! (1-Yes / 2-No)"
      select yn in "Yes" "No"; do
        case $yn in
          Yes ) ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30 -v; break;;
          No ) exit;;
        esac
      done
    fi
    if [ "$2" == "local" ]
    then
      cd "$(dirname -- "$0")/plugins/DEFAULT"
      ls | grep -xv "README.md" | xargs rm -r
      cd ../..
    fi
    ;;
  build )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 build"
      echo ""
      echo "Build all OpenC3 docker containers."
      echo ""
      echo "This command:"
      echo "  1. Runs setup to download certificates"
      echo "  2. Builds openc3-ruby base image"
      echo "  3. Builds openc3-base image"
      echo "  4. Builds openc3-node image"
      echo "  5. Builds all remaining service containers"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    # Change to cosmos directory since openc3_setup.sh uses relative paths
    cd "$(dirname -- "$0")"
    "$(find_script openc3_setup.sh)"
    # Handle restrictive umasks - Built files need to be world readable
    umask 0022
    chmod -R +r "$(dirname -- "$0")"
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-ruby
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-base
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-node
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build
    ;;
  build-ubi )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 build-ubi"
      echo ""
      echo "Build all OpenC3 UBI (Universal Base Image) containers."
      echo ""
      echo "This is used for enterprise deployments requiring Red Hat UBI base images."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    # Change to cosmos directory since scripts use relative paths
    cd "$(dirname -- "$0")"
    set -a
    . "$(dirname -- "$0")/.env"
    if test -f /etc/ssl/certs/ca-bundle.crt
    then
      cp /etc/ssl/certs/ca-bundle.crt "$(dirname -- "$0")/cacert.pem"
    fi
    "$(find_script openc3_setup.sh)"
    "$(find_script openc3_build_ubi.sh)"
    set +a
    ;;
  run )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 run"
      echo ""
      echo "Run all OpenC3 containers in detached mode."
      echo ""
      echo "Containers will start in the background using docker compose up -d."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    check_root
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" up -d
    ;;
  run-ubi )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 run-ubi"
      echo ""
      echo "Run all OpenC3 UBI containers in detached mode."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    check_root
    OPENC3_IMAGE_SUFFIX=-ubi OPENC3_REDIS_VOLUME=/home/data ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" up -d
    ;;
  test )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 test [COMMAND] [OPTIONS]"
      echo ""
      echo "Test OpenC3. Run '$0 test --help' for available test commands."
      echo ""
      echo "This builds OpenC3 and runs the specified test suite."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    # Change to cosmos directory since openc3_setup.sh uses relative paths
    cd "$(dirname -- "$0")"
    "$(find_script openc3_setup.sh)"
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build
    "$(find_script openc3_test.sh)" "${@:2}"
    ;;
  util )
    if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
      echo "Usage: $0 util [COMMAND] [OPTIONS]"
      echo ""
      echo "Various OpenC3 utility commands."
      echo ""
      echo "Run '$0 util' (without arguments) to see available utility commands."
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    set -a
    . "$(dirname -- "$0")/.env"
    "$(find_script openc3_util.sh)" "${@:2}"
    set +a
    ;;
  * )
    usage $0
    ;;
esac
