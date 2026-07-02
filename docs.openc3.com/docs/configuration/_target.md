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

## Stored Limits Mode

When COSMOS receives telemetry through a normal real-time interface, limits are evaluated, state changes are logged, and any configured [limits responses](limits-response) are triggered. However, when telemetry arrives with the **stored** flag set (e.g. from a [File Interface](interfaces#file-interface) or historical data replay), you may not want limits processing to behave the same way. The `STORED_LIMITS_MODE` plugin.txt setting controls this behavior per target.

:::info
Please see [Historical Data Ingest](/docs/guides/historical-data.md) for how to handle historical data in COSMOS.
:::

### Modes

| Mode | Limits Evaluated | Changes Logged | Limits Reactions | Updates Current State |
|------|:----------------:|:--------------:|:----------------:|:---------------------:|
| **PROCESS** (default) | Yes | Yes | Yes | Yes |
| **LOG** | Yes | Yes | No | No |
| **DISABLE** | No | No | No | No |

**PROCESS** -- The default. Stored packets are processed exactly like real-time packets. Limits are evaluated, state changes are logged and published, limits responses fire, and the system-wide current limits state (used by `get_overall_limits_state` and the Limits Monitor) is updated.

**LOG** -- Limits are evaluated and state changes are logged and published to the limits event stream, but limits responses (automated reactions) are **not** triggered. The current limits state hash is **not** updated, so stored data cannot cause the overall system limits state to change. This is useful when you want visibility into historical limits behavior without side effects.

**DISABLE** -- Limits processing is skipped entirely for stored packets. No limits are evaluated, no state changes are logged, no events are published, and no limits responses fire. Additionally, the decommutated output for stored packets will not contain limits state (`__L`) values. This is useful when replaying large volumes of historical data where limits are irrelevant.

:::info
Non-stored (real-time) packets are always processed normally regardless of this setting.
:::

### Configuration

`STORED_LIMITS_MODE` is set as a modifier under the [TARGET](plugins.md#target-1) keyword in `plugin.txt`:

```cosmos
TARGET INST INST
  STORED_LIMITS_MODE LOG
```

See the [STORED_LIMITS_MODE](plugins.md#stored_limits_mode) reference for parameter details.

## target.txt Keywords

COSMOS_META
