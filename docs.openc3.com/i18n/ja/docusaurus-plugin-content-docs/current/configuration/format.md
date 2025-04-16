---
sidebar_position: 1
title: File Format
description: Structure of a COSMOS file, including using ERB
---

COSMOS configuration files are just text files. They can (and should) be checked into your configuration management system and thus can be easily diffed throughout their history. They support ERB syntax, partials, and various line continuations which make them extremely flexible.

## Keyword / Parameters

Each line of a COSMOS configuration file contains a single keyword followed by parameters. For example:

```ruby
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

```erb
<% Ruby code -- no output %>
<%= Ruby expression -- insert result %>
```

In a COSMOS [Telemetry](telemetry.md) configuration file we could write the following:

```erb
<% (1..5).each do |i| %>
  APPEND_ITEM VALUE<%= i %> 16 UINT "Value <%= i %> setting"
<% end %>
```

The first line is Ruby code which iterates from 1 up to and including 5 and places the value in the variable i. The code inside the block will be output to the file every time the iteration runs. The APPEND_ITEM line uses the value of i and directly outputs it to the file by using the `<%=` syntax. The result of the parsing will look like the following:

```ruby
APPEND_ITEM VALUE1 16 UINT "Value 1 setting"
APPEND_ITEM VALUE2 16 UINT "Value 2 setting"
APPEND_ITEM VALUE3 16 UINT "Value 3 setting"
APPEND_ITEM VALUE4 16 UINT "Value 4 setting"
APPEND_ITEM VALUE5 16 UINT "Value 5 setting"
```

COSMOS uses ERB syntax extensively in a Plugin's [plugin.txt](plugins.md#plugintxt-configuration-file) configuration file.

### render

COSMOS provides a method used inside ERB called `render` which renders a configuration file into another configuration file. For example:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  <%= render "_ccsds_apid.txt", locals: {apid: 1} %>
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

The render method takes a parameter which is the name of the configuration file to inject into the top level file. This file is required to start with underscore to avoid being processed as a regular configuration file. This file is called a partial since it's part of a larger file. For example, \_ccsds_apid.txt is defined as follows:

```ruby
  APPEND_ID_ITEM CCSDSAPID 11 UINT <%= apid %> "CCSDS application process id"
```

This would result in output as follows:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  APPEND_ID_ITEM CCSDSAPID 11 UINT 1 "CCSDS application process id"
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

Note the variable `apid` was set to 1 using the `locals:` syntax. This is a very powerful way to add common headers and footer to every packet definition. See the INST target's cmd_tlm definitions in the [Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/cmd_tlm) for a more comprehensive example.

## Line Continuation

COSMOS supports a line continuation character in configuration files. For a simple line continuation use the ampersand character: `&`. For example:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN &
  "Health and status"
```

This will strip the ampersand character and merge the two lines to result in:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
```

Spaces around the second line are stripped so indentation does not matter.

## String Concatenation

COSMOS supports two different string concatenation characters in configuration files. To concatenate strings with a newline use the plus character: `+`. For example:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status" +
  "Additional description"
```

The strings will be merged with a newline to result in:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status\nAdditional description"
```

To concatenate strings without a newline use the backslash character: `\`. For example:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and status' \
  'Additional description'
```

The strings will be merged without a newline to result in:

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and statusAdditional description'
```

The string continuation characters work with both single or double quoted strings but note that both lines MUST use the same syntax. You can not concatenate a single quoted string with a double quoted string or vice versa. Also note the indentation of the second line does not matter as whitespace is stripped.
