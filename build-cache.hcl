# HCL bake overrides for CI builds.
#
# Layered on top of compose.yaml + compose-build.yaml in CI only:
#
#   docker buildx bake -f compose.yaml -f compose-build.yaml -f build-cache.hcl --load
#
# Two responsibilities:
#
#   1. Make `FROM <registry>/<ns>/<base>:<tag>` in dependent Dockerfiles resolve
#      to the just-built bake target instead of pulling from the registry.
#      Required for `docker buildx bake` because each target builds in the same
#      BuildKit session but the docker-container driver does not share the host
#      docker daemon's image store between sequential `buildx build` calls.
#      HCL is used here (not YAML) because compose only interpolates env vars
#      in map values, not in map keys — and we need the env vars in the key to
#      match the FROM line after build-arg substitution.
#
#   2. Plumb GitHub Actions cache (type=gha) into the slow base images so
#      ruby/base/node layers persist across CI runs. Local developer builds
#      use compose without this file and avoid the GHA cache backend.

variable "OPENC3_REGISTRY" {
  default = "docker.io"
}
variable "OPENC3_NAMESPACE" {
  default = "openc3inc"
}
variable "OPENC3_TAG" {
  default = "latest"
}

target "openc3-ruby" {
  cache-from = ["type=gha,scope=openc3-ruby"]
  cache-to   = ["type=gha,scope=openc3-ruby,mode=max"]
}

target "openc3-base" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}" = "target:openc3-ruby"
  }
  cache-from = ["type=gha,scope=openc3-base"]
  cache-to   = ["type=gha,scope=openc3-base,mode=max"]
}

target "openc3-node" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}" = "target:openc3-ruby"
  }
  cache-from = ["type=gha,scope=openc3-node"]
  cache-to   = ["type=gha,scope=openc3-node,mode=max"]
}

target "openc3-cosmos-cmd-tlm-api" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base:${OPENC3_TAG}" = "target:openc3-base"
  }
}

target "openc3-cosmos-script-runner-api" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base:${OPENC3_TAG}" = "target:openc3-base"
  }
}

target "openc3-operator" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base:${OPENC3_TAG}" = "target:openc3-base"
  }
}

target "openc3-cosmos-init" {
  contexts = {
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-node:${OPENC3_TAG}" = "target:openc3-node"
    "${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-base:${OPENC3_TAG}" = "target:openc3-base"
  }
}
