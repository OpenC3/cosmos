#!/bin/bash

usage() {
  echo "Usage: $1 [install-playwright, build-plugin, reset-storage-state, run-local, run-chromium]" >&2
  echo "*  install-playwright: installs playwright and its dependencies" >&2
  echo "*  build-plugin: builds the plugin to be used in the playwright tests" >&2
  echo "*  reset-storage-state: clear out cached data" >&2
  echo "*  run-chromium: runs the playwright tests against a locally running version of Cosmos using Chrome" >&2
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
        ../openc3.sh cli generate plugin PW_TEST
        cd openc3-cosmos-pw-test
        ../../openc3.sh cli generate target PW_TEST
        ../../openc3.sh cli rake build VERSION=1.0.0
        cp openc3-cosmos-pw-test-1.0.0.gem openc3-cosmos-pw-test-1.0.1.gem
        ../../openc3.sh cli validate openc3-cosmos-pw-test-1.0.0.gem
        ;;

    reset-storage-state )
        ./reset_storage_state.sh
        ;;

    run-chromium )
        yarn playwright test "${@:2}" --project=chromium
        ;;
esac
