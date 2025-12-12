#!/bin/bash

usage() {
  echo "Usage: $1 [install-playwright, build-plugin, reset-storage-state, run-chromium, run-aws]" >&2
  echo "*  install-playwright: installs playwright and its dependencies" >&2
  echo "*  build-plugin: builds the plugin to be used in the playwright tests" >&2
  echo "*  reset-storage-state: clear out cached data" >&2
  echo "*  run-chromium: runs the playwright tests against a locally running version of Cosmos using Chrome" >&2
  echo "*  run-enterprise: runs the enterprise playwright tests against a locally running version of Cosmos using Chrome" >&2
  echo "*  run-aws: runs the playwright tests against a remotely running version of Cosmos using Chrome" >&2
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
    install-playwright )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 install-playwright"
            echo ""
            echo "Install Playwright and its dependencies."
            echo ""
            echo "This command:"
            echo "  - Removes cached Playwright browser binaries"
            echo "  - Removes node_modules directory"
            echo "  - Runs pnpm install with frozen lockfile"
            echo "  - Installs Playwright browsers with dependencies"
            echo "  - Resets storage state"
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            exit 0
        fi
        # Attempt to clean up downloaded browser binaries
        #   https://playwright.dev/docs/ci#directories-to-cache
        [ -d $HOME/.cache/ms-playwright ] && rm -rf $HOME/.cache/ms-playwright # linux
        [ -d $HOME/Library/Caches/ms-playwright ] && rm -rf $HOME/Library/Caches/ms-playwright # mac

        rm -rf node_modules

        pnpm install --frozen-lockfile --ignore-scripts; pnpm exec playwright install --with-deps; pnpm playwright --version

        ./reset_storage_state.sh
        ;;

    build-plugin )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 build-plugin"
            echo ""
            echo "Build the test plugin used in Playwright tests."
            echo ""
            echo "This command:"
            echo "  - Generates a PW_TEST plugin using openc3cli"
            echo "  - Generates a PW_TEST target"
            echo "  - Builds plugin gems (version 1.0.0 and 1.0.1)"
            echo "  - Validates the plugin gem"
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            exit 0
        fi
        rm -rf openc3-cosmos-pw-test
        ../openc3.sh cli generate plugin PW_TEST --ruby
        cd openc3-cosmos-pw-test
        ../../openc3.sh cli generate target PW_TEST --ruby
        ../../openc3.sh cli rake build VERSION=1.0.0
        cp openc3-cosmos-pw-test-1.0.0.gem openc3-cosmos-pw-test-1.0.1.gem
        ../../openc3.sh cli validate openc3-cosmos-pw-test-1.0.0.gem
        cd -
        ;;

    reset-storage-state )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 reset-storage-state"
            echo ""
            echo "Clear out cached Playwright storage state."
            echo ""
            echo "This resets authentication and other cached browser state"
            echo "used during Playwright tests."
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            exit 0
        fi
        ./reset_storage_state.sh
        ;;

    run-chromium )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 run-chromium [PLAYWRIGHT_OPTIONS]"
            echo ""
            echo "Run Playwright tests using Chrome against a local OpenC3 instance."
            echo ""
            echo "This runs the test suite defined in the playwright configuration."
            echo "OpenC3 must be running locally at http://localhost:2900"
            echo ""
            echo "Examples:"
            echo "  $0 run-chromium                 # Run all tests"
            echo "  $0 run-chromium --headed        # Run with visible browser"
            echo "  $0 run-chromium --debug         # Run in debug mode"
            echo ""
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  PLAYWRIGHT_OPTIONS      Additional Playwright CLI options"
            echo ""
            echo "See: https://playwright.dev/docs/test-cli"
            exit 0
        fi
        pnpm test
        ;;

    run-enterprise )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 run-enterprise"
            echo ""
            echo "Run enterprise Playwright tests."
            echo ""
            echo "This runs the enterprise test suite against a locally"
            echo "running OpenC3 Enterprise instance."
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            exit 0
        fi
        pnpm test:enterprise
        ;;

    run-aws )
        if [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
            echo "Usage: $0 run-aws"
            echo ""
            echo "Run Playwright tests against AWS-hosted OpenC3."
            echo ""
            echo "This command:"
            echo "  - Configures tests for https://aws.openc3.com"
            echo "  - Runs Keycloak authentication tests"
            echo "  - Runs enterprise test suite"
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            exit 0
        fi
        sed -i 's#http://localhost:2900#https://aws.openc3.com#' playwright.config.ts
        KEYCLOAK_URL=https://aws.openc3.com/auth/admin/master/console REDIRECT_URL=https://aws.openc3.com/* pnpm test:keycloak
        pnpm test:enterprise
        ;;
esac
