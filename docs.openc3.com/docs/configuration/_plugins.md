---
sidebar_position: 2
title: Plugins
description: Plugin definition file format and keywords
sidebar_custom_props:
  myEmoji: 🔌
---

<!-- Be sure to edit _plugins.md because plugins.md is a generated file -->

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

## Plugin Directory Structure

COSMOS plugins have a well-defined directory structure described in detail in the [Code Generator](/docs/getting-started/generators) documentation.

## plugin.txt Configuration File

A plugin.txt configuration file is required for any COSMOS plugin. It declares the contents of the plugin and provides variables that allow the plugin to be configured at the time it is initially installed or upgraded.
This file follows the standard COSMOS configuration file format of keywords followed by zero or more space separated parameters. The following keywords are supported by the plugin.txt config file:

COSMOS_META
