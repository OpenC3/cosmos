#!/bin/bash

# Define available images
AVAILABLE_IMAGES=(
  "openc3-ruby-ubi"
  "openc3-base-ubi"
  "openc3-node-ubi"
  "openc3-minio-ubi"
  "openc3-redis-ubi"
  "openc3-tsdb-ubi"
  "openc3-cosmos-cmd-tlm-api-ubi"
  "openc3-cosmos-script-runner-api-ubi"
  "openc3-operator-ubi"
  "openc3-traefik-ubi"
  "openc3-cosmos-init-ubi"
)

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  echo "Usage: openc3_build_ubi.sh [IMAGE_NAME...]"
  echo ""
  echo "Builds OpenC3 UBI (Universal Base Image) containers for enterprise deployments."
  echo ""
  echo "This script builds all OpenC3 services using Red Hat UBI base images,"
  echo "suitable for air-gapped and government environments."
  echo ""
  echo "Arguments:"
  echo "  IMAGE_NAME    One or more image names to build (optional)"
  echo "                If no images are specified, all images will be built"
  echo ""
  echo "Available images:"
  for img in "${AVAILABLE_IMAGES[@]}"; do
    echo "  - $img"
  done
  echo ""
  echo "Environment variables required:"
  echo "  OPENC3_UBI_REGISTRY      - UBI registry URL"
  echo "  OPENC3_UBI_IMAGE         - UBI image name"
  echo "  OPENC3_UBI_TAG           - UBI image tag"
  echo "  OPENC3_REGISTRY          - Target registry for built images"
  echo "  OPENC3_NAMESPACE         - Target namespace"
  echo "  OPENC3_TAG               - Tag for built images"
  echo "  RUBYGEMS_URL             - RubyGems mirror URL (optional)"
  echo "  PYPI_URL                 - PyPI mirror URL (optional)"
  echo "  NPM_URL                  - NPM registry URL (optional)"
  echo ""
  echo "Options:"
  echo "  -h, --help    Show this help message"
  echo ""
  echo "Examples:"
  echo "  openc3_build_ubi.sh                           # Build all images"
  echo "  openc3_build_ubi.sh openc3-ruby-ubi           # Build only openc3-ruby-ubi"
  echo "  openc3_build_ubi.sh openc3-ruby-ubi openc3-base-ubi  # Build multiple images"
  exit 0
fi

set -e

# Save the script's starting directory for use in helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Parse command line arguments to determine which images to build
IMAGES_TO_BUILD=()
if [ $# -eq 0 ]; then
  # No arguments provided, build all images
  IMAGES_TO_BUILD=("${AVAILABLE_IMAGES[@]}")
  echo "No images specified, building all images..."
else
  # Validate provided image names
  for arg in "$@"; do
    # Check if the image is in the available list
    if [[ " ${AVAILABLE_IMAGES[@]} " =~ " ${arg} " ]]; then
      IMAGES_TO_BUILD+=("$arg")
    else
      echo "Error: Unknown image '${arg}'"
      echo "Available images:"
      for img in "${AVAILABLE_IMAGES[@]}"; do
        echo "  - $img"
      done
      exit 1
    fi
  done
  echo "Building specified images: ${IMAGES_TO_BUILD[@]}"
fi

if ! command -v docker &> /dev/null
then
  if command -v podman &> /dev/null
  then
    function docker() {
      podman $@
    }

    # Check if logged into Podman registry
    if ! podman login --get-login "$OPENC3_UBI_REGISTRY" &> /dev/null; then
      echo "Not logged into Podman registry: $OPENC3_UBI_REGISTRY"
      echo "Please login to continue..."
      if ! podman login "$OPENC3_UBI_REGISTRY"; then
        echo "Failed to login to registry!"
        exit 1
      fi
    else
      echo "Already logged into registry: $OPENC3_UBI_REGISTRY"
    fi
  else
    echo "Neither docker nor podman found!!!"
    exit 1
  fi
fi

# Handle restrictive umasks - Built files need to be world readable
umask 0022
# Make directory and files readable for Docker build context
# Use || true to continue even if chmod fails (e.g. SELinux, permission issues)
chmod -R +r . 2>/dev/null || echo "Warning: Could not set all files readable (this is usually harmless)"

# Helper function to check if an image should be built
should_build() {
  local image_name="$1"
  [[ " ${IMAGES_TO_BUILD[@]} " =~ " ${image_name} " ]]
}

# Helper function to format duration in human-readable format
format_duration() {
  local total_seconds=$1
  local minutes=$((total_seconds / 60))
  local seconds=$((total_seconds % 60))
  if [ $minutes -gt 0 ]; then
    echo "${minutes}m ${seconds}s"
  else
    echo "${seconds}s"
  fi
}

# Arrays to track build times for final report
declare -a BUILT_IMAGES=()
declare -a BUILD_TIMES=()

# Helper function to record build completion
record_build() {
  local image_name="$1"
  local duration="$2"
  BUILT_IMAGES+=("$image_name")
  BUILD_TIMES+=("$duration")
}

# Helper function to prepare Ruby services for air-gapped builds
# This generates a Gemfile.lock without development/test gems to avoid
# dependency resolution failures in air-gapped environments
prepare_ruby_service() {
  local service_dir="$1"
  local abs_service_dir="${SCRIPT_DIR}/${service_dir}"
  echo "  Preparing Gemfile.lock for air-gapped build..."

  # Check if Gemfile exists
  if [ ! -f "$abs_service_dir/Gemfile" ]; then
    echo "  No Gemfile found, skipping preparation"
    return 0
  fi

  # Generate Gemfile.lock without dev/test gems
  # Set bundler version to match what's installed in openc3-ruby-ubi
  (cd "$abs_service_dir" && \
   bundle config set --local without 'development test' && \
   bundle lock --conservative --bundler=2.5.22 2>/dev/null || bundle lock --bundler=2.5.22) && \
  echo "  Generated Gemfile.lock without development/test gems"

  # Temporarily modify .dockerignore to include Gemfile.lock
  if [ -f "$abs_service_dir/.dockerignore" ]; then
    if grep -q "^Gemfile\.lock$" "$abs_service_dir/.dockerignore"; then
      cp "$abs_service_dir/.dockerignore" "$abs_service_dir/.dockerignore.bak"
      sed -i.tmp '/^Gemfile\.lock$/d' "$abs_service_dir/.dockerignore" && rm -f "$abs_service_dir/.dockerignore.tmp"
      echo "  Modified .dockerignore to include Gemfile.lock in build"
    fi
  fi
}

# Cleanup function for Ruby service preparation
cleanup_ruby_service() {
  local service_dir="$1"
  local abs_service_dir="${SCRIPT_DIR}/${service_dir}"

  # Restore .dockerignore if we backed it up
  if [ -f "$abs_service_dir/.dockerignore.bak" ]; then
    mv "$abs_service_dir/.dockerignore.bak" "$abs_service_dir/.dockerignore"
    echo "  Restored .dockerignore"
  fi

  # Remove generated Gemfile.lock
  if [ -f "$abs_service_dir/Gemfile.lock" ]; then
    rm -f "$abs_service_dir/Gemfile.lock"
    echo "  Removed generated Gemfile.lock"
  fi

  # Clean up bundle config
  (cd "$abs_service_dir" && bundle config unset without 2>/dev/null || true)
}

if should_build "openc3-ruby-ubi"; then
  echo "Building openc3-ruby-ubi..."
  START_TIME=$SECONDS
  cd openc3-ruby
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_UBI_REGISTRY=$OPENC3_UBI_REGISTRY \
    --build-arg OPENC3_UBI_IMAGE=$OPENC3_UBI_IMAGE \
    --build-arg OPENC3_UBI_TAG=$OPENC3_UBI_TAG \
    --build-arg RUBYGEMS_URL=$RUBYGEMS_URL \
    --build-arg PYPI_URL=$PYPI_URL \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-ruby-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-ruby-ubi" "$DURATION"
fi

if should_build "openc3-base-ubi"; then
  echo "Building openc3-base-ubi..."
  START_TIME=$SECONDS

  # Prepare Gemfile.lock for air-gapped build
  prepare_ruby_service "openc3"

  # Set trap to ensure cleanup even on error
  trap "cleanup_ruby_service 'openc3'" EXIT

  cd openc3
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --build-arg OPENC3_IMAGE=openc3-ruby-ubi \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base-ubi:${OPENC3_TAG}" \
    .
  cd ..

  # Cleanup after successful build
  trap - EXIT
  cleanup_ruby_service "openc3"

  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-base-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-base-ubi" "$DURATION"
fi

if should_build "openc3-node-ubi"; then
  echo "Building openc3-node-ubi..."
  START_TIME=$SECONDS
  cd openc3-node
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --build-arg NPM_URL=$NPM_URL \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-node-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-node-ubi" "$DURATION"
fi

if should_build "openc3-minio-ubi"; then
  echo "Building openc3-minio-ubi..."
  START_TIME=$SECONDS
  # NOTE: Ensure the release is on IronBank:
  # https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Fminio%252Fminio
  # NOTE: RELEASE.2023-10-16T04-13-43Z is the last MINIO release to support UBI8
  cd openc3-minio
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
    --build-arg OPENC3_MINIO_RELEASE=RELEASE.2025-10-15T17-29-55Z \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-minio-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-minio-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-minio-ubi" "$DURATION"
fi

if should_build "openc3-redis-ubi"; then
  echo "Building openc3-redis-ubi..."
  START_TIME=$SECONDS
  cd openc3-redis
  docker build \
    --network host \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/redis \
    --build-arg OPENC3_REDIS_IMAGE=redis7 \
    --build-arg OPENC3_REDIS_VERSION="7.2.5" \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-redis-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-redis-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-redis-ubi" "$DURATION"
fi

if should_build "openc3-tsdb-ubi"; then
  echo "Building openc3-tsdb-ubi..."
  START_TIME=$SECONDS
  cd openc3-tsdb
  docker build \
    --network host \
    --build-arg OPENC3_TSDB_VERSION_EXT="-rhel" \
    --build-arg OPENC3_DEPENDENCY_REGISTRY="${OPENC3_DEPENDENCY_REGISTRY}" \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-tsdb-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-tsdb-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-tsdb-ubi" "$DURATION"
fi

if should_build "openc3-cosmos-cmd-tlm-api-ubi"; then
  echo "Building openc3-cosmos-cmd-tlm-api-ubi..."
  START_TIME=$SECONDS

  # Prepare Gemfile.lock for air-gapped build
  prepare_ruby_service "openc3-cosmos-cmd-tlm-api"

  # Set trap to ensure cleanup even on error
  trap "cleanup_ruby_service 'openc3-cosmos-cmd-tlm-api'" EXIT

  cd openc3-cosmos-cmd-tlm-api
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --build-arg OPENC3_IMAGE=openc3-base-ubi \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-cmd-tlm-api-ubi:${OPENC3_TAG}" \
    .
  cd ..

  # Cleanup after successful build
  trap - EXIT
  cleanup_ruby_service "openc3-cosmos-cmd-tlm-api"

  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-cosmos-cmd-tlm-api-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-cosmos-cmd-tlm-api-ubi" "$DURATION"
fi

if should_build "openc3-cosmos-script-runner-api-ubi"; then
  echo "Building openc3-cosmos-script-runner-api-ubi..."
  START_TIME=$SECONDS

  # Prepare Gemfile.lock for air-gapped build
  prepare_ruby_service "openc3-cosmos-script-runner-api"

  # Set trap to ensure cleanup even on error
  trap "cleanup_ruby_service 'openc3-cosmos-script-runner-api'" EXIT

  cd openc3-cosmos-script-runner-api
  docker build \
    -f Dockerfile-ubi \
    --network host \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --build-arg OPENC3_IMAGE=openc3-base-ubi \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-script-runner-api-ubi:${OPENC3_TAG}" \
    .
  cd ..

  # Cleanup after successful build
  trap - EXIT
  cleanup_ruby_service "openc3-cosmos-script-runner-api"

  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-cosmos-script-runner-api-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-cosmos-script-runner-api-ubi" "$DURATION"
fi

if should_build "openc3-operator-ubi"; then
  echo "Building openc3-operator-ubi..."
  START_TIME=$SECONDS
  cd openc3-operator
  docker build \
    --network host \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --build-arg OPENC3_IMAGE=openc3-base-ubi \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-operator-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-operator-ubi" "$DURATION"
fi

if should_build "openc3-traefik-ubi"; then
  echo "Building openc3-traefik-ubi..."
  START_TIME=$SECONDS
  if [[ -z $TRAEFIK_CONFIG ]]; then
    export TRAEFIK_CONFIG=traefik.yaml
  fi
  # NOTE: Ensure OPENC3_TRAEFIK_RELEASE is on IronBank:
  # https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Ftraefik%252Ftraefik
  # 3.5.4 is the latest 3.5.x version on IronBank as of Nov 11 2025
cd openc3-traefik
  docker build \
    --network host \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource/traefik \
    --build-arg TRAEFIK_CONFIG=$TRAEFIK_CONFIG \
    --build-arg OPENC3_TRAEFIK_RELEASE=v3.5.4 \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-traefik-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-traefik-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-traefik-ubi" "$DURATION"
fi

if should_build "openc3-cosmos-init-ubi"; then
  echo "Building openc3-cosmos-init-ubi..."
  START_TIME=$SECONDS
  # NOTE: Ensure OPENC3_MC_RELEASE is on IronBank:
  # https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Fminio%252Fmc
  # NOTE: RELEASE.2023-10-14T01-57-03Z is the last MINIO/MC release to support UBI8
  cd openc3-cosmos-init
  docker build \
    --network host \
    --build-context docs=../docs.openc3.com \
    --build-arg NPM_URL=$NPM_URL \
    --build-arg OPENC3_DEPENDENCY_REGISTRY=${OPENC3_UBI_REGISTRY}/ironbank/opensource \
    --build-arg OPENC3_MC_RELEASE=RELEASE.2025-08-13T08-35-41Z \
    --build-arg OPENC3_BASE_IMAGE=openc3-base-ubi \
    --build-arg OPENC3_NODE_IMAGE=openc3-node-ubi \
    --build-arg OPENC3_REGISTRY=$OPENC3_REGISTRY \
    --build-arg OPENC3_NAMESPACE=$OPENC3_NAMESPACE \
    --build-arg OPENC3_TAG=$OPENC3_TAG \
    --platform linux/amd64 \
    -t "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-cosmos-init-ubi:${OPENC3_TAG}" \
    .
  cd ..
  DURATION=$((SECONDS - START_TIME))
  echo "✓ openc3-cosmos-init-ubi completed in $(format_duration $DURATION)"
  record_build "openc3-cosmos-init-ubi" "$DURATION"
fi

podman image prune -f

# Generate final build report
echo ""
echo "========================================"
echo "       BUILD SUMMARY REPORT"
echo "========================================"
echo ""

if [ ${#BUILT_IMAGES[@]} -eq 0 ]; then
  echo "No images were built."
else
  echo "Images built: ${#BUILT_IMAGES[@]}"
  echo ""

  # Calculate total time
  TOTAL_TIME=0
  for time in "${BUILD_TIMES[@]}"; do
    TOTAL_TIME=$((TOTAL_TIME + time))
  done

  # Display individual build times
  echo "Individual build times:"
  echo "----------------------------------------"
  for i in "${!BUILT_IMAGES[@]}"; do
    printf "  %-40s %s\n" "${BUILT_IMAGES[$i]}" "$(format_duration ${BUILD_TIMES[$i]})"
  done

  echo "----------------------------------------"
  echo "Total build time: $(format_duration $TOTAL_TIME)"
fi

echo ""
echo "========================================"
