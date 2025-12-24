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
if [[ "$?" -ne 0 ]]; then
  export DOCKER_COMPOSE_COMMAND="docker-compose"
fi

docker info | grep -e "rootless$" -e "rootless: true"
if [[ "$?" -ne 0 ]]; then
  export OPENC3_ROOTFUL=1
  export OPENC3_USER_ID=`id -u`
  export OPENC3_GROUP_ID=`id -g`
else
  export OPENC3_ROOTLESS=1
  export OPENC3_USER_ID=0
  export OPENC3_GROUP_ID=0
fi

# Detect if this is a development (build) environment or runtime environment
# by checking for compose-build.yaml
if [[ -f "$(dirname -- "$0")/compose-build.yaml" ]]; then
  export OPENC3_DEVEL=1
else
  export OPENC3_DEVEL=0
fi

# Detect if this is enterprise by checking for enterprise-specific services
if [[ -f "$(dirname -- "$0")/compose-build.yaml" ]] && grep -q "openc3-enterprise-gem" "$(dirname -- "$0")/compose-build.yaml" 2>/dev/null; then
  export OPENC3_ENTERPRISE=1
elif [[ -f "$(dirname -- "$0")/compose.yaml" ]] && grep -q "openc3-metrics" "$(dirname -- "$0")/compose.yaml" 2>/dev/null; then
  export OPENC3_ENTERPRISE=1
else
  export OPENC3_ENTERPRISE=0
fi

# Set display name based on enterprise flag
if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
  export COSMOS_NAME="COSMOS Enterprise"
else
  export COSMOS_NAME="COSMOS Core"
fi

set -e

usage() {
  if [[ "$OPENC3_DEVEL" -eq 1 ]] && [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
    cat >&2 << EOF
OpenC3 $COSMOS_NAME - Command and Control System (Enterprise Development Installation)
Usage: $1 COMMAND [OPTIONS]

DESCRIPTION:
  $COSMOS_NAME is a command and control system for embedded systems. This script
  provides a convenient interface for building, running, testing, and managing
  $COSMOS_NAME in Docker containers.

  This is an ENTERPRISE DEVELOPMENT installation with source code and build capabilities.

COMMON COMMANDS:
EOF
  elif [[ "$OPENC3_DEVEL" -eq 1 ]]; then
    cat >&2 << EOF
OpenC3 $COSMOS_NAME - Command and Control System (Development Installation)
Usage: $1 COMMAND [OPTIONS]

DESCRIPTION:
  $COSMOS_NAME is a command and control system for embedded systems. This script
  provides a convenient interface for building, running, testing, and managing
  $COSMOS_NAME in Docker containers.

  This is a DEVELOPMENT installation with source code and build capabilities.

COMMON COMMANDS:
EOF
  elif [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
    cat >&2 << EOF
OpenC3 $COSMOS_NAME - Command and Control System (Enterprise Runtime-Only Installation)
Usage: $1 COMMAND [OPTIONS]

DESCRIPTION:
  $COSMOS_NAME is a command and control system for embedded systems. This script
  provides a convenient interface for running, testing, and managing
  $COSMOS_NAME in Docker containers.

  This is an ENTERPRISE RUNTIME-ONLY installation using pre-built images.

COMMON COMMANDS:
EOF
  else
    cat >&2 << EOF
OpenC3 $COSMOS_NAME - Command and Control System (Runtime-Only Installation)
Usage: $1 COMMAND [OPTIONS]

DESCRIPTION:
  $COSMOS_NAME is a command and control system for embedded systems. This script
  provides a convenient interface for running, testing, and managing
  $COSMOS_NAME in Docker containers.

  This is a RUNTIME-ONLY installation using pre-built images.

COMMON COMMANDS:
EOF
  fi
  if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
    cat >&2 << EOF
  start                 Build and run $COSMOS_NAME (equivalent to: build + run)
                        This is the typical command to get $COSMOS_NAME running.

EOF
  else
    cat >&2 << EOF
  run                   Start $COSMOS_NAME containers
                        Access at: http://localhost:2900

EOF
  fi
  cat >&2 << EOF
  stop                  Stop all running $COSMOS_NAME containers gracefully
                        Allows containers to shutdown cleanly.

  cli [COMMAND]         Run $COSMOS_NAME CLI commands in a container
                        Use 'cli help' for available commands
                        Use 'cli --help' for Docker wrapper info
                        Examples:
                          $1 cli generate plugin MyPlugin
                          $1 cli validate myplugin.gem

  cliroot [COMMAND]     Run $COSMOS_NAME CLI commands as root user
                        Same as 'cli' but with root privileges

EOF
  if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
    cat >&2 << EOF
DEVELOPMENT COMMANDS:
  build                 Build all $COSMOS_NAME Docker containers from source
                        Required before first run or after code changes.

  run                   Start $COSMOS_NAME containers in detached mode
                        Access at: http://localhost:2900

EOF
  fi
  cat >&2 << EOF
  test [COMMAND]        Run test suites (rspec, playwright, hash)
                        Use '$1 test' to see available test commands.

  util [COMMAND]        Utility commands (encode, hash, save, load, etc.)
                        Use '$1 util' to see available utilities.

  generate_compose      Generate compose.yaml from template
                        Merges template with core/enterprise overrides.
                        Use '$1 generate_compose --help' for details.

EOF
  if [[ "$OPENC3_DEVEL" -eq 0 ]]; then
    cat >&2 << EOF
  upgrade               Upgrade $COSMOS_NAME to latest version
                        Downloads and installs latest release.

EOF
  fi
  cat >&2 << EOF
CLEANUP:
  cleanup [OPTIONS]     Remove Docker volumes and data
                        WARNING: This deletes all $COSMOS_NAME data!
                        Options:
                          local  - Also remove local plugin files
                          force  - Skip confirmation prompt

EOF
  if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
    cat >&2 << EOF
REDHAT:
  start-ubi             Build and run with Red Hat UBI images
  build-ubi             Build containers using UBI base images
  run-ubi               Run containers with UBI images
                        For air-gapped or government environments.

EOF
  fi
  cat >&2 << EOF
GETTING STARTED:
  1. First time setup:     $1 start
  2. Access COSMOS:        http://localhost:2900
  3. Stop when done:       $1 stop
  4. Remove everything:    $1 cleanup

MORE INFORMATION:
  Run '$1 COMMAND --help' for detailed help on any command.
  Documentation: https://docs.openc3.com

OPTIONS:
  -h, --help            Show this help message

EOF
  exit 1
}

if [[ "$#" -eq 0 ]]; then
  usage $0
fi

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage $0
fi

check_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "WARNING: $COSMOS_NAME should not be run as the root user, as permissions for Local Mode will be affected. Do not use sudo when running $COSMOS_NAME. See more: https://docs.openc3.com/docs/guides/local-mode"
  fi
}

case $1 in
  cli )
    if [[ "$2" == "--wrapper-help" ]] || [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 cli [COMMAND] [OPTIONS]"
      echo ""
      echo "Run $COSMOS_NAME CLI commands inside a Docker container as the default user."
      echo ""
      echo "What this wrapper does:"
      echo "  - Starts a temporary Docker container (removed after use)"
      echo "  - Mounts your current directory as /openc3/local inside the container"
      echo "  - Runs the Ruby CLI tool (/openc3/bin/openc3cli) with your arguments"
      echo "  - Uses interactive terminal mode (-it) for commands that need input"
      echo ""
      echo "Prerequisites:"
      echo "  - Containers must be built first: $0 build"
      echo "  - .env file must exist in the $COSMOS_NAME directory"
      echo ""
      echo "Common commands:"
      echo "  $0 cli help                           Show CLI command help"
      echo "  $0 cli validate plugin.gem            Validate a plugin"
      echo "  $0 cli load plugin.gem                Load a plugin"
      echo "  $0 cli generate plugin MyPlugin --ruby"
      echo "                                        Generate a new plugin"
      echo ""
      echo "For detailed CLI command help, run: $0 cli help"
      echo ""
      echo "Note: Use 'cliroot' instead of 'cli' to run as root user."
      echo ""
      echo "Environment variables:"
      echo "  ENV_FILE          Path to environment file (default: .env)"
      echo ""
      echo "Options:"
      echo "  -h, --help        Show this help message"
      echo "  --wrapper-help    (same as --help)"
      exit 0
    fi
    # Source the environment file to setup environment variables
    # Use ENV_FILE if set, otherwise default to .env
    set -a
    . "$(dirname -- "$0")/${ENV_FILE:-.env}"
    # Start (and remove when done --rm) the cmd-tlm-api container with the current working directory
    # mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
    # This allows tools running in the container to have a consistent path to the current working directory.
    # Run the command "ruby /openc3/bin/openc3cli" with all parameters starting at 2 since the first is 'openc3'
    # Shift off the first argument (script name) to get CLI args
    shift
    if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" run -it --rm -v $(pwd):/openc3/local:z -w /openc3/local -e OPENC3_API_USER=$OPENC3_API_USER -e OPENC3_API_PASSWORD=$OPENC3_API_PASSWORD --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli "$@"
    else
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" run -it --rm -v $(pwd):/openc3/local:z -w /openc3/local -e OPENC3_API_PASSWORD=$OPENC3_API_PASSWORD --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli "$@"
    fi
    set +a
    ;;
  cliroot )
    if [[ "$2" == "--wrapper-help" ]] || [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 cliroot [COMMAND] [OPTIONS]"
      echo ""
      echo "Run $COSMOS_NAME CLI commands inside a Docker container as root user."
      echo ""
      echo "This is the same as 'cli' but runs as root instead of the default user."
      echo "Use this when you need elevated privileges inside the container."
      echo ""
      echo "What this wrapper does:"
      echo "  - Starts a temporary Docker container (removed after use)"
      echo "  - Mounts your current directory as /openc3/local inside the container"
      echo "  - Runs the Ruby CLI tool (/openc3/bin/openc3cli) with your arguments"
      echo "  - Uses interactive terminal mode (-it) for commands that need input"
      echo "  - Runs as root user (--user=root)"
      echo ""
      echo "Prerequisites:"
      echo "  - Containers must be built first: $0 build"
      echo "  - .env file must exist in the $COSMOS_NAME directory"
      echo ""
      echo "Common commands:"
      echo "  $0 cliroot help                       Show CLI command help"
      echo "  $0 cliroot validate plugin.gem        Validate a plugin"
      echo "  $0 cliroot load plugin.gem            Load a plugin"
      echo ""
      echo "For detailed CLI command help, run: $0 cliroot help"
      echo ""
      echo "Environment variables:"
      echo "  ENV_FILE          Path to environment file (default: .env)"
      echo ""
      echo "Options:"
      echo "  -h, --help        Show this help message"
      echo "  --wrapper-help    (same as --help)"
      exit 0
    fi
    # Source the environment file to setup environment variables
    # Use ENV_FILE if set, otherwise default to .env
    set -a
    . "$(dirname -- "$0")/${ENV_FILE:-.env}"
    # Same as cli but run as root user
    # Note: The service name is always openc3-cosmos-cmd-tlm-api; compose.yaml pulls the correct image
    # (enterprise or non-enterprise) based on environment variables.
    # Shift off the first argument (script name) to get CLI args
    shift
    if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" run -it --rm --user=root -v $(pwd):/openc3/local:z -w /openc3/local -e OPENC3_API_USER=$OPENC3_API_USER -e OPENC3_API_PASSWORD=$OPENC3_API_PASSWORD --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli "$@"
    else
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" run -it --rm --user=root -v $(pwd):/openc3/local:z -w /openc3/local -e OPENC3_API_PASSWORD=$OPENC3_API_PASSWORD --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli "$@"
    fi
    set +a
    ;;
  start )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
        echo "Usage: $0 start"
        echo ""
        echo "Build and run $COSMOS_NAME containers."
        echo ""
        echo "This command:"
        echo "  1. Builds all $COSMOS_NAME containers (equivalent to 'openc3.sh build')"
        echo "  2. Starts all containers (equivalent to 'openc3.sh run')"
        echo ""
        echo "Options:"
        echo "  -h, --help    Show this help message"
      else
        echo "Usage: $0 start"
        echo ""
        echo "Start $COSMOS_NAME containers."
        echo ""
        echo "This is an alias for 'run' command in runtime-only installations."
        echo ""
        echo "Options:"
        echo "  -h, --help    Show this help message"
      fi
      exit 0
    fi
    if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
      "$0" build
      "$0" run
    else
      "$0" run
    fi
    ;;
  start-ubi )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
        echo "Usage: $0 start-ubi"
        echo ""
        echo "Build and run $COSMOS_NAME UBI containers."
        echo ""
        echo "This command:"
        echo "  1. Builds all $COSMOS_NAME UBI containers (equivalent to 'openc3.sh build-ubi')"
        echo "  2. Starts all UBI containers (equivalent to 'openc3.sh run-ubi')"
        echo ""
        echo "Options:"
        echo "  -h, --help    Show this help message"
      else
        echo "Usage: $0 start-ubi"
        echo ""
        echo "Run all $COSMOS_NAME UBI containers in detached mode."
        echo ""
        echo "This is an alias for 'run-ubi' command."
        echo ""
        echo "Options:"
        echo "  -h, --help    Show this help message"
      fi
      exit 0
    fi
    if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
      "$0" build-ubi
      "$0" run-ubi
    else
      "$0" run-ubi
    fi
    ;;
  stop )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 stop"
      echo ""
      echo "Stop all $COSMOS_NAME containers gracefully."
      echo ""
      if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
        echo "This command:"
        echo "  1. Stops operator, script-runner-api, cmd-tlm-api, and metrics containers"
        echo "  2. Waits 5 seconds"
        echo "  3. Runs docker compose down with 30 second timeout"
      else
        echo "This command:"
        echo "  1. Stops operator, script-runner-api, and cmd-tlm-api containers"
        echo "  2. Waits 5 seconds"
        echo "  3. Runs docker compose down with 30 second timeout"
      fi
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-operator
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-cosmos-script-runner-api
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-cosmos-cmd-tlm-api
    if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" stop openc3-metrics
    fi
    sleep 5
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30
    ;;
  cleanup )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 cleanup [local] [force]"
      echo ""
      echo "Remove all $COSMOS_NAME docker volumes and data."
      echo ""
      echo "WARNING: This is a destructive operation that removes ALL $COSMOS_NAME data!"
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
    if [[ "$2" == "force" ]] || [[ "$3" == "force" ]]
    then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30 -v
    else
      echo "Are you sure? Cleanup removes ALL docker volumes and all $COSMOS_NAME data! (1-Yes / 2-No)"
      select yn in "Yes" "No"; do
        case $yn in
          Yes ) ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" down -t 30 -v; break;;
          No ) exit;;
        esac
      done
    fi
    if [[ "$2" == "local" ]]; then
      cd "$(dirname -- "$0")/plugins/DEFAULT"
      ls | grep -xv "README.md" | xargs rm -r
      cd ../..
    fi
    ;;
  build )
    if [[ "$OPENC3_DEVEL" -eq 0 ]]; then
      echo "Error: 'build' command is only available in development environments" >&2
      echo "This appears to be a runtime-only installation." >&2
      exit 1
    fi
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 build"
      echo ""
      echo "Build all $COSMOS_NAME docker containers."
      echo ""
      if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
        echo "This command:"
        echo "  1. Runs setup to download certificates"
        echo "  2. Builds openc3-enterprise-gem image"
        echo "  3. Builds all remaining service containers"
      else
        echo "This command:"
        echo "  1. Runs setup to download certificates"
        echo "  2. Builds openc3-ruby base image"
        echo "  3. Builds openc3-base image"
        echo "  4. Builds openc3-node image"
        echo "  5. Builds all remaining service containers"
      fi
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
    if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-enterprise-gem
    else
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-ruby
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-base
      ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build openc3-node
    fi
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build
    ;;
  build-ubi )
    if [[ "$OPENC3_DEVEL" -eq 0 ]]; then
      echo "Error: 'build-ubi' command is only available in development environments" >&2
      echo "This appears to be a runtime-only installation." >&2
      exit 1
    fi
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 build-ubi [IMAGE_NAME...]"
      echo ""
      echo "Build $COSMOS_NAME UBI (Universal Base Image) containers."
      echo ""
      echo "This is used for enterprise deployments requiring Red Hat UBI base images,"
      echo "suitable for air-gapped and government environments."
      echo ""
      echo "Arguments:"
      echo "  IMAGE_NAME    One or more image names to build (optional)"
      echo "                If no images are specified, all images will be built"
      echo ""
      echo "Required environment variables (set in env file):"
      echo "  OPENC3_UBI_REGISTRY      UBI registry URL"
      echo "  OPENC3_UBI_IMAGE         UBI image name"
      echo "  OPENC3_UBI_TAG           UBI image tag"
      echo "  OPENC3_REGISTRY          Target registry for built images"
      echo "  OPENC3_NAMESPACE         Target namespace"
      echo "  OPENC3_TAG               Tag for built images"
      echo ""
      echo "Optional environment variables:"
      echo "  ENV_FILE                 Path to environment file (default: .env)"
      echo "  RUBYGEMS_URL             RubyGems mirror URL (for air-gapped)"
      echo "  PYPI_URL                 PyPI mirror URL (for air-gapped)"
      echo "  NPM_URL                  NPM registry URL (for air-gapped)"
      echo ""
      echo "This command:"
      echo "  1. Sources environment file for configuration"
      echo "  2. Copies CA certificates if available"
      echo "  3. Runs openc3_setup.sh"
      echo "  4. Builds UBI-based containers"
      echo ""
      echo "Examples:"
      echo "  $0 build-ubi                              # Build all images"
      echo "  $0 build-ubi openc3-ruby-ubi              # Build one image"
      echo "  ENV_FILE=.env.prod $0 build-ubi           # Use different env file"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    # Change to cosmos directory since scripts use relative paths
    cd "$(dirname -- "$0")"
    set -a
    . "$(dirname -- "$0")/${ENV_FILE:-.env}"
    if test -f /etc/ssl/certs/ca-bundle.crt
    then
      cp /etc/ssl/certs/ca-bundle.crt "$(dirname -- "$0")/cacert.pem"
    fi
    "$(find_script openc3_setup.sh)"
    # Pass through any additional arguments (image names) to openc3_build_ubi.sh
    "$(find_script openc3_build_ubi.sh)" "${@:2}"
    set +a
    ;;
  run )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 run"
      echo ""
      echo "Run all $COSMOS_NAME containers in detached mode."
      echo ""
      echo "Containers will start in the background using docker compose up -d."
      echo ""
      echo "After starting, check status with:"
      echo "  docker compose ps                   # Show running containers"
      echo "  docker compose logs -f              # Follow all logs"
      echo "  docker compose logs -f SERVICE      # Follow specific service logs"
      echo ""
      echo "Access $COSMOS_NAME:"
      echo "  http://localhost:2900               # $COSMOS_NAME web interface"
      echo ""
      echo "Common services:"
      echo "  openc3-operator                     Main orchestration service"
      echo "  openc3-cosmos-cmd-tlm-api          Command/Telemetry API"
      echo "  openc3-cosmos-script-runner-api    Script execution service"
      echo "  openc3-redis                        Redis database"
      echo "  openc3-minio                        Object storage"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    check_root
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" up -d
    ;;
  run-ubi )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 run-ubi"
      echo ""
      echo "Run all $COSMOS_NAME UBI (Universal Base Image) containers in detached mode."
      echo ""
      echo "This uses UBI-based container images and sets UBI-specific configurations:"
      echo "  - Image suffix: -ubi"
      echo "  - Redis volume: /home/data (for UBI compatibility)"
      echo ""
      echo "Containers will start in the background using docker compose up -d."
      echo ""
      echo "After starting, check status with:"
      echo "  docker compose ps                   # Show running containers"
      echo "  docker compose logs -f              # Follow all logs"
      echo "  docker compose logs -f SERVICE      # Follow specific service logs"
      echo ""
      echo "Access $COSMOS_NAME:"
      echo "  http://localhost:2900               # $COSMOS_NAME web interface"
      echo ""
      echo "Common services:"
      echo "  openc3-operator                     Main orchestration service"
      echo "  openc3-cosmos-cmd-tlm-api          Command/Telemetry API"
      echo "  openc3-cosmos-script-runner-api    Script execution service"
      echo "  openc3-redis                        Redis database"
      echo "  openc3-minio                        Object storage"
      echo ""
      echo "Options:"
      echo "  -h, --help    Show this help message"
      exit 0
    fi
    check_root
    OPENC3_IMAGE_SUFFIX=-ubi OPENC3_REDIS_VOLUME=/home/data ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" up -d
    ;;
  test )
    # Check for help at any position
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]] || [[ "$#" -eq 1 ]]; then
      echo "Usage: $0 test COMMAND [OPTIONS]"
      echo ""
      echo "Test $COSMOS_NAME. This builds $COSMOS_NAME and runs the specified test suite."
      echo ""
      echo "Available commands:"
      echo "  rspec                       Run RSpec tests against Ruby code"
      echo "  playwright [SUBCOMMAND]     Run Playwright end-to-end tests"
      echo "    install-playwright        Install playwright and dependencies"
      echo "    build-plugin              Build the plugin for tests"
      echo "    run-chromium              Run tests using Chrome"
      echo "    reset-storage-state       Clear cached data"
      echo "  hash                        Run comprehensive tests with coverage"
      echo ""
      echo "Run '$0 test COMMAND --help' for detailed help on each command."
      echo ""
      echo "Options:"
      echo "  -h, --help                  Show this help message"
      exit 0
    fi
    # If subcommand has --help or -h, skip setup/build and pass through directly
    for arg in "$@"; do
      if [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
        "$(find_script openc3_test.sh)" "${@:2}"
        exit 0
      fi
    done
    # Change to cosmos directory since openc3_setup.sh uses relative paths
    cd "$(dirname -- "$0")"
    "$(find_script openc3_setup.sh)"
    ${DOCKER_COMPOSE_COMMAND} -f "$(dirname -- "$0")/compose.yaml" -f "$(dirname -- "$0")/compose-build.yaml" build
    "$(find_script openc3_test.sh)" "${@:2}"
    ;;
  upgrade )
    if [[ "$OPENC3_DEVEL" -eq 1 ]]; then
      echo "Error: 'upgrade' command is only available in runtime environments" >&2
      echo "This appears to be a development installation." >&2
      exit 1
    fi
    "$(find_script openc3_upgrade.sh)" "${@:2}"
    ;;
  generate_compose )
    if [[ "$OPENC3_DEVEL" -eq 0 ]]; then
      echo "Error: 'generate_command' command is only available in development environments" >&2
      echo "This appears to be a runtime-only installation." >&2
      exit 1
    fi
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
      echo "Usage: $0 generate_compose [OPTIONS]"
      echo ""
      echo "Generate compose.yaml from template and mode-specific overrides."
      echo ""
      echo "This command uses a template-based system to generate compose.yaml files"
      echo "for both OpenC3 Core and Enterprise editions. It ensures that shared"
      echo "configuration stays in sync while allowing edition-specific customizations."
      echo ""
      echo "Files used:"
      if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
        echo "  - Template:  ../cosmos/compose.yaml.template"
        echo "  - Overrides: ./compose.enterprise.yaml"
        echo "  - Output:    ./compose.yaml"
      else
        echo "  - Template:  ./compose.yaml.template"
        echo "  - Overrides: ./compose.core.yaml"
        echo "  - Output:    ./compose.yaml"
      fi
      echo ""
      echo "How it works:"
      echo "  1. The template file contains placeholders like {{REGISTRY_VAR}}, {{IMAGE_PREFIX}}, etc."
      echo "  2. The override file defines the actual values for these placeholders"
      echo "  3. The script merges the template with the overrides to produce compose.yaml"
      echo ""
      echo "Options:"
      echo "  --dry-run             Print output to stdout instead of writing to file"
      echo "  --output PATH         Custom output file path (default: ./compose.yaml)"
      echo "  -h, --help            Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 generate_compose                    # Generate compose.yaml"
      echo "  $0 generate_compose --dry-run           # Preview without writing"
      echo "  $0 generate_compose --output /tmp/test.yaml  # Write to custom path"
      echo ""
      echo "Making changes:"
      echo "  - To change shared config:    Edit compose.yaml.template"
      echo "  - To change core-specific:    Edit compose.core.yaml"
      echo "  - To change enterprise-specific: Edit compose.enterprise.yaml"
      echo ""
      echo "After editing, regenerate compose.yaml for both core and enterprise."
      echo ""
      echo "Benefits:"
      echo "  - Single source of truth for shared configuration"
      echo "  - No manual syncing needed between core and enterprise"
      echo "  - Clear visibility of what's different between editions"
      echo "  - Automated generation prevents copy-paste errors"
      exit 0
    fi

    # Detect mode based on OPENC3_ENTERPRISE
    if [[ "$OPENC3_ENTERPRISE" -eq 1 ]]; then
      MODE="enterprise"
      # Enterprise uses the template from core repo
      SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
      if [[ -f "$SCRIPT_DIR/../cosmos/scripts/release/generate_compose.py" ]]; then
        GENERATOR="$SCRIPT_DIR/../cosmos/scripts/release/generate_compose.py"
        TEMPLATE="$SCRIPT_DIR/../cosmos/compose.yaml.template"
      else
        echo "Error: Cannot find generate_compose.py in ../cosmos/scripts/release/" >&2
        echo "Make sure the cosmos repository is checked out in the parent directory." >&2
        exit 1
      fi
    else
      MODE="core"
      GENERATOR="$(dirname -- "$0")/scripts/release/generate_compose.py"
      TEMPLATE=""  # Will use default (./compose.yaml.template)
    fi

    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
      echo "Error: python3 is required but not found" >&2
      echo "Please install Python 3 to use this command" >&2
      exit 1
    fi

    # Check if PyYAML is installed, install if missing
    if ! python3 -c "import yaml" &> /dev/null; then
      echo "PyYAML not found, installing..."
      if python3 -m pip install --user pyyaml &> /dev/null; then
        echo "✓ PyYAML installed successfully"
      else
        echo "Error: Failed to install PyYAML automatically" >&2
        echo "Please install it manually with: pip install pyyaml" >&2
        exit 1
      fi
    fi

    # Build arguments for the generator
    ARGS="--mode $MODE"

    # Add template path for enterprise
    if [[ -n "$TEMPLATE" ]]; then
      ARGS="$ARGS --template $TEMPLATE"
    fi

    # Pass through any additional arguments (like --dry-run, --output)
    shift  # Remove 'generate_compose' from args
    if [[ $# -gt 0 ]]; then
      ARGS="$ARGS $@"
    fi

    # Run the generator
    python3 "$GENERATOR" $ARGS
    ;;
  util )
    if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]] || [[ "$#" -eq 1 ]]; then
      echo "Usage: $0 util COMMAND [OPTIONS]"
      echo ""
      echo "Various $COSMOS_NAME utility commands."
      echo ""
      echo "Available commands:"
      echo "  encode STRING               Encode a string to base64"
      echo "  hash STRING                 Hash a string using SHA-256"
      echo "  save REPO NS TAG [SUFFIX]   Save docker images to tar files"
      echo "  load [TAG] [SUFFIX]         Load docker images from tar files"
      echo "  tag REPO1 REPO2 NS1 TAG1 [NS2] [TAG2] [SUFFIX]"
      echo "                              Tag images from one repo to another"
      echo "  push REPO NS TAG [SUFFIX]   Push images to docker repository"
      echo "  clean                       Remove node_modules, coverage, etc"
      echo "  hostsetup REPO NS TAG       Configure host for redis"
      echo "  hostenter                   Shell into VM host"
      echo ""
      echo "Run '$0 util COMMAND --help' for detailed help on each command."
      echo ""
      echo "Environment variables:"
      echo "  ENV_FILE                    Path to environment file (default: .env)"
      echo ""
      echo "Options:"
      echo "  -h, --help                  Show this help message"
      exit 0
    fi
    set -a
    . "$(dirname -- "$0")/${ENV_FILE:-.env}"
    "$(find_script openc3_util.sh)" "${@:2}"
    set +a
    ;;
  * )
    usage $0
    ;;
esac
