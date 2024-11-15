---
sidebar_position: 8
title: Tables
description: Table definition file format and keywords
---

<!-- Be sure to edit _table.md because table.md is a generated file -->

## Table Definition Files

Table definition files define the binary tables that can be displayed in COSMOS [Table Manager](../tools/table-manager.md)
. Table definitions are defined in the target's tables/config directory and are typically named after the table such as `PPSSelectionTable_def.txt`. The `_def.txt` extension helps to identify the file as a table definition. Table definitions can be combined using the `TABLEFILE` keyword. This allows you to build individual table components into a larger binary.

The Table definition files share a lot of similarity with the [Command Configuration](command.md). You have the same data types: INT, UINT, FLOAT, STRING, BLOCK. These correspond to integers, unsigned integers, floating point numbers, strings and binary blocks of data.

<div style={{"clear": 'both'}}></div>

# Table Keywords

COSMOS_META

## Example File

**Example File: TARGET/tables/config/MCConfigurationTable_def.txt**

<!-- prettier-ignore -->
```ruby
TABLE "MC_Configuration" BIG_ENDIAN KEY_VALUE "Memory Control Configuration Table"
  APPEND_PARAMETER "Scrub_Region_1_Start_Addr" 32 UINT 0 0x03FFFFFB 0
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_1_End_Addr" 32 UINT 0 0x03FFFFFF 0x03FFFFFF
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_2_Start_Addr" 32 UINT 0 0x03FFFFB 0
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_2_End_Addr" 32 UINT 0 0x03FFFFF 0x03FFFFF
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Dump_Packet_Throttle_(sec)" 32 UINT 0 0x0FFFFFFFF 2 "Number of seconds to wait between dumping large packets"
  APPEND_PARAMETER "Memory_Scrubbing" 8 UINT 0 1 1
    STATE DISABLE 0
    STATE ENABLE 1
  APPEND_PARAMETER "SIOC_Memory_Config" 8 UINT 1 3 3
  APPEND_PARAMETER "Uneditable_Text" 32 UINT MIN MAX 0xDEADBEEF "Uneditable field"
    FORMAT_STRING "0x%0X"
    UNEDITABLE
  APPEND_PARAMETER "Uneditable_State" 16 UINT MIN MAX 0 "Uneditable field"
    STATE DISABLE 0
    STATE ENABLE 1
    UNEDITABLE
  APPEND_PARAMETER "Uneditable_Check" 16 UINT MIN MAX 1 "Uneditable field"
    STATE UNCHECKED 0
    STATE CHECKED 1
    UNEDITABLE
  APPEND_PARAMETER "Binary" 32 STRING 0xDEADBEEF "Binary string"
  APPEND_PARAMETER "Pad" 16 UINT 0 0 0
    HIDDEN
```
