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

Once variables are set, COSMOS registers the plugin model in Redis, installs the Ruby gem, and if the plugin contains a `pyproject.toml` or `requirements.txt`, installs Python dependencies as well. It then parses `plugin.txt` again with [ERB](/docs/configuration/format#erb) variable substitution applied and deploys each component declared in the file: targets, interfaces, routers, microservices, tools, widgets, and script engines.

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
