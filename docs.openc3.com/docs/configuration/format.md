---
sidebar_position: 1
title: File Format
description: Structure of a COSMOS file, including using ERB
---

COSMOS configuration files are just text files. They can (and should) be checked into your configuration management system and thus can be easily diffed throughout their history. They support ERB syntax, partials, and various line continuations which make them extremely flexible.

## Keyword / Parameters

Each line of a COSMOS configuration file contains a single keyword followed by parameters. For example:

```cosmos
COMMAND TARGET COLLECT BIG_ENDIAN "Collect command"
```

The keyword is `COMMAND` and the parameters are `TARGET`, `COLLECT`, `BIG_ENDIAN`, and `"Collect command"`. Keywords are parsed by COSMOS and parameters are checked for validity. Parameters can be required or optional although required parameters always come first. Some parameters have a limited set of valid values. For example, the `COMMAND` keyword above has the following documentation:

| PARAMETER   | DESCRIPTION                                                                                                                                        | REQUIRED |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Target      | Name of the target this command is associated with                                                                                                 | True     |
| Command     | Name of this command. Also referred to as its mnemonic. Must be unique to commands to this target. Ideally will be as short and clear as possible. | True     |
| Endianness  | Indicates if the data in this command is to be sent in Big Endian or Little Endian format<br/><br/>Valid Values: `BIG_ENDIAN, LITTLE_ENDIAN`       | True     |
| Description | Description of this command which must be enclosed with quotes                                                                                     | False    |

The Target and Command parameters can be any string and are required. The Endianness parameter is required and must be `BIG_ENDIAN` or `LITTLE_ENDIAN`. Other values will cause an error when parsed. The Description parameter must be enclosed in quotes and is optional. All the COSMOS configuration files document their keyword and parameters in this fashion. In addition, Example Usage is provided similar to the example given above.

## ERB

ERB stands for Embedded Ruby. [ERB](https://github.com/ruby/erb) is a templating system for Ruby which allows you to use Ruby logic and variables to generate text files. There are two basic forms of ERB:

```cosmos
<% Ruby code -- no output %>
<%= Ruby expression -- insert result %>
```

In a COSMOS [Telemetry](telemetry.md) configuration file we could write the following:

```cosmos
<% (1..5).each do |i| %>
  APPEND_ITEM VALUE<%= i %> 16 UINT "Value <%= i %> setting"
<% end %>
```

The first line is Ruby code which iterates from 1 up to and including 5 and places the value in the variable i. The code inside the block will be output to the file every time the iteration runs. The APPEND_ITEM line uses the value of i and directly outputs it to the file by using the `<%=` syntax. The result of the parsing will look like the following:

```cosmos
APPEND_ITEM VALUE1 16 UINT "Value 1 setting"
APPEND_ITEM VALUE2 16 UINT "Value 2 setting"
APPEND_ITEM VALUE3 16 UINT "Value 3 setting"
APPEND_ITEM VALUE4 16 UINT "Value 4 setting"
APPEND_ITEM VALUE5 16 UINT "Value 5 setting"
```

COSMOS uses ERB syntax extensively in a Plugin's [plugin.txt](plugins.md#plugintxt-configuration-file) configuration file.

:::info[ERB is Install-time, not Runtime]
ERB statements are _only_ evaluated at plugin installation time.
:::

### target_name

Any of the COSMOS configuration files can use the ERB variable `target_name` to refer to the actual name of the target. This allows you to use target name substitution in your plugin.txt and then use the correct values throughout your target files (procedures, libraries, etc). This variable is resolved at plugin _install_ time and then remains constant.

For example, you have a target definition in the `targets/KEYSIGHT_N6700` directory but you have 3 physical power supplies you want to control. Your plugin.txt might look like the following:

```cosmos
TARGET KEYSIGHT_N6700 PWR_SUPPLY1
TARGET KEYSIGHT_N6700 PWR_SUPPLY2
TARGET KEYSIGHT_N6700 PWR_SUPPLY3
```

If you use our [Target Generator](/docs/getting-started/generators#target-generator) you will have a target library at `targets/KEYSIGHT_N6700/lib/keysight_n6700.py`. To implement commands and telemetry checks in your target library that will work with dynamic target names, you can not hardcode the target name as `KEYSIGHT_N6700`. Instead you should use ERB to make the target name dynamic. For example:

```python
from openc3.script import *

class KeysightN6700:
    def power_on(self):
        cmd("<%= target_name %> POWER_ON")
        wait_check("<%= target_name %> STATUS POWER == 'ON'", 5)
```

### render

COSMOS provides a method used inside ERB called `render` which renders a configuration file into another configuration file. For example:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  <%= render "_ccsds_apid.txt", locals: {apid: 1} %>
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

The render method takes a parameter which is the name of the configuration file to inject into the top level file. This file is required to start with underscore to avoid being processed as a regular configuration file. This file is called a partial since it's part of a larger file. For example, \_ccsds_apid.txt is defined as follows:

```cosmos
  APPEND_ID_ITEM CCSDSAPID 11 UINT <%= apid %> "CCSDS application process id"
```

This would result in output as follows:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  APPEND_ID_ITEM CCSDSAPID 11 UINT 1 "CCSDS application process id"
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

Note the variable `apid` was set to 1 using the `locals:` syntax. This is a very powerful way to add common headers and footer to every packet definition. See the INST target's cmd_tlm definitions in the [Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/cmd_tlm) for a more comprehensive example.

### require

You can also `require` files using ERB. For example, you have `targets/BOB/lib/msg_id.rb`

```cosmos
BOB_MSG_ID = 0x1234
```

You can require this in your cmd.txt and use the values from the required file:

```cosmos
<% require "msg_id" %>

COMMAND BOB EXAMPLE BIG_ENDIAN "Packet description"
  # Keyword           Name  BitSize Type   Min Max  Default            Description
  APPEND_ID_PARAMETER ID    16      UINT   MIN MAX  <%= BOB_MSG_ID %>  "Identifier"
  APPEND_PARAMETER    VALUE 32      FLOAT  0   10.5 2.5                "Value"
  APPEND_PARAMETER    BOOL  8       UINT   MIN MAX  0                  "Boolean"
    STATE FALSE 0
    STATE TRUE 1
  APPEND_PARAMETER    LABEL 0       STRING          "OpenC3" "The label to apply"
```

This will put `0x1234` as the `ID` parameters default value.

:::warning[Filename duplication]
If you have 2 targets which both have files called `msg_id.rb` then the first file will 'win' when you require it. A more explicit alternative is:
`<% require File.expand_path('../lib/msg_id', Dir.pwd) %>`. However, the best solution is to simply name files after the target to keep them distinct, e.g. `bob_msg_id.rb`.
:::

## Line Continuation

COSMOS supports a line continuation character in configuration files. For a simple line continuation use the ampersand character: `&`. For example:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN &
  "Health and status"
```

This will strip the ampersand character and merge the two lines to result in:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
```

Spaces around the second line are stripped so indentation does not matter.

## String Concatenation

COSMOS supports two different string concatenation characters in configuration files. To concatenate strings with a newline use the plus character: `+`. For example:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status" +
  "Additional description"
```

The strings will be merged with a newline to result in:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status\nAdditional description"
```

To concatenate strings without a newline use the backslash character: `\`. For example:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and status' \
  'Additional description'
```

The strings will be merged without a newline to result in:

```cosmos
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and statusAdditional description'
```

The string continuation characters work with both single or double quoted strings but note that both lines MUST use the same syntax. You can not concatenate a single quoted string with a double quoted string or vice versa. Also note the indentation of the second line does not matter as whitespace is stripped.
