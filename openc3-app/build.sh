#!/usr/bin/env bash
#
# Host entry point for building the OpenC3 COSMOS native app. All compilation
# happens inside the Docker build environment so the host only needs Docker.
#
# Usage:
#   ./build.sh                 # build all supported targets
#   ./build.sh TARGET [...]    # build specific target(s)
#
# Optional environment:
#   MACOS_SDK=/path/to/MacOSX.sdk   Mount a macOS SDK to enable macOS targets.
#                                   On macOS this defaults to the Command Line
#                                   Tools SDK when present.
#
# Outputs land in ./dist/<target>/.

set -euo pipefail

cd "$(dirname "$0")"

IMAGE=openc3-app-builder

echo "Building Docker build environment image ($IMAGE)..."
docker build -f docker/Dockerfile.build -t "$IMAGE" .

RUN_ARGS=(--rm -v "$PWD":/work -w /work)

# Cache cargo registry across runs.
docker volume inspect openc3-app-cargo-registry >/dev/null 2>&1 \
  || docker volume create openc3-app-cargo-registry >/dev/null
RUN_ARGS+=(-v openc3-app-cargo-registry:/usr/local/cargo/registry)

# On macOS, default the SDK to the Command Line Tools SDK so the apple-darwin
# targets build without requiring MACOS_SDK to be set manually.
if [[ -z "${MACOS_SDK:-}" && "$(uname -s)" == "Darwin" ]]; then
  default_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
  if [[ -d "$default_sdk" ]]; then
    MACOS_SDK="$default_sdk"
    echo "Defaulting MACOS_SDK to $MACOS_SDK"
  fi
fi

# Provide a macOS SDK (if available) to enable the apple-darwin targets.
if [[ -n "${MACOS_SDK:-}" ]]; then
  RUN_ARGS+=(-v "$MACOS_SDK":/opt/macos-sdk:ro -e SDKROOT=/opt/macos-sdk)
fi

echo "Running cross build inside Docker..."
docker run "${RUN_ARGS[@]}" "$IMAGE" "$@"

echo
echo "Done. Executables are in ./dist/"
