---
sidebar_position: 3
title: Targets
description: Target definition file format and keywords
sidebar_custom_props:
  myEmoji: 🛰️
---

<!-- Be sure to edit _target.md because target.md is a generated file -->

Targets are the external embedded systems that COSMOS connects to. Targets are defined by the top level [TARGET](plugins.md#target-1) keyword in the plugin.txt file. Each target is self contained in a target directory named after the target. In the root of the target directory there is a configuration file named target.txt which configures the individual target.

# target.txt Keywords

COSMOS_META
