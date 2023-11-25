---
sidebar_position: 3
title: Targets
---

<!-- Be sure to edit _target.md because target.md is a generated file -->

Targets are the external embedded systems that COSMOS connects to. Targets are defined by the top level [TARGET](plugins.md#target-1) keyword in the plugin.txt file. Each target is self contained in a target directory named after the target. In the root of the target directory there is a configuration file named target.txt which configures the individual target.

# target.txt Keywords


## LANGUAGE
<div class="right">(Since 5.11.1)</div>**Programming language of the target interfaces and microservices**

The target language must be either Ruby or Python. The language determines how the target's interfaces and microservices are run. Note that both Ruby and Python still use ERB to perform templating.

| Parameter | Description | Required |
|-----------|-------------|----------|
|  | Ruby or Python<br/><br/>Valid Values: <span class="values">ruby, python</span> | True |

Example Usage:
```ruby
LANGUAGE python
```

## REQUIRE
**Requires a Ruby file**

Ruby files must be required to be available to call in other code. Files are first required from the target's lib folder. If no file is found the Ruby system path is checked which includes the base openc3/lib folder.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Filename | Filename to require. For files in the target's lib directory simply supply the filename, e.g. "REQUIRE my_file". Files in the base OpenC3 lib directory also should just list the filename. If a file is in a folder under the lib directory then you must specify the folder name, e.g. "REQUIRE folder/my_file". The filename can also be an absolute path but this is not common. Note the ".rb" extension is optional when specifying the filename. | True |

Example Usage:
```ruby
REQUIRE limits_response.rb
```

## IGNORE_PARAMETER
**Ignore the given command parameter**

Hint to other OpenC3 tools to hide or ignore this command parameter when processing the command. For example, Command Sender and Command Sequence will not display the parameter (by default) when showing the command and Script Runner code completion will not display the parameter.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Parameter Name | The name of a command parameter. Note that this parameter will be ignored in ALL the commands it appears in. | True |

Example Usage:
```ruby
IGNORE_PARAMETER CCSDS_VERSION
```

## IGNORE_ITEM
**Ignore the given telemetry item**

Hint to other OpenC3 tools to hide or ignore this telemetry item when processing the telemetry. For example, Packet Viewer will not display the item (by default) when showing the packet.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Item name | The name of a telemetry item. Note that this item will be ignored in ALL the telemetry it appears in. | True |

Example Usage:
```ruby
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
```ruby
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
```ruby
COMMANDS inst_cmds_v2.txt
TELEMETRY inst_tlm_v2.txt
```

## CMD_UNIQUE_ID_MODE
<div class="right">(Since 4.4.0)</div>**Command packet identifiers don't all share the same bit offset, size, and type**

Ideally all commands for a target are identified using the exact same bit offset, size, and type field in each command. If ANY command identifiers differ then this flag must be set to force a brute force identification method.

:::warning
Using this mode significantly slows packet identification
:::


## TLM_UNIQUE_ID_MODE
<div class="right">(Since 4.4.0)</div>**Telemetry packets identifiers don't all share the same bit offset, size, and type**

Ideally all telemetry for a target are identified using the exact same bit offset, size, and type field in each packet. If ANY telemetry identifiers differ then this flag must be set to force a brute force identification method.

:::warning
Using this mode significantly slows packet identification
:::


