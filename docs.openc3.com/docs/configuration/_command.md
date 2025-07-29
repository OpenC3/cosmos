---
sidebar_position: 4
title: Commands
description: Command definition file format and keywords
sidebar_custom_props:
  myEmoji: 📡
---

<!-- Be sure to edit _command.md because command.md is a generated file -->

## Command Concepts

The COSMOS front end provides multiple ways to send commands. They can come from a script (e.g. in [Script Runner](../tools/script-runner)), a tool like [Command Sender](../tools/cmd-sender), or just generally through an API call. These requests will go to the CmdTlmApi Server to start the flow through the rest of the COSMOS architecture and out to the target as follows:

![Command Processing Diagram](/img/cmd-processing.png)

## Command Definition Files

Command definition files define the command packets that can be sent to COSMOS targets. One large file can be used to define the command packets, or multiple files can be used at the user's discretion. Command definition files are placed in the target's cmd_tlm directory and are processed alphabetically. Therefore if you have some command files that depend on others, e.g. they override or extend existing commands, they must be named last. The easiest way to do this is to add an extension to an existing file name. For example, if you already have cmd.txt you can create cmd_override.txt for commands that depends on the definitions in cmd.txt. Also note that due to the way the [ASCII Table](http://www.asciitable.com/) is structured, files beginning with capital letters are processed before lower case letters.

When defining command parameters you can choose from the following data types: INT, UINT, FLOAT, STRING, BLOCK. These correspond to integers, unsigned integers, floating point numbers, strings and binary blocks of data. The only difference between a STRING and BLOCK is when COSMOS reads the binary command log it stops reading a STRING type when it encounters a null byte (0). This shows up in the text log produced by Data Extractor. Note that this does NOT affect the data COSMOS writes as it's still legal to pass null bytes (0) in STRING parameters.

<div style={{"clear": 'both'}}></div>

## Command Authority (Enterprise)

Command Authority can be enabled in the Admin Console under the Scopes tab and is enabled scope wide. Once Command Authority is enabled, individual users can take and release Command Authority which enables exclusive command and script access to that target for that user. Without Command Authority, users can not send a command or start a script under that target. Note, commands or scripts scheduled with Calendar or Autonomic are not affected by Command Authority.

![Command Authority](/img/cmd_tlm_server/cmd_authority.png)
![Command Authority in CmdTlm Server](/img/cmd_tlm_server/cmd_authority_targets.png)

## Critical Commanding (Enterprise)

Critical Commanding can be enabled in the Admin Console under the Scopes tab and is enabled scope wide. Critical commanding requires a different user to approve each command. When Critical Commanding mode is set to NORMAL, HAZARDOUS and RESTRICTED commands need approval. When Critical Commanding mode is set to ALL, all manual commands will require approval. OFF is the default, and disables Critical Commanding.

Here is an example of sending a HAZARDOUS command in Command Sender when Critical Command Mode is set to NORMAL.

![Critical Command](/img/cmd_tlm_server/critical_cmd_sender.png)

# Command Keywords

COSMOS_META

## Example File

**Example File: TARGET/cmd_tlm/cmd.txt**

<!-- prettier-ignore -->
```ruby
COMMAND TARGET COLLECT_DATA BIG_ENDIAN "Commands my target to collect data"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 100 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 4 4 4 "CCSDS PRIMARY HEADER PACKET LENGTH"
  PARAMETER ANGLE 48 32 FLOAT -180.0 180.0 0.0 "ANGLE OF INSTRUMENT IN DEGREES"
    POLY_WRITE_CONVERSION 0 0.01745 0 0
  PARAMETER MODE 80 8 UINT 0 1 0 "DATA COLLECTION MODE"
    STATE NORMAL 0
    STATE DIAG 1
COMMAND TARGET NOOP BIG_ENDIAN "Do Nothing"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 101 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 0 0 0 "CCSDS PRIMARY HEADER PACKET LENGTH"
  PARAMETER DUMMY 48 8 UINT 0 0 0 "DUMMY PARAMETER BECAUSE CCSDS REQUIRES 1 BYTE OF DATA"
COMMAND TARGET SETTINGS BIG_ENDIAN "Set the Settings"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 102 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 0 0 0 "CCSDS PRIMARY HEADER PACKET LENGTH"
  <% 5.times do |x| %>
  APPEND_PARAMETER SETTING<%= x %> 16 UINT 0 5 0 "Setting <%= x %>"
  <% end %>
```
