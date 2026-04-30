# HCL bake overrides for CI builds.
#
# Layered on top of compose.yaml + compose-build.yaml in CI only:
#
#   docker buildx bake -f compose.yaml -f compose-build.yaml -f build-cache.hcl --load
#
# Two responsibilities:
#
#   1. Make `FROM ...` in dependent Dockerfiles resolve to the just-built bake
#      target instead of pulling the published image from the registry. This is
#      required because each bake target builds in the same BuildKit session
#      but the docker-container driver does not share the host docker daemon's
#      image store across separate buildx invocations.
#
#      BuildKit's named-context override matches against the *stage name* (or a
#      bare FROM identifier), not against full registry/namespace/image:tag
#      refs. Each dependent Dockerfile names its FROM stage `openc3-ruby`,
#      `openc3-node`, or `openc3-base`, and the contexts map below swaps that
#      stage out for the corresponding bake target.
#
#   2. Plumb GitHub Actions cache (type=gha) into the slow base images so
#      ruby/base/node layers persist across CI runs. Local developer builds
#      use compose without this file and avoid the GHA cache backend.

target "openc3-ruby" {
  cache-from = ["type=gha,scope=openc3-ruby"]
  cache-to   = ["type=gha,scope=openc3-ruby,mode=max"]
}

target "openc3-base" {
  contexts = {
    openc3-ruby = "target:openc3-ruby"
  }
  cache-from = ["type=gha,scope=openc3-base"]
  cache-to   = ["type=gha,scope=openc3-base,mode=max"]
}

target "openc3-node" {
  contexts = {
    openc3-ruby = "target:openc3-ruby"
  }
  cache-from = ["type=gha,scope=openc3-node"]
  cache-to   = ["type=gha,scope=openc3-node,mode=max"]
}

target "openc3-cosmos-cmd-tlm-api" {
  contexts = {
    openc3-base = "target:openc3-base"
  }
}

target "openc3-cosmos-script-runner-api" {
  contexts = {
    openc3-base = "target:openc3-base"
  }
}

target "openc3-operator" {
  contexts = {
    openc3-base = "target:openc3-base"
  }
}

target "openc3-cosmos-init" {
  contexts = {
    openc3-node = "target:openc3-node"
    openc3-base = "target:openc3-base"
  }
}
