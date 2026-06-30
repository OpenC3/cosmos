---
sidebar_position: 3
title: Targets
description: Target definition file format and keywords
sidebar_custom_props:
  myEmoji: 🛰️
---

{/* Be sure to edit _target.md because target.md is a generated file */}

## Overview

Targets are the external embedded systems that COSMOS connects to. Targets are defined by the top level [TARGET](plugins.md#target-1) keyword in the plugin.txt file. Each target is self contained in a target directory named after the target. In the root of the target directory there is a configuration file named target.txt which configures the individual target.

A target communicates with COSMOS through an [Interface](interfaces). Targets are typically mapped to an interface using the [MAP_TARGET](plugins.md#map_target), [MAP_CMD_TARGET](plugins.md#map_cmd_target), and [MAP_TLM_TARGET](plugins.md#map_tlm_target) keywords beneath the [INTERFACE](plugins.md#interface-1) definition. Targets and interfaces are a many-to-many relationship; see [Mapping Targets to Interfaces](interfaces#mapping-targets-to-interfaces) for details.

## target.txt Keywords

COSMOS_META
