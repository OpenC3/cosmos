---
title: Extending COSMOS Containers
description: Add OS packages, gems, Python packages, and tools to the COSMOS images without forking them
sidebar_custom_props:
  myEmoji: 🧱
---

Sometimes a target needs software that isn't in the COSMOS images: a command line tool an interface shells out to, a system library a gem compiles against, Node.js for a custom microservice, or a vendor binary. This guide shows how to add it by building your own image **on top of** the official COSMOS image, and how to run that image with `./openc3.sh run`.

## Don't Edit the COSMOS Dockerfiles

It is tempting to add a line to `openc3/Dockerfile`, `openc3-ruby/Dockerfile`, or `openc3-operator/Dockerfile` in a clone of the COSMOS repository. Avoid this:

- **Upgrades get harder.** Most COSMOS releases change these Dockerfiles, so your edits conflict on every upgrade and have to be merged by hand.
- **You have to build all of COSMOS.** The images depend on each other (`openc3-ruby` → `openc3-base` → `openc3-operator`, ...), so a change near the bottom means rebuilding every image instead of pulling the released ones.
- **You lose the tested images.** The released images are built and tested together. A rebuilt chain can pick up different OS package versions.

Instead, write a small Dockerfile that starts `FROM` the released image and adds only what you need. COSMOS upgrades then just change the tag your Dockerfile builds from.

## First, Check Whether You Need a Custom Image

Many dependencies don't need a custom image at all, because plugins can bring their own:

| Dependency                                              | Recommended approach                                                                                                                                                                                                                                |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ruby gem                                                | Add it to your plugin's `.gemspec` with `s.add_runtime_dependency`. COSMOS installs it when the plugin is installed.                                                                                                                                |
| Python package                                          | Add it to your plugin's `pyproject.toml` or `requirements.txt`. COSMOS installs it into a virtual environment for the plugin. See [Plugins](/docs/configuration/plugins).                                                                           |
| Package mirror or proxy                                 | Change the **Rubygems URL** and **Pypi URL** settings in the Admin tool's Settings tab rather than baking a mirror into an image. `RUBYGEMS_URL` and `PYPI_URL` in `.env.local` only set the initial values of these settings on a new install.     |
| OS package, binary, or SDK                              | **Custom image** (this guide)                                                                                                                                                                                                                       |
| Gem with a native extension that needs a system library | Install build dependencies in custom `openc3-cosmos-cmd-tlm-api` and `openc3-cosmos-init` images, where plugin gems are compiled. Also install runtime libraries in every image that loads the gem. The gem itself can still come from your plugin. |
| Node.js / npm at runtime                                | **Custom image** (this guide). Custom tools and widgets don't need this, because they are built before the plugin is installed.                                                                                                                     |

Plugin dependencies are versioned and installed with your plugin, so they are the easier choice when they work. Use a custom image for anything that isn't a Ruby gem or Python package.

## Which Image to Extend

Add the dependency to the container where the code that needs it runs:

| Service                           | Runs                                                                   | Core image                                  | Enterprise image                                                              |
| --------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------- |
| `openc3-operator`                 | Interfaces, routers, and microservices                                 | `openc3inc/openc3-operator`                 | `openc3/openc3-enterprise-operator` (from `repos.openc3.com`)                 |
| `openc3-cosmos-script-runner-api` | Script Runner scripts                                                  | `openc3inc/openc3-cosmos-script-runner-api` | `openc3/openc3-cosmos-enterprise-script-runner-api` (from `repos.openc3.com`) |
| `openc3-cosmos-cmd-tlm-api`       | The REST API and plugin installs from the Admin tool                   | `openc3inc/openc3-cosmos-cmd-tlm-api`       | `openc3/openc3-cosmos-enterprise-cmd-tlm-api` (from `repos.openc3.com`)       |
| `openc3-cosmos-init`              | Plugin installs at startup (including `plugins/DEFAULT` in local mode) | `openc3inc/openc3-cosmos-init`              | `openc3/openc3-cosmos-enterprise-init` (from `repos.openc3.com`)              |

Most interface, router, and microservice runtime dependencies belong in `openc3-operator`. If scripts call the same tool, extend `openc3-cosmos-script-runner-api` as well.

Native gem build dependencies are an exception, because native extensions are compiled where plugins are installed:

- `openc3-cosmos-cmd-tlm-api` installs plugins from the Admin tool and `./openc3.sh cli load`.
- `openc3-cosmos-init` installs plugins at startup. With `OPENC3_LOCAL_MODE` set (the default), it installs any plugins saved in `plugins/DEFAULT` that aren't installed yet or have changed, for example on a new machine. A failed compile here doesn't stop COSMOS from starting, so check the `openc3-cosmos-init` logs if a plugin is missing.

Extend both images with the compiler, headers, and other build-time libraries. If the compiled extension dynamically links to a shared library at runtime, add that runtime library to every service that loads the gem, such as `openc3-operator` or `openc3-cosmos-script-runner-api`. The exact image names for your version are in the `image:` lines of your `compose.yaml`.

## Writing the Dockerfile

Create a directory for each image you extend in your COSMOS project, next to `compose.yaml`, e.g. `custom/openc3-operator/Dockerfile`:

```dockerfile
# Build arguments are passed in from compose.override.yaml so this always
# builds on the COSMOS version set by OPENC3_TAG in .env (or .env.local)
ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE_SUFFIX=
FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator${OPENC3_IMAGE_SUFFIX}:${OPENC3_TAG}

# The COSMOS images run as an unprivileged user, so switch to root to install
USER root

# OS packages (the default images are Debian based)
RUN apt-get update && \
    apt-get install -y --no-install-recommends iputils-ping && \
    rm -rf /var/lib/apt/lists/*

# Ruby gems
RUN gem install --no-document rubyserial

# Python packages, installed into the COSMOS Python environment
RUN uv pip install --no-cache --python /openc3/python/.venv/bin/python pyusb

# A vendor binary or SDK copied from the build context
# COPY vendor-tool /usr/local/bin/vendor-tool

# Switch back to the unprivileged COSMOS user
USER ${USER_ID}:${GROUP_ID}
```

Notes:

- Always end with `USER ${USER_ID}:${GROUP_ID}`. `USER_ID` and `GROUP_ID` are set by the COSMOS base image. Under Compose the container actually runs as the `user:` set in `compose.yaml` (`OPENC3_USER_ID` / `OPENC3_GROUP_ID`), so files you add must be readable by that user, not just by the image's default user.
- Don't change the `CMD` or `ENTRYPOINT`. The image has to start the same way the original did.
- Containers run with a read-only file system, so anything your code needs to write at runtime must go to `/tmp` or a volume you mount in `compose.override.yaml`, not into a directory you create in the image. `/gems` is mounted read-only in the operator and Script Runner containers.
- If you use the Red Hat UBI images (`OPENC3_IMAGE_SUFFIX=-ubi`), install OS packages with `microdnf install -y <package>` instead of `apt-get`. The Node.js example below only works with the default Debian images.
- In an air-gapped network, point `apt-get`, `gem`, and `uv` at your internal mirrors, or `COPY` the packages into the image and install them from files.

### Adding Node.js

To run Node.js code in the operator, copy Node.js from the official Node image instead of installing it with `apt-get`, which gives you a current Node.js version:

```dockerfile
ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE_SUFFIX=
FROM node:24-trixie-slim AS nodejs
FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-operator${OPENC3_IMAGE_SUFFIX}:${OPENC3_TAG}
USER root
COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
USER ${USER_ID}:${GROUP_ID}
```

Running `node` works as is. The home directory (`/openc3`) is read only at runtime, so if your code also runs `npm` or `npx` while COSMOS is running, set `npm_config_cache=/tmp/.npm` in its environment.

## Using the Custom Image

Tell Docker Compose to build and use your image in `compose.override.yaml`, which `openc3.sh` merges on top of `compose.yaml` automatically (see [Docker Compose](/docs/configuration/compose)). Leave `compose.yaml` itself unchanged so COSMOS upgrades don't conflict.

```yaml
services:
  openc3-operator:
    build:
      context: ./custom/openc3-operator
      args:
        OPENC3_REGISTRY: ${OPENC3_REGISTRY}
        OPENC3_NAMESPACE: ${OPENC3_NAMESPACE}
        OPENC3_TAG: ${OPENC3_TAG}
        OPENC3_IMAGE_SUFFIX: ${OPENC3_IMAGE_SUFFIX}
    # Use a name that is clearly yours so it never overwrites an official image.
    # Including the suffix keeps Debian and UBI builds of the same tag apart.
    image: "mycompany/openc3-operator-custom${OPENC3_IMAGE_SUFFIX}:${OPENC3_TAG}"
```

For COSMOS Enterprise, change the image name in the Dockerfile's `FROM` line to the Enterprise image (e.g. `openc3-enterprise-operator`) and pass the Enterprise variables into the same build arguments. Use `OPENC3_ENTERPRISE_TAG` in the image tag too:

```yaml
services:
  openc3-operator:
    build:
      context: ./custom/openc3-operator
      args:
        OPENC3_REGISTRY: ${OPENC3_ENTERPRISE_REGISTRY}
        OPENC3_NAMESPACE: ${OPENC3_ENTERPRISE_NAMESPACE}
        OPENC3_TAG: ${OPENC3_ENTERPRISE_TAG}
        OPENC3_IMAGE_SUFFIX: ${OPENC3_IMAGE_SUFFIX}
    image: "mycompany/openc3-enterprise-operator-custom${OPENC3_IMAGE_SUFFIX}:${OPENC3_ENTERPRISE_TAG}"
```

In the rest of this guide, read `OPENC3_TAG` as `OPENC3_ENTERPRISE_TAG` when using COSMOS Enterprise.

Then start COSMOS as usual:

```bash
./openc3.sh run
```

Compose builds the image the first time, because `mycompany/openc3-operator-custom:<tag>` doesn't exist yet, and then starts the operator from it. Compose may first try to pull the image and print a "pull access denied" warning; this is expected, and it builds the image afterward. Check that the dependency is there:

```bash
docker compose exec openc3-operator ping -V
```

### Rebuilding

Compose only builds the image automatically when it doesn't exist. Because the image tag includes `OPENC3_TAG`, upgrading COSMOS to a new version builds a new image on the new base automatically. After you change your Dockerfile, rebuild it yourself:

```bash
docker compose --env-file .env --env-file .env.local -f compose.yaml -f compose.override.yaml build openc3-operator
./openc3.sh run
```

Omit `--env-file .env.local` if you don't have a `.env.local`. When you are testing with the `latest` tag, add `--pull` to the build command to pick up a newer base image.

### Deploying to Other Machines

For an air-gapped network or a cluster, build the image once and push it to your own registry instead of building it on every machine. Replace `X.Y.Z` with your `OPENC3_TAG`, and omit `--env-file .env.local` if you don't have one:

```bash
docker compose --env-file .env --env-file .env.local -f compose.yaml -f compose.override.yaml build openc3-operator
docker tag mycompany/openc3-operator-custom:X.Y.Z registry.example.com/mycompany/openc3-operator-custom:X.Y.Z
docker push registry.example.com/mycompany/openc3-operator-custom:X.Y.Z
```

On the target machines, point `image:` in `compose.override.yaml` at `registry.example.com/mycompany/openc3-operator-custom:${OPENC3_TAG}` and remove the `build:` section.

#### Kubernetes (COSMOS Enterprise Helm Chart)

The Helm chart builds each image reference from `global.image.registry`, `global.image.namespace`, `global.image.names.<service>`, and `global.image.tag`, so push your image to the same registry, namespace, and tag as the other COSMOS images and set the matching name, e.g. `global.image.names.cmdTlmApi`, `global.image.names.scriptRunnerApi`, or `global.image.names.init`.

Where interfaces, routers, and microservices run depends on `operator.shards`:

- **`shards: 0` (the default):** the Kubernetes operator runs each interface, router, and microservice in its own pod using the `openc3-enterprise-gem` image, not the operator image, so `global.image.names.operator` doesn't affect them. Build your image `FROM` the `openc3-enterprise-gem` image instead, push it to a registry the cluster can pull from, and select it in `plugin.txt` by giving its full image reference to the [CONTAINER](/docs/configuration/plugins#container) keyword under the `INTERFACE`, `ROUTER`, or `MICROSERVICE`.
- **`shards: 1` or more:** interfaces, routers, and microservices run inside the operator pods, so set `global.image.names.operator` to your custom operator image.

## Upgrading COSMOS

Because your changes live in your own Dockerfile and `compose.override.yaml`:

1. Upgrade COSMOS as usual (see [Upgrading](/docs/getting-started/upgrading)), which changes `OPENC3_TAG` (`OPENC3_ENTERPRISE_TAG` for Enterprise).
2. Run `./openc3.sh run`. Compose sees that the image for the new tag doesn't exist and builds it on top of the new COSMOS image.

Occasionally a COSMOS release changes the base OS or Python version, which can break a package your Dockerfile installs. Check the release notes and rebuild in a test environment before upgrading operations.
