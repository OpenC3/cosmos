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

case $1 in
    install-playwright )
        # Attempt to clean up downloaded browser binaries
        #   https://playwright.dev/docs/ci#directories-to-cache
        [ -d $HOME/.cache/ms-playwright ] && rm -rf $HOME/.cache/ms-playwright # linux
        [ -d $HOME/Library/Caches/ms-playwright ] && rm -rf $HOME/Library/Caches/ms-playwright # mac

        rm -rf node_modules

        yarn; yarn playwright install --with-deps; yarn playwright --version

        ./reset_storage_state.sh
        ;;

    build-plugin )
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
        ./reset_storage_state.sh
        ;;

    run-chromium )
        yarn test
        ;;

    run-enterprise )
        yarn test:enterprise
        ;;

    run-aws )
        sed -i 's#http://localhost:2900#https://aws.openc3.com#' playwright.config.ts
        KEYCLOAK_URL=https://aws.openc3.com/auth REDIRECT_URL=https://aws.openc3.com/* yarn test:keycloak
        yarn test
        ;;
esac
