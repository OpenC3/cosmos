---
sidebar_position: 5
title: Telemetry
description: Telemetry definition file format and keywords
sidebar_custom_props:
  myEmoji: 📡
---

<!-- Be sure to edit _telemetry.md because telemetry.md is a generated file -->

## Telemetry Definition Files

Telemetry definition files define the telemetry packets that can be received and processed from COSMOS targets. One large file can be used to define the telemetry packets, or multiple files can be used at the user's discretion. Telemetry definition files are placed in the target's cmd_tlm directory and are processed alphabetically. Therefore if you have some telemetry files that depend on others, e.g. they override or extend existing telemetry, they must be named last. The easiest way to do this is to add an extension to an existing file name. For example, if you already have tlm.txt you can create tlm_override.txt for telemetry that depends on the definitions in tlm.txt. Note that due to the way the [ASCII Table](http://www.asciitable.com/) is structured, files beginning with capital letters are processed before lower case letters.

When defining telemetry items you can choose from the following data types: INT, UINT, FLOAT, STRING, BLOCK. These correspond to integers, unsigned integers, floating point numbers, strings and binary blocks of data. Within COSMOS, the only difference between a STRING and BLOCK is when COSMOS reads a STRING type it stops reading when it encounters a null byte (0). This shows up when displaying the value in Packet Viewer or Tlm Viewer and in the output of Data Extractor. You should strive to store non-ASCII data inside BLOCK items and ASCII strings in STRING items.

:::info Printing Data

Most data types can be printed in a COSMOS script simply by doing <code>print(tlm("TGT PKT ITEM"))</code>. However, if the ITEM is a BLOCK data type and contains binary (non-ASCII) data then that won't work. COSMOS comes with a built-in method called <code>formatted</code> to help you view binary data. If ITEM is a BLOCK type containing binary try <code>puts tlm("TGT PKT ITEM").formatted</code> (Ruby) and <code>print(formatted(tlm("TGT PKT ITEM")))</code> (Python) which will print the bytes out as hex.
:::

### ID Items

All packets require identification items so the incoming data can be matched to a packet structure. These items are defined using the [ID_ITEM](telemetry.md#id_item) and [APPEND_ID_ITEM](telemetry.md#append_id_item). As data is read from the interface and refined by the protocol, the resulting packet is identified by matching all the ID fields. Note that ideally all packets in a particular target should use the exact same bit offset, bit size, and data type to identify. If this is not the case, you must set [TLM_UNIQUE_ID_MODE](target.md#tlm_unique_id_mode) in the target.txt file which incurs a performance penalty on every packet identification.

### Variable Sized Items

COSMOS specifies a variable sized item with a bit size of 0. When a packet is identified, all other data that isn't explicitly defined will be put into the variable sized item. These items are typically used for packets containing memory dumps which vary in size depending on the number of bytes dumped. Note that there can only be one variable sized item per packet.

### Derived Items

COSMOS has a concept of a derived item which is a telemetry item that doesn't actually exist in the binary data. Derived items are typically computed based on other telemetry items. COSMOS derived items are very similar to real items except they use the special DERIVED data type. Here is how a derived item might look in a telemetry definition.

```ruby
ITEM TEMP_AVERAGE 0 0 DERIVED "Average of TEMP1, TEMP2, TEMP3, TEMP4"
```

Note the bit offset and bit size of 0 and the data type of DERIVED. For this reason DERIVED items should be declared using ITEM rather than APPEND_ITEM. They can be defined anywhere in the packet definition but are typically placed at the end. The ITEM definition must be followed by a CONVERSION keyword, e.g. [READ_CONVERSION](telemetry.md#read_conversion), to generate the value.

### Received Time and Packet Time

COSMOS automatically creates several telemetry items on every packet: PACKET_TIMESECONDS, PACKET_TIMEFORMATTED, RECEIVED_COUNT, RECEIVED_TIMEFORMATTED, and RECEIVED_TIMESECONDS.

RECEIVED_TIME is the time that COSMOS receives the packet. This is set by the interface which is connected to the target and is receiving the raw data. Once a packet has been created out of the raw data the time is set.

PACKET_TIME defaults to RECEIVED_TIME, but can be set as a derived item with a time object in the telemetry configuration file. This helps support stored telemetry packets so that they can be more reasonably handled by other COSMOS tools such as Telemetry Grapher and Data Extractor. You can set the 'stored' flag in your interface and the current value table is unaffected.

The \_TIMEFORMATTED items returns the date and time in a YYYY/MM/DD HH:MM:SS.sss format and the \_TIMESECONDS returns the Unix seconds of the time. Internally these are both stored as either a Ruby Time object or Python date object.

#### Example

COSMOS provides a Unix time conversion class which returns a Ruby Time object or Python date object based on the number of seconds and (optionally) microseconds since the Unix epoch. Note: This returns a native object and not a float or string!

Ruby Example:

```ruby
ITEM PACKET_TIME 0 0 DERIVED "Ruby time based on TIMESEC and TIMEUS"
    READ_CONVERSION unix_time_conversion.rb TIMESEC TIMEUS
```

Python Example:

```python
ITEM PACKET_TIME 0 0 DERIVED "Python time based on TIMESEC and TIMEUS"
    READ_CONVERSION openc3/conversions/unix_time_conversion.py TIMESEC TIMEUS
```

Defining PACKET_TIME allows the PACKET_TIMESECONDS and PACKET_TIMEFORMATTED to be calculated against an internal Packet time rather than the time COSMOS receives the packet.

<div style={{"clear": 'both'}}></div>

# Telemetry Keywords

COSMOS_META

## Example File

**Example File: TARGET/cmd_tlm/tlm.txt**

<!-- prettier-ignore -->
```ruby
TELEMETRY TARGET HS BIG_ENDIAN "Health and Status for My Target"
  ITEM CCSDSVER 0 3 UINT "CCSDS PACKET VERSION NUMBER (SEE CCSDS 133.0-B-1)"
  ITEM CCSDSTYPE 3 1 UINT "CCSDS PACKET TYPE (COMMAND OR TELEMETRY)"
    STATE TLM 0
    STATE CMD 1
  ITEM CCSDSSHF 4 1 UINT "CCSDS SECONDARY HEADER FLAG"
    STATE FALSE 0
    STATE TRUE 1
  ID_ITEM CCSDSAPID 5 11 UINT 102 "CCSDS APPLICATION PROCESS ID"
  ITEM CCSDSSEQFLAGS 16 2 UINT "CCSDS SEQUENCE FLAGS"
    STATE FIRST 0
    STATE CONT 1
    STATE LAST 2
    STATE NOGROUP 3
  ITEM CCSDSSEQCNT 18 14 UINT "CCSDS PACKET SEQUENCE COUNT"
  ITEM CCSDSLENGTH 32 16 UINT "CCSDS PACKET DATA LENGTH"
  ITEM CCSDSDAY 48 16 UINT "DAYS SINCE EPOCH (JANUARY 1ST, 1958, MIDNIGHT)"
  ITEM CCSDSMSOD 64 32 UINT "MILLISECONDS OF DAY (0 - 86399999)"
  ITEM CCSDSUSOMS 96 16 UINT "MICROSECONDS OF MILLISECOND (0-999)"
  ITEM ANGLEDEG 112 16 INT "Instrument Angle in Degrees"
    POLY_READ_CONVERSION 0 57.295
  ITEM MODE 128 8 UINT "Instrument Mode"
    STATE NORMAL 0 GREEN
    STATE DIAG 1 YELLOW
  ITEM TIMESECONDS 0 0 DERIVED "DERIVED TIME SINCE EPOCH IN SECONDS"
    GENERIC_READ_CONVERSION_START FLOAT 32
      ((packet.read('ccsdsday') * 86400.0) + (packet.read('ccsdsmsod') / 1000.0) + (packet.read('ccsdsusoms') / 1000000.0)  )
    GENERIC_READ_CONVERSION_END
  ITEM TIMEFORMATTED 0 0 DERIVED "DERIVED TIME SINCE EPOCH AS A FORMATTED STRING"
    GENERIC_READ_CONVERSION_START STRING 216
      time = Time.ccsds2mdy(packet.read('ccsdsday'), packet.read('ccsdsmsod'), packet.read('ccsdsusoms'))
      sprintf('%04u/%02u/%02u %02u:%02u:%02u.%06u', time[0], time[1], time[2], time[3], time[4], time[5], time[6])
    GENERIC_READ_CONVERSION_END
```
