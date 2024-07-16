#!/bin/bash

# Define variables
REGISTRY="registry.ethos.labs:443"
IMAGE_SUFFIX="${OPENC3_IMAGE_SUFFIX:-}"
TAG="${OPENC3_TAG:-latest}"

# Define Dockerfiles and services
declare -A services
services=(
  ["openc3-minio"]="openc3-minio/Dockerfile"
  ["openc3-redis"]="openc3-redis/Dockerfile"
  ["openc3-cosmos-cmd-tlm-api"]="openc3-cosmos-cmd-tlm-api/Dockerfile"
  ["openc3-cosmos-script-runner-api"]="openc3-cosmos-script-runner-api/Dockerfile"
  ["openc3-operator"]="openc3-operator/Dockerfile"
  ["openc3-traefik"]="path/to/Dockerfile.traefik"
  ["openc3-cosmos-init"]="path/to/Dockerfile.init"
)

# Build and push images for each service
for service in "${!services[@]}"; do
  dockerfile="${services[$service]}"
  image="$REGISTRY/$service$IMAGE_SUFFIX:$TAG"

  echo "Building and pushing $image..."

  docker buildx build --push --platform linux/amd64,linux/arm64 -t "$image" -f "$dockerfile" . --output=type=registry,registry.insecure=true
  
  if [ $? -ne 0 ]; then
    echo "Failed to build and push $image"
    exit 1
  fi

  echo "Successfully built and pushed $image"
done

echo "All images have been built and pushed successfully."
