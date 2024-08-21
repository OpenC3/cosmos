---
sidebar_position: 5
title: Telemetry
---

<!-- Be sure to edit _telemetry.md because telemetry.md is a generated file -->

## Telemetry Definition Files

Telemetry definition files define the telemetry packets that can be received and processed from COSMOS targets. One large file can be used to define the telemetry packets, or multiple files can be used at the user's discretion. Telemetry definition files are placed in the target's cmd_tlm directory and are processed alphabetically. Therefore if you have some telemetry files that depend on others, e.g. they override or extend existing telemetry, they must be named last. The easist way to do this is to add an extension to an existing file name. For example, if you already have tlm.txt you can create tlm_override.txt for telemetry that depends on the definitions in tlm.txt. Note that due to the way the [ASCII Table](http://www.asciitable.com/) is structured, files beginning with capital letters are processed before lower case letters.

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

Definining PACKET_TIME allows the PACKET_TIMESECONDS and PACKET_TIMEFORMATTED to be calculated against an internal Packet time rather than the time COSMOS receives the packet.

<div style={{"clear": 'both'}}></div>

# Telemetry Keywords


## TELEMETRY
**Defines a new telemetry packet**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target | Name of the target this telemetry packet is associated with | True |
| Command | Name of this telemetry packet. Also referred to as its mnemonic. Must be unique to telemetry packets in this target. Ideally will be as short and clear as possible. | True |
| Endianness | Indicates if the data in this packet is in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | True |
| Description | Description of this telemetry packet which must be enclosed with quotes | False |

Example Usage:
```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Instrument health and status"
```

## TELEMETRY Modifiers
The following keywords must follow a TELEMETRY keyword.

### ITEM
**Defines a telemetry item in the current telemetry packet**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Bit Offset | Bit offset into the telemetry packet of the Most Significant Bit of this item. May be negative to indicate on offset from the end of the packet. Always use a bit offset of 0 for derived item. | True |
| Bit Size | Bit size of this telemetry item. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. If Bit Offset is 0 and Bit Size is 0 then this is a derived parameter and the Data Type must be set to 'DERIVED'. | True |
| Data Type | Data Type of this telemetry item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Description | Description for this telemetry item which must be enclosed with quotes | False |
| Endianness | Indicates if the item is to be interpreted in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
ITEM PKTID 112 16 UINT "Packet ID"
ITEM DATA 0 0 DERIVED "Derived data"
```

### ITEM Modifiers
The following keywords must follow a ITEM keyword.

#### FORMAT_STRING
**Adds printf style formatting**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Format | How to format using printf syntax. For example, '0x%0X' will display the value in hex. | True |

Example Usage:
```ruby
FORMAT_STRING "0x%0X"
```

#### UNITS
**Add displayed units**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Full Name | Full name of the units type, e.g. Celsius | True |
| Abbreviated | Abbreviation for the units, e.g. C | True |

Example Usage:
```ruby
UNITS Celsius C
UNITS Kilometers KM
```

#### DESCRIPTION
**Override the defined description**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Value | The new description | True |

#### META
**Stores custom user metadata**

Meta data is user specific data that can be used by custom tools for various purposes. One example is to store additional information needed to generate source code header files.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Meta Name | Name of the metadata to store | True |
| Meta Values | One or more values to be stored for this Meta Name | False |

Example Usage:
```ruby
META TEST "This parameter is for test purposes only"
```

#### OVERLAP
<div class="right">(Since 4.4.1)</div>**This item is allowed to overlap other items in the packet**

If an item's bit offset overlaps another item, OpenC3 issues a warning. This keyword explicitly allows an item to overlap another and supresses the warning message.


#### KEY
<div class="right">(Since 5.0.10)</div>**Defines the key used to access this raw value in the packet.**

Keys are often JsonPath or XPath strings

| Parameter | Description | Required |
|-----------|-------------|----------|
| Key string | The key to access this item | True |

Example Usage:
```ruby
KEY $.book.title
```

#### VARIABLE_BIT_SIZE
<div class="right">(Since 5.18.0)</div>**Marks an item as having its bit size defined by another length item**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Length Item Name | The name of the associated length item | True |
| Length Bits Per Count | Bits per count of the length item. Defaults to 8 | False |
| Length Value Bit Offset | Offset in Bits to Apply to Length Field Value. Defaults to 0 | False |

#### STATE
**Defines a key/value pair for the current item**

Key value pairs allow for user friendly strings. For example, you might define states for ON = 1 and OFF = 0. This allows the word ON to be used rather than the number 1 when sending the telemetry item and allows for much greater clarity and less chance for user error. A catch all value of ANY applies to all other values not already defined as state values.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Key | The string state name | True |
| Value | The numerical state value or ANY to apply the state to all other values | True |
| Color | The color the state should be displayed as<br/><br/>Valid Values: <span class="values">GREEN, YELLOW, RED</span> | False |

Example Usage:
```ruby
APPEND_ITEM ENABLE 32 UINT "Enable setting"
  STATE FALSE 0
  STATE TRUE 1
  STATE ERROR ANY # Match all other values to ERROR
APPEND_ITEM STRING 1024 STRING "String"
  STATE "NOOP" "NOOP" GREEN
  STATE "ARM LASER" "ARM LASER" YELLOW
  STATE "FIRE LASER" "FIRE LASER" RED
```

#### READ_CONVERSION
**Applies a conversion to the current telemetry item**

Conversions are implemented in a custom Ruby or Python file which should be located in the target's lib folder. The class must inherit from Conversion. It must implement the `initialize` (Ruby) or `__init__` (Python) method if it takes extra parameters and must always implement the `call` method. The conversion factor is applied to the raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Class Filename | The filename which contains the Ruby or Python class. The filename must be named after the class such that the class is a CamelCase version of the underscored filename. For example, 'the_great_conversion.rb' should contain 'class TheGreatConversion'. | True |
| Parameter | Additional parameter values for the conversion which are passed to the class constructor. | False |

Ruby Example:
```ruby
READ_CONVERSION the_great_conversion.rb 1000

Defined in the_great_conversion.rb:

require 'openc3/conversions/conversion'
module OpenC3
  class TheGreatConversion < Conversion
    def initialize(multiplier)
      super()
      @multiplier = multiplier.to_f
    end
    def call(value, packet, buffer)
      return value * @multiplier
    end
  end
end
```

Python Example:
```python
READ_CONVERSION the_great_conversion.py 1000

Defined in the_great_conversion.py:

from openc3.conversions.conversion import Conversion
class TheGreatConversion(Conversion):
    def __init__(self, multiplier):
        super().__init__()
        self.multiplier = float(multiplier)
    def call(self, value, packet, buffer):
        return value * multiplier
```

#### POLY_READ_CONVERSION
**Adds a polynomial conversion factor to the current telemetry item**

The conversion factor is applied to raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog.

| Parameter | Description | Required |
|-----------|-------------|----------|
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

Example Usage:
```ruby
POLY_READ_CONVERSION 10 0.5 0.25
```

#### SEG_POLY_READ_CONVERSION
**Adds a segmented polynomial conversion factor to the current telemetry item**

This conversion factor is applied to the raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Lower Bound | Defines the lower bound of the range of values that this segmented polynomial applies to. Is ignored for the segment with the smallest lower bound. | True |
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

Example Usage:
```ruby
SEG_POLY_READ_CONVERSION 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_READ_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_READ_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100
```

#### GENERIC_READ_CONVERSION_START
**Start a generic read conversion**

Adds a generic conversion function to the current telemetry item. This conversion factor is applied to the raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog. The conversion is specified as Ruby or Python code that receives two implied parameters. 'value' which is the raw value being read and 'packet' which is a reference to the telemetry packet class (Note, referencing the packet as 'myself' is still supported for backwards compatibility). The last line of code should return the converted value. The GENERIC_READ_CONVERSION_END keyword specifies that all lines of code for the conversion have been given.

:::warning
Generic conversions are not a good long term solution. Consider creating a conversion class and using READ_CONVERSION instead. READ_CONVERSION is easier to debug and has higher performance.
:::

| Parameter | Description | Required |
|-----------|-------------|----------|
| Converted Type | Type of the converted value<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | False |
| Converted Bit Size | Bit size of converted value | False |

Ruby Example:
```ruby
APPEND_ITEM ITEM1 32 UINT
  GENERIC_READ_CONVERSION_START
    return (value * 1.5).to_i # Convert the value by a scale factor
  GENERIC_READ_CONVERSION_END
```

Python Example:
```python
APPEND_ITEM ITEM1 32 UINT
  GENERIC_READ_CONVERSION_START
    return int(value * 1.5) # Convert the value by a scale factor
  GENERIC_READ_CONVERSION_END
```

#### GENERIC_READ_CONVERSION_END
**Complete a generic read conversion**


#### LIMITS
**Defines a set of limits for a telemetry item**

If limits are violated a message is printed in the Command and Telemetry Server to indicate an item went out of limits. Other tools also use this information to update displays with different colored telemetry items or other useful information. The concept of "limits sets" is defined to allow for different limits values in different environments. For example, you might want tighter or looser limits on telemetry if your environment changes such as during thermal vacuum testing.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Limits Set | Name of the limits set. If you have no unique limits sets use the keyword DEFAULT. | True |
| Persistence | Number of consecutive times the telemetry item must be within a different limits range before changing limits state. | True |
| Initial State | Whether limits monitoring for this telemetry item is initially enabled or disabled. Note if you have multiple LIMITS items they should all have the same initial state.<br/><br/>Valid Values: <span class="values">ENABLED, DISABLED</span> | True |
| Red Low Limit | If the telemetry value is less than or equal to this value a Red Low condition will be detected | True |
| Yellow Low Limit | If the telemetry value is less than or equal to this value, but greater than the Red Low Limit, a Yellow Low condition will be detected | True |
| Yellow High Limit | If the telemetry value is greater than or equal to this value, but less than the Red High Limit, a Yellow High condition will be detected | True |
| Red High Limit | If the telemetry value is greater than or equal to this value a Red High condition will be detected | True |
| Green Low Limit | Setting the Green Low and Green High limits defines an "operational limit" which is colored blue by OpenC3. This allows for a distinct desired operational range which is narrower than the green safety limit. If the telemetry value is greater than or equal to this value, but less than the Green High Limit, a Blue operational condition will be detected. | False |
| Green High Limit | Setting the Green Low and Green High limits defines an "operational limit" which is colored blue by OpenC3. This allows for a distinct desired operational range which is narrower than the green safety limit. If the telemetry value is less than or equal to this value, but greater than the Green Low Limit, a Blue operational condition will be detected. | False |

Example Usage:
```ruby
LIMITS DEFAULT 3 ENABLED -80.0 -70.0 60.0 80.0 -20.0 20.0
LIMITS TVAC 3 ENABLED -80.0 -30.0 30.0 80.0
```

#### LIMITS_RESPONSE
**Defines a response class that is called when the limits state of the current item changes**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Response Class Filename | Name of the Ruby or Python file which implements the limits response. This file should be in the target's lib directory. | True |
| Response Specific Options | Variable length number of options that will be passed to the class constructor | False |

Ruby Example:
```ruby
LIMITS_RESPONSE example_limits_response.rb 10
```

Python Example:
```python
LIMITS_RESPONSE example_limits_response.py 10
```

### APPEND_ITEM
**Defines a telemetry item in the current telemetry packet**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Bit Size | Bit size of this telemetry item. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. If Bit Offset is 0 and Bit Size is 0 then this is a derived parameter and the Data Type must be set to 'DERIVED'. | True |
| Data Type | Data Type of this telemetry item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Description | Description for this telemetry item which must be enclosed with quotes | False |
| Endianness | Indicates if the item is to be interpreted in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
APPEND_ITEM PKTID 16 UINT "Packet ID"
```

### ID_ITEM
**Defines a telemetry item in the current telemetry packet. Note, packets defined without one or more ID_ITEMs are "catch-all" packets which will match all incoming data. Normally this is the job of the UNKNOWN packet.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Bit Offset | Bit offset into the telemetry packet of the Most Significant Bit of this item. May be negative to indicate on offset from the end of the packet. | True |
| Bit Size | Bit size of this telemetry item. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. | True |
| Data Type | Data Type of this telemetry item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | True |
| ID Value | The value of this telemetry item that uniquely identifies this telemetry packet | True |
| Description | Description for this telemetry item which must be enclosed with quotes | False |
| Endianness | Indicates if the item is to be interpreted in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
ID_ITEM PKTID 112 16 UINT 1 "Packet ID which must be 1"
```

### APPEND_ID_ITEM
**Defines a telemetry item in the current telemetry packet**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Bit Size | Bit size of this telemetry item. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. | True |
| Data Type | Data Type of this telemetry item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | True |
| ID Value | The value of this telemetry item that uniquely identifies this telemetry packet | True |
| Description | Description for this telemetry item which must be enclosed with quotes | False |
| Endianness | Indicates if the item is to be interpreted in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
APPEND_ID_ITEM PKTID 16 UINT 1 "Packet ID which must be 1"
```

### ARRAY_ITEM
**Defines a telemetry item in the current telemetry packet that is an array**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Bit Offset | Bit offset into the telemetry packet of the Most Significant Bit of this item. May be negative to indicate on offset from the end of the packet. Always use a bit offset of 0 for derived item. | True |
| Item Bit Size | Bit size of each array item | True |
| Item Data Type | Data Type of each array item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Array Bit Size | Total Bit Size of the Array. Zero or Negative values may be used to indicate the array fills the packet up to the offset from the end of the packet specified by this value. | True |
| Description | Description which must be enclosed with quotes | False |
| Endianness | Indicates if the data is to be sent in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
ARRAY_ITEM ARRAY 64 32 FLOAT 320 "Array of 10 floats"
```

### APPEND_ARRAY_ITEM
**Defines a telemetry item in the current telemetry packet that is an array**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the telemety item. Must be unique within the packet. | True |
| Item Bit Size | Bit size of each array item | True |
| Item Data Type | Data Type of each array item<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Array Bit Size | Total Bit Size of the Array. Zero or Negative values may be used to indicate the array fills the packet up to the offset from the end of the packet specified by this value. | True |
| Description | Description which must be enclosed with quotes | False |
| Endianness | Indicates if the data is to be sent in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Example Usage:
```ruby
APPEND_ARRAY_ITEM ARRAY 32 FLOAT 320 "Array of 10 floats"
```

### SELECT_ITEM
**Selects an existing telemetry item for editing**

Must be used in conjunction with SELECT_TELEMETRY to first select the packet. Typically used to override generated values or make specific changes to telemetry that only affect a particular instance of a target used multiple times.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Item | Name of the item to select for modification | True |

Example Usage:
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  SELECT_ITEM TEMP1
    # Define limits for this item, overrides or replaces any existing
    LIMITS DEFAULT 3 ENABLED -90.0 -80.0 80.0 90.0 -20.0 20.0
```

### DELETE_ITEM
<div class="right">(Since 4.4.1)</div>**Delete an existing telemetry item from the packet definition**

Deleting an item from the packet definition does not remove the defined space for that item. Thus unless you redefine a new item, there will be a "hole" in the packet where the data is not accessible. You can use SELECT_TELEMETRY and then ITEM to define a new item.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Item | Name of the item to delete | True |

Example Usage:
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  DELETE_ITEM TEMP4
```

### META
**Stores metadata for the current telemetry packet**

Meta data is user specific data that can be used by custom tools for various purposes. One example is to store additional information needed to generate source code header files.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Meta Name | Name of the metadata to store | True |
| Meta Values | One or more values to be stored for this Meta Name | False |

Example Usage:
```ruby
META FSW_TYPE "struct tlm_packet"
```

### PROCESSOR
**Defines a processor class that executes code every time a packet is received**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Processor Name | The name of the processor | True |
| Processor Class Filename | Name of the Ruby or Python file which implements the processor. This file should be in the target's lib directory. | True |
| Processor Specific Options | Variable length number of options that will be passed to the class constructor. | False |

Ruby Example:
```ruby
PROCESSOR TEMP1HIGH watermark_processor.rb TEMP1
```

Python Example:
```python
PROCESSOR TEMP1HIGH watermark_processor.py TEMP1
```

### ALLOW_SHORT
**Process telemetry packets which are less than their defined length**

Allows the telemetry packet to be received with a data portion that is smaller than the defined size without warnings. Any extra space in the packet will be filled in with zeros by OpenC3.


### HIDDEN
**Hides this telemetry packet from all the OpenC3 tools**

This packet will not appear in Packet Viewer, Telemetry Grapher and Handbook Creator. It also hides this telemetry from appearing in the Script Runner popup helper when writing scripts. The telemetry still exists in the system and can received and checked by scripts.


### ACCESSOR
<div class="right">(Since 5.0.10)</div>**Defines the class used to read and write raw values from the packet**

Defines the class that is used too read raw values from the packet. Defaults to BinaryAccessor. Provided accessors also include JsonAccessor, CborAccessor, HtmlAccessor, and XmlAccessor.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Accessor Class Name | The name of the accessor class | True |

### IGNORE_OVERLAP
<div class="right">(Since 5.16.0)</div>**Ignores any packet items which overlap**

Packet items which overlap normally generate a warning unless each individual item has the OVERLAP keyword. This ignores overlaps across the entire packet.


### VIRTUAL
<div class="right">(Since 5.18.0)</div>**Marks this packet as virtual and not participating in identification**

Used for packet definitions that can be used as structures for items with a given packet.


## SELECT_TELEMETRY
**Selects an existing telemetry packet for editing**

Typically used in a separate configuration file from where the original telemetry is defined to override or add to the existing telemetry definition. Must be used in conjunction with SELECT_ITEM to change an individual item.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | Name of the target this telemetry packet is associated with | True |
| Packet Name | Name of the telemetry packet to select | True |

Example Usage:
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  SELECT_ITEM TEMP1
    # Define limits for this item, overrides or replaces any existing
    LIMITS DEFAULT 3 ENABLED -90.0 -80.0 80.0 90.0 -20.0 20.0
```

## LIMITS_GROUP
**Defines a group of related limits Items**

Limits groups contain telemetry items that can be enabled and disabled together. It can be used to group related limits as a subsystem that can be enabled or disabled as that particular subsystem is powered (for example). To enable a group call the enable_limits_group("NAME") method in Script Runner. To disable a group call the disable_limits_group("NAME") in Script Runner. Items can belong to multiple groups but the last enabled or disabled group "wins". For example, if an item belongs to GROUP1 and GROUP2 and you first enable GROUP1 and then disable GROUP2 the item will be disabled. If you then enable GROUP1 again it will be enabled.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Group Name | Name of the limits group | True |

## LIMITS_GROUP_ITEM
**Adds the specified telemetry item to the last defined LIMITS_GROUP**

Limits group information is typically kept in a separate configuration file in the config/TARGET/cmd_tlm folder named limits_groups.txt.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | Name of the target | True |
| Packet Name | Name of the packet | True |
| Item Name | Name of the telemetry item to add to the group | True |

Example Usage:
```ruby
LIMITS_GROUP SUBSYSTEM
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP1
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP2
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP3
```


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
