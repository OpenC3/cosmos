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

Plugins are where you define targets (and their corresponding command and telemetry packet definitions), where you configure the interfaces needed to talk to targets, where you can define routers to stream raw data out of COSMOS, how you can add new tools to the COSMOS user interface, and how you can run additional microservices to provide new functionality.

Each plugin is built as a Ruby gem and thus has a plugin.gemspec file which builds it. Plugins have a plugin.txt file which declares all the variables used by the plugin and how to interface to the target(s) it contains.

## Concepts

### Target

Targets are the external pieces of hardware and/or software that COSMOS communicates with. These are things like Front End Processors (FEPs), ground support equipment (GSE), custom software tools, and pieces of hardware like satellites themselves. A target is anything that COSMOS can send commands to and receive telemetry from.

### Interface

Interfaces implement the physical connection to one or more targets. They are typically ethernet connections implemented using TCP or UDP but can be other connections like serial ports. Interfaces send commands to targets and receive telemetry from targets.

### Router

Routers flow streams of telemetry packets out of COSMOS and receive streams of commands into COSMOS. The commands are forwarded by COSMOS to associated interfaces. Telemetry comes from associated interfaces.

### Tool

COSMOS Tools are web-based applications the communicate with the COSMOS APIs to perform takes like displaying telemetry, sending commands, and running scripts.

### Microservice

Microservices are persistent running backend code that runs within the COSMOS environment. They can process data and perform other useful tasks.

## Plugin Directory Structure

COSMOS plugins have a well-defined directory structure described in detail in the [Code Generator](../getting-started/generators) documentation.

## plugin.txt Configuration File

A plugin.txt configuration file is required for any COSMOS plugin. It declares the contents of the plugin and provides variables that allow the plugin to be configured at the time it is initially installed or upgraded.
This file follows the standard COSMOS configuration file format of keywords followed by zero or more space separated parameters. The following keywords are supported by the plugin.txt config file:

COSMOS_META
