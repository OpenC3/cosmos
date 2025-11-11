---
sidebar_position: 6
title: Utility Commands
description: Using openc3.sh util
sidebar_custom_props:
  myEmoji: ⌨️
---

The COSMOS Util is a command on `openc3.sh` and `openc3.bat` which are included in the COSMOS [project](https://github.com/OpenC3/cosmos-project) (more about [projects](key-concepts#projects)).

If you followed the [Installation Guide](installation.md) you should already be inside a cloned [cosmos-project](https://github.com/OpenC3/cosmos-project) which is in your PATH (necessary for openc3.bat / openc3.sh to be resolved).

:::note
The utility script automatically detects and uses either Docker or Podman. If Docker is not found, it will use Podman as a fallback. If neither is available, the script will exit with an error.
:::

To see all the available commands, type the following:

```zsh
❯ ./openc3.sh util
Usage: scripts/linux/openc3_util.sh [encode, hash, save, load, tag, push, clean, hostsetup]
*  encode: encode a string to base64
*  hash: hash a string using SHA-256
*  save: save images to a tar file
*  load: load images from a tar file
*  tag: tag images
*  push: push images
*  clean: remove node_modules, coverage, etc
*  hostsetup: configure host for redis
*  hostenter: sh into vm host
```

## Encode

Encode a string to base64. This is useful for encoding credentials or configuration values.

```zsh
❯ ./openc3.sh util encode foo
Zm9v
```

**Usage**: `encode <STRING>`

Parameters:
- `STRING`: The string to encode

## Hash

Hash a string using SHA-256. This is useful for generating checksums or verifying data integrity.

```zsh
❯ ./openc3.sh util hash foo
2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae
```

**Usage**: `hash <STRING>`

Parameters:
- `STRING`: The string to hash

## Save

Save images to tar file. This command pulls all COSMOS Docker images from the specified repository and saves them as tar files in the `tmp/` directory.

```zsh
❯ ./openc3.sh util save docker.io openc3inc 5.19.0
+ docker pull docker.io/openc3inc/openc3-ruby:5.19.0
+ docker pull docker.io/openc3inc/openc3-node:5.19.0
...
+ docker save docker.io/openc3inc/openc3-ruby:5.19.0 -o tmp/openc3-ruby-5.19.0.tar
...
```

**Usage**: `save <REPO> <NAMESPACE> <TAG> <SUFFIX>`

Parameters:
- `REPO`: Docker repository (e.g., docker.io)
- `NAMESPACE`: Image namespace (e.g., openc3inc)
- `TAG`: Image tag/version (e.g., 5.19.0)
- `SUFFIX`: (Optional) Image name suffix for custom builds

## Load

Load images from tar files in the `tmp/` directory. This command loads all COSMOS Docker images from previously saved tar files.

```zsh
❯ ./openc3.sh util load 5.19.0
+ docker load -i tmp/openc3-ruby-5.19.0.tar
+ docker load -i tmp/openc3-node-5.19.0.tar
...
```

**Usage**: `load <TAG> <SUFFIX>`

Parameters:
- `TAG`: (Optional) Image tag/version (defaults to "latest")
- `SUFFIX`: (Optional) Image name suffix for custom builds

Example loading latest:
```zsh
❯ ./openc3.sh util load
+ docker load -i tmp/openc3-ruby-latest.tar
...
```

## Tag

Tag images from one repository/namespace to another. This is useful for pushing images to a local registry or retagging for different deployments.

```zsh
❯ ./openc3.sh util tag docker.io localhost:12345 openc3inc latest
+ docker tag docker.io/openc3inc/openc3-ruby:latest localhost:12345/openc3inc/openc3-ruby:latest
+ docker tag docker.io/openc3inc/openc3-node:latest localhost:12345/openc3inc/openc3-node:latest
...
```

**Usage**: `tag <REPO1> <REPO2> <NAMESPACE1> <TAG1> <NAMESPACE2> <TAG2> <SUFFIX>`

Parameters:
- `REPO1`: Source repository (e.g., docker.io)
- `REPO2`: Destination repository (e.g., localhost:12345)
- `NAMESPACE1`: Source namespace (e.g., openc3inc)
- `TAG1`: Source tag (e.g., latest)
- `NAMESPACE2`: (Optional) Destination namespace (defaults to NAMESPACE1)
- `TAG2`: (Optional) Destination tag (defaults to TAG1)
- `SUFFIX`: (Optional) Image name suffix for custom builds

Example with different namespace and tag:
```zsh
❯ ./openc3.sh util tag docker.io localhost:12345 openc3inc latest mycompany 1.0.0
```

## Push

Push all COSMOS Docker images to a remote repository.

```zsh
❯ ./openc3.sh util push localhost:12345 openc3inc latest
+ docker push localhost:12345/openc3inc/openc3-ruby:latest
+ docker push localhost:12345/openc3inc/openc3-node:latest
...
```

**Usage**: `push <REPO> <NAMESPACE> <TAG> <SUFFIX>`

Parameters:
- `REPO`: Docker repository (e.g., localhost:12345)
- `NAMESPACE`: Image namespace (e.g., openc3inc)
- `TAG`: Image tag (e.g., latest)
- `SUFFIX`: (Optional) Image name suffix for custom builds

## Clean

Remove development artifacts and lock files from the repository. This command helps clean up your workspace.

What gets cleaned:
- All `node_modules` directories (removed automatically)
- All `coverage` directories (removed automatically)
- All `pnpm-lock.yaml` files (prompts for confirmation)
- All `Gemfile.lock` files (prompts for confirmation)

```zsh
❯ ./openc3.sh util clean
Removing ./openc3/node_modules
Removing ./openc3-cosmos-init/plugins/node_modules
...
remove ./pnpm-lock.yaml? y
remove ./openc3/Gemfile.lock? y
...
```

**Note**: This command will prompt you before removing lock files to prevent accidental deletion.

## Hostsetup

Configure the Docker/Podman host VM for Redis requirements. This command sets kernel parameters needed for optimal Redis performance.

This command configures:
- Disables transparent huge pages (THP)
- Sets `vm.max_map_count` to 262144

```zsh
❯ ./openc3.sh util hostsetup docker.io openc3inc latest
```

**Usage**: `hostsetup <REPO> <NAMESPACE> <TAG>`

Parameters:
- `REPO`: Docker repository containing the operator image
- `NAMESPACE`: Image namespace (e.g., openc3inc)
- `TAG`: Image tag (e.g., latest)

**Note**: This command requires privileged access and is typically run once during initial setup or when Redis warnings appear.

## Hostenter

Open a shell into the Docker/Podman host VM. This is useful for debugging and inspecting the host environment.

```zsh
❯ ./openc3.sh util hostenter
Unable to find image 'alpine:3.21.4' locally
3.21.4: Pulling from library/alpine
Digest: sha256:b6a6be0ff92ab6db8acd94f5d1b7a6c2f0f5d10ce3c24af348d333ac6da80685
Status: Downloaded newer image for alpine:3.21.4
sh-5.2# uname -a
Linux docker-desktop 6.10.4-linuxkit #1 SMP PREEMPT_DYNAMIC Thu Aug  8 14:33:14 UTC 2024 aarch64 Linux
sh-5.2# exit
```

**Usage**: `hostenter`

No parameters required.

**Environment Variables**:
- `OPENC3_DEPENDENCY_REGISTRY`: Registry for the Alpine image (defaults if not set)
- `ALPINE_VERSION`: Alpine Linux version
- `ALPINE_BUILD`: Alpine Linux build number

**Note**: This command requires privileged access and opens an interactive shell. Type `exit` to leave the host shell.
