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


## LANGUAGE
<span class="badge badge--secondary since-right">Since 5.11.1</span>**Programming language of the target interfaces and microservices**

The target language must be either Ruby or Python. The language determines how the target's interfaces and microservices are run. A target must pick one language for its interfaces and microservices &mdash; you cannot mix Ruby and Python interfaces/microservices within the same target. Scripts executed in Script Runner are independent of this setting and may be written in either Ruby or Python regardless of the target's LANGUAGE. Note that both Ruby and Python still use ERB to perform templating.

| Parameter | Description | Required |
|-----------|-------------|----------|
|  | Ruby or Python<br/><br/>Valid Values: <span class="values">ruby, python</span> | True |

Example Usage:
```cosmos
LANGUAGE python
```

## REQUIRE
**Requires a Ruby file**

List the Ruby files required to explicitly declare dependencies. This is now completely optional.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Filename | Filename to require. For files in the target's lib directory simply supply the filename, e.g. "REQUIRE my_file". Files in the base OpenC3 lib directory also should just list the filename. If a file is in a folder under the lib directory then you must specify the folder name, e.g. "REQUIRE folder/my_file". Note the ".rb" extension is optional when specifying the filename. | True |

Example Usage:
```cosmos
REQUIRE limits_response.rb
```

## IGNORE_PARAMETER
**Ignore the given command parameter**

Hint to other OpenC3 tools to hide or ignore this command parameter when processing the command. For example, Command Sender and Command Sequence will not display the parameter (by default) when showing the command and Script Runner code completion will not display the parameter.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Parameter Name | The name of a command parameter. Note that this parameter will be ignored in ALL the commands it appears in. | True |

Example Usage:
```cosmos
IGNORE_PARAMETER CCSDS_VERSION
```

## IGNORE_ITEM
**Ignore the given telemetry item**

Hint to other OpenC3 tools to hide or ignore this telemetry item when processing the telemetry. For example, Packet Viewer will not display the item (by default) when showing the packet.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Item name | The name of a telemetry item. Note that this item will be ignored in ALL the telemetry it appears in. | True |

Example Usage:
```cosmos
IGNORE_ITEM CCSDS_VERSION
```

## COMMANDS
**Process the given command definition file**

This keyword is used to explicitly add the command definition file to the list of command and telemetry files to process.

:::warning
Usage of this keyword overrides automatic command and telemetry file discovery. If this keyword is used, you must also use the TELEMETRY keyword to specify the telemetry files to process.
:::

| Parameter | Description | Required |
|-----------|-------------|----------|
| Filename | Name of a command definition file in the target's cmd_tlm directory, e.g. "cmd.txt". | True |

Example Usage:
```cosmos
COMMANDS inst_cmds_v2.txt
TELEMETRY inst_tlm_v2.txt
```

## TELEMETRY
**Process the given telemetry definition file**

This keyword is used to explicitly add the telemetry definition file to the list of command and telemetry files to process.

:::warning
Usage of this keyword overrides automatic command and telemetry file discovery. If this keyword is used, you must also use the COMMAND keyword to specify the command files to process.
:::

| Parameter | Description | Required |
|-----------|-------------|----------|
| Filename | Name of a telemetry definition file in the target's cmd_tlm directory, e.g. "tlm.txt". | True |

Example Usage:
```cosmos
COMMANDS inst_cmds_v2.txt
TELEMETRY inst_tlm_v2.txt
```

## CMD_UNIQUE_ID_MODE
:::note[Deprecated]
Since 6.10.0 this condition is now automatically detected
:::

<span class="badge badge--secondary since-right">Since 4.4.0</span>**Command packet identifiers don't all share the same bit offset, size, and type**

Ideally all commands for a target are identified using the exact same bit offset, size, and type field in each command. If ANY command identifiers differ then this flag must be set to force a brute force identification method.


## TLM_UNIQUE_ID_MODE
:::note[Deprecated]
Since 6.10.0 this condition is now automatically detected
:::

<span class="badge badge--secondary since-right">Since 4.4.0</span>**Telemetry packets identifiers don't all share the same bit offset, size, and type**

Ideally all telemetry for a target are identified using the exact same bit offset, size, and type field in each packet. If ANY telemetry identifiers differ then this flag must be set to force a brute force identification method.


