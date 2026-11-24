---
sidebar_position: 2
title: Plugins
description: Plugin definition file format and keywords
sidebar_custom_props:
  myEmoji: 🔌
---

{/* Be sure to edit _plugins.md because plugins.md is a generated file */}

## Introduction

This document provides the information necessary to configure a COSMOS plugin. Plugins are how you configure and extend COSMOS.

Plugins are where you define [Targets](./target.md) (and their corresponding command and telemetry packet definitions), [Interfaces](/docs/configuration/interfaces.md) needed to talk to targets, [Routers](/docs/configuration/interfaces.md) to stream raw data out of COSMOS, Microservices to provide new functionality, Widgets and Tools to add new GUIs, and Script Engines to implement custom script languages.

Plugin [Targets](/docs/configuration/target.md) must be installed (or re-installed) to update commands, telemetry, conversions, limits responses, microservices, and anything that changes the structure of a packet or contains code (conversions, limits responses, etc). Certain aspects of a Target can be changed through APIs like limits but most require reinstalling the Target. Note that COSMOS also supports [Dynamic Packets](/docs/guides/dynamic-packets) but this is meant for use during COSMOS plugin initialization rather than while running.

Each plugin is built as a Ruby gem and thus has a plugin.gemspec file which builds it. Plugins have a plugin.txt file which declares all the variables used by the plugin and how to interface to the target(s) it contains.

## Concepts

### Target

Targets are the external pieces of hardware and/or software that COSMOS communicates with. These are things like Front End Processors (FEPs), ground support equipment (GSE), custom software tools, and pieces of hardware like satellites themselves. A target is anything that COSMOS can send commands to and receive telemetry from.

### Interface

Interfaces implement the physical connection to one or more targets. They are typically ethernet connections implemented using TCP or UDP but can be other connections like serial ports. Interfaces send commands to targets and receive telemetry from targets.

### Router

Routers flow streams of telemetry packets out of COSMOS and receive streams of commands into COSMOS. The commands are forwarded by COSMOS to associated interfaces. Telemetry comes from associated interfaces.

### Widgets

COSMOS Widgets are GUI elements that can be placed on [Screens](/docs/configuration/telemetry-screens.md) in [Telemetry Viewer](/docs/tools/tlm-viewer.md).

### Tool

COSMOS Tools are web-based applications the communicate with the COSMOS APIs to perform takes like displaying telemetry, sending commands, and running scripts.

### Microservice

Microservices are persistent running backend code that runs within the COSMOS environment. They can process data and perform other useful tasks.

### Script Engines

Script Engines enhance Script Runner by providing the implementation of a new file type and language. The new language must be implemented in either Ruby or Python but can support any custom Domain Specific Language (DSL). For a real example see our [CSTOL](https://github.com/OpenC3/openc3-cosmos-script-engine-cstol) implementation.

## Installation Process

Plugin installation happens in two phases via the Admin Plugins tab or the `./openc3.sh cli load` command.

### Phase 1: Extract Variables

COSMOS uploads the plugin gem file to an internal gem server and extracts the gem contents to a temporary directory. It then reads and parses the `plugin.txt` file to extract all `VARIABLE` definitions along with their descriptions and options. These variables are returned to the Admin Plugins UI where the user can set values before proceeding to Phase 2.

### Phase 2: Deploy

Once variables are set, COSMOS registers the plugin model in Redis and installs the Ruby gem. If the plugin contains Python dependencies (`pyproject.toml` or `requirements.txt`), COSMOS creates an isolated [UV](https://docs.astral.sh/uv/) virtual environment for the plugin at `/gems/plugin_venvs/<plugin>/.venv` and installs the dependencies into it. This gives each plugin full dependency isolation — different plugins can require different versions of the same package without conflicts.

COSMOS supports two formats for declaring Python dependencies:

- **`pyproject.toml`** (recommended) — When paired with a `uv.lock` file, enables reproducible installs via `uv sync --frozen`. COSMOS uses `uv sync` for `pyproject.toml`-based plugins.
- **`requirements.txt`** — COSMOS uses `uv pip install -r requirements.txt` for requirements-based plugins. It has no lock file, so it can't use [`offline_install`](#offline-installs-with-bundled-wheels).

Both files are processed with [ERB](/docs/configuration/format#erb) using the plugin variables before installation, so variables can select which dependencies are installed. ERB code can read files shipped next to the dependency file with `File.dirname(__FILE__)`. For example, a `requirements.txt` that installs only the driver for the selected device:

```
<%- require 'json' -%>
<%= JSON.parse(File.read(File.join(File.dirname(__FILE__), 'drivers.json')))[device_type].join("\n") %>
```

A `uv.lock` is used as-is, so a plugin whose `pyproject.toml` dependencies depend on variables should not ship a `uv.lock`.

System Python packages (those shipped in the COSMOS Docker image) are pre-seeded into the UV download cache, so plugins that depend on those packages reuse them without re-downloading. If the UV install fails for any reason, COSMOS falls back to a shared pip install and logs a warning. A plugin built with [`offline_install`](#offline-installs-with-bundled-wheels) skips that fallback: the shared install would need a package index, so COSMOS logs an error instead.

Dependencies are resolved against the `pypi_url` Admin Console setting, falling back to the `PYPI_URL` environment variable and then to public PyPI. When that setting names an index other than `https://pypi.org`, COSMOS treats it as authoritative and passes uv `--no-config --no-sources`, so a plugin cannot resolve around it using an index declared in its own `[tool.uv].index` table or a `[tool.uv].sources` pin. A plugin depending on a package published only to its author's private index therefore fails to install unless your index serves that package too.

This applies only to the paths where uv resolves — `requirements.txt` plugins, and `pyproject.toml` plugins with no `uv.lock`. A plugin shipping a `uv.lock` installs with `uv sync --frozen`, which reuses the registry and wheel URLs already recorded in that lock and never consults an index, so a locked plugin still downloads from whatever index its author locked against.

Shipping a `uv.lock` is still recommended, including for air-gapped deployments. COSMOS first tries `uv sync --frozen` offline against its seeded package cache. If the URLs recorded in the lock are unreachable, for example because they point at public PyPI from an air-gapped network, COSMOS falls back to resolving the plugin's `pyproject.toml` against the configured `pypi_url` index, so the install still succeeds as long as that index serves the packages. This fallback ignores the versions pinned in `uv.lock`. To keep those pins in an air-gapped deployment, generate the lock against the same mirror, e.g. `uv lock --no-config --no-sources --default-index <mirror-url>`, so the recorded URLs point at an index the deployment can reach.

#### Offline installs with bundled wheels

<span class="badge badge--secondary since-heading">Since _Coming Soon_</span>

A deployment with no index at all can install a plugin's Python dependencies from wheels bundled inside the plugin gem. Opt in from the plugin's `pyproject.toml`:

```toml
[tool.openc3]
offline_install = true
# Optional. By default the wheels target the machine running the build.
python_platforms = ["x86_64-manylinux_2_28", "aarch64-manylinux_2_28"]
python_version = "3.13"
```

Bundling is opt-in because every wheel adds to the gem's size. A dependency such as `torch` can add gigabytes, so only enable it when the deployment can't reach PyPI or a mirror.

When the plugin is built, the Rakefile runs [`cli bundlewheels`](/docs/getting-started/cli#bundle-wheels) before `gem build`. The build needs network access, and it:

1. Fails unless `uv.lock` exists and matches `pyproject.toml` (`uv lock --check`).
1. Lets uv choose the wheel for every locked runtime dependency on each target platform. uv evaluates environment markers and wheel tags for that platform.
1. Downloads exactly those wheels from the URLs recorded in `uv.lock` into `python_wheels/` and checks each one against the sha256 in `uv.lock`. It also writes `python_wheels/SHA256SUMS`.
1. Installs from `python_wheels/` alone, offline, for each target to prove the bundle is complete.

If the build stops, the message names the fix:

| Build error | Fix |
| --- | --- |
| `offline_install requires a uv.lock` | Run `openc3.sh cli lock` in the plugin directory. |
| `uv.lock is out of date with pyproject.toml` | `pyproject.toml` changed after the last lock, for example a dependency was added by hand. Run `openc3.sh cli lock` to update `uv.lock`. |
| `Could not find a compatible wheel for every locked package for <platform>` | A dependency publishes no wheel for that platform or Python version (only a source distribution, or no build for that architecture). Pick a version that ships one, or drop that platform from `python_platforms`. |
| `offline_install can only bundle packages locked from a package index` | A dependency is locked from a URL, git repository or local path, for example `name @ https://...`. An offline install can only take wheels from the bundle for packages locked from an index, so publish the package to an index or a find-links directory, depend on it by name, and run `openc3.sh cli lock`. |
| `Could not download ... HTTP 401` or `HTTP 403` | The index that serves the wheels requires credentials. The build downloads the locked wheels without credentials, so it can't bundle from such an index yet. |
| `python_platforms also needs python_version` | Add `python_version`, set to the deployment's Python, such as `"3.13"`. |
| `python_version 3.10 is older than the plugin's requires-python` | `uv.lock` only covers the Python versions `requires-python` in `[project]` allows. Set `python_version` to the deployment's Python, such as `"3.13"`. |
| `python_version must be a Python version such as "3.13"` | Give a major and minor version, such as `"3.13"`. |
| `python3 (3.11 or newer) is required to read .../pyproject.toml` | The build ran outside the COSMOS image without a new enough Python. Install Python 3.11 or newer so `python3` is on `PATH`, or build with `openc3.sh cli rake build`. |

To create or update `uv.lock`, run [`openc3.sh cli lock`](/docs/getting-started/cli#lock) in the plugin directory. It runs uv in the COSMOS image, so you don't need uv installed. Add `--build VERSION` to rebuild the gem in the same step. Locking needs network access to the package index, just like the build. uv resolves against the index in the plugin's `[tool.uv]` settings, or else the `PYPI_URL` the COSMOS image was built with. If you do have [uv](https://docs.astral.sh/uv/getting-started/installation/) installed, `uv lock` and `uv add <package>` work as well.

Building outside the COSMOS image, for example with a locally installed `rake build`, needs uv and `python3` 3.11 or newer on `PATH`. COSMOS uses `python3` to read `pyproject.toml`. `openc3.sh cli rake build` already has both.

To check a built gem later, for example against a deployment's platform before shipping it, run [`cli verifywheels`](/docs/getting-started/cli#verify-wheels). It prints a per-target report of the wheel serving each package and its hash check.

##### Updating dependencies

To change a dependency, edit `pyproject.toml`, then lock and build the next version:

```bash
% openc3.sh cli lock --build 1.0.1
```

Versions already in `uv.lock` stay as they are unless `pyproject.toml` no longer allows them. To move to newer versions, add `--upgrade-package <name>` (repeatable) or `--upgrade` for every dependency. Then upgrade the plugin in the Admin Console [Plugins tab](/docs/tools/admin#plugins) with the new gem.

##### Converting an existing plugin

A plugin generated before COSMOS supported `offline_install` needs a few files updated before it can bundle wheels. Compare with a newly generated plugin (`openc3.sh cli generate plugin NAME --python`) if yours has drifted from the template.

1. List the Python dependencies in `pyproject.toml`. A plugin with only a `requirements.txt` must move them to the `dependencies` list in `[project]`, because `offline_install` is read from `pyproject.toml` and the wheels are bundled from `uv.lock`. Then add the `[tool.openc3]` table shown above.
1. In the `Rakefile`, run `openc3cli bundlewheels` before `gem build`:

   ```ruby
   # Bundle the locked Python wheels into python_wheels/ when pyproject.toml sets
   # [tool.openc3] offline_install, so the gem installs on an air-gapped COSMOS.
   if File.exist?('pyproject.toml')
     sh('openc3cli bundlewheels')
   end

   sh('gem', 'build', PLUGIN_NAME)
   ```

1. In the gemspec, package the lock and the wheels by adding them to `s.files`:

   ```ruby
   s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile README.md LICENSE.md plugin.txt) +
     Dir.glob("{pyproject.toml,uv.lock}") + Dir.glob("python_wheels/*")
   ```

   Install rejects an `offline_install` gem that lacks `uv.lock` or `python_wheels/`.

1. Add `python_wheels/` to `.gitignore`. The build recreates it each time.
1. Lock and build, then check the gem against the COSMOS image:

   ```bash
   % openc3.sh cli lock --build 1.1.0
   % openc3.sh cli verifywheels openc3-cosmos-my-plugin-1.1.0.gem
   ```

1. Upgrade the plugin in the Admin Console [Plugins tab](/docs/tools/admin#plugins) with the new gem. Its Python dependencies now install from the bundled wheels.

The gem ships `uv.lock` next to the wheels, so security scanners that read `uv.lock` cover every bundled package, and the bundled versions are exactly the locked ones.

At install, COSMOS rejects a gem that sets `offline_install` but has no `uv.lock` or `python_wheels/`. Otherwise it copies the wheels to `offline_wheels/` in the shared UV cache (`/gems/uv/offline_wheels`) and installs with `uv pip install --offline --no-index --find-links /gems/uv/offline_wheels --require-hashes`, using requirements exported from the gem's `uv.lock`. Because that directory doesn't change between installs, reinstalling or upgrading the plugin reuses the cached packages instead of unpacking them again. The wheel files stay there after the plugin is uninstalled, so they count against the `/gems` volume. Any wheel whose hash differs from the lock is rejected. A package missing from the bundle, or built for another platform or Python version, fails the install with uv's message naming it. COSMOS doesn't fall back to an index for these plugins, including when uv is unavailable (`OPENC3_USE_UV=false`). In that case it logs an error and installs nothing. A failed Python dependency install doesn't stop the plugin install: COSMOS logs the error and still deploys the plugin's targets, microservices and other components, without their Python dependencies. Check the install log in the Admin Console after installing an `offline_install` plugin. Installing the wheels also adds them to the shared UV cache, so they appear in the Cached section of the Admin Console [Packages tab](/docs/tools/admin#packages).

Wheels with compiled code only install on the OS, CPU architecture and Python version they were built for. Pure-Python wheels install anywhere. Building with `openc3.sh cli rake build` runs the build in the COSMOS image, so the default target matches the deployment. When building on another machine, or for a deployment that runs more than one architecture, set `python_platforms` to uv's `--python-platform` names for the deployment and `python_version` to its Python version. `python_platforms` requires `python_version`; without it the wheels would match the build machine's Python.

After installing dependencies, COSMOS parses `plugin.txt` again with [ERB](/docs/configuration/format#erb) variable substitution applied and deploys each component declared in the file: targets, interfaces, routers, microservices, tools, widgets, and script engines.

### Target Deployment

When a target is deployed, its files are extracted from the gem's `targets/<FOLDER>/` directory and uploaded to the configuration bucket under `<SCOPE>/targets/<TARGET_NAME>/`. This `targets/` path represents the original, read-only target configuration as shipped by the plugin.

COSMOS also creates an archive zip in `<SCOPE>/target_archives/<TARGET_NAME>/` which stores versioned snapshots of the target configuration. Each archive is identified by a SHA256 hash so previous versions can be restored.

The `<SCOPE>/targets_modified/<TARGET_NAME>/` path stores user-editable modifications to targets. When a user edits screens, scripts, or other target files through the COSMOS UI, those changes are written to `targets_modified/` rather than overwriting the originals in `targets/`. This separation means user customizations survive plugin upgrades — COSMOS reads from `targets_modified/` first and falls back to `targets/` for unmodified files. When a plugin is upgraded, files that the user has not modified are updated from the new plugin while user modifications in `targets_modified/` are preserved.

Target deployment also automatically creates several microservices for each target:

- **DECOM** — Decommutates raw telemetry packets into individual data items
- **COMMANDLOG** — Logs raw command packets to the bucket storage
- **PACKETLOG** — Logs raw telemetry packets to the bucket storage
- **CLEANUP** — Removes old log files based on the configured retention time
- **TSDB** — Writes decommutated data to the time series database
- **MULTI** — Parent microservice that manages child processes for orderly startup and shutdown

### Interface and Router Deployment

Interfaces and routers each create a corresponding microservice that the operator starts as a running process. The microservice handles the physical connection (TCP, UDP, serial, etc.) and routes commands and telemetry to the appropriate Valkey pub/sub topics.

### Tool Deployment

Tool files (HTML, JavaScript, CSS, fonts) are extracted from the gem's `tools/<FOLDER>/` directory and uploaded to the tools bucket. Files are uploaded in dependency order: fonts first, then CSS, then HTML and JavaScript. This ensures assets are available when the tool's page loads. Tools appear in the COSMOS navigation bar after installation.

### Widget Deployment

Widget JavaScript files and source maps are extracted and uploaded to the tools bucket. Widgets become available for use in Telemetry Viewer screens after installation.

### Microservice Deployment

Custom microservice files are extracted from the gem's `microservices/<FOLDER>/` directory and uploaded to the config bucket under `<SCOPE>/microservices/<MICROSERVICE_NAME>/`. The COSMOS operator watches Redis for new microservice definitions and starts them as running processes.

### Uninstallation

When a plugin is uninstalled, COSMOS destroys all its components in dependency order: microservices are stopped first (with a wait period for graceful shutdown), then interfaces, routers, tools, widgets, targets, and script engines are removed. All associated files are deleted from both the configuration and tools buckets, and Redis state is cleaned up.

## Plugin Directory Structure

COSMOS plugins have a well-defined directory structure described in detail in the [Code Generator](/docs/getting-started/generators) documentation.

## plugin.txt Configuration File

A plugin.txt configuration file is required for any COSMOS plugin. It declares the contents of the plugin and provides variables that allow the plugin to be configured at the time it is initially installed or upgraded.
This file follows the standard COSMOS configuration file format of keywords followed by zero or more space separated parameters. The following keywords are supported by the plugin.txt config file:

COSMOS_META
