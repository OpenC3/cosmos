---
sidebar_position: 8
title: Tables
---

<!-- Be sure to edit _table.md because table.md is a generated file -->

## Table Definition Files

Table definition files define the binary tables that can be displayed in COSMOS [Table Manager](../tools/table-manager.md)
. Table definitions are defined in the target's tables/config directory and are typically named after the table such as `PPSSelectionTable_def.txt`. The `_def.txt` extension helps to identify the file as a table definition. Table definitions can be combined using the `TABLEFILE` keyword. This allows you to build individual table components into a larger binary.

The Table definition files share a lot of similarity with the [Command Configuration](command.md). You have the same data types: INT, UINT, FLOAT, STRING, BLOCK. These correspond to integers, unsigned integers, floating point numbers, strings and binary blocks of data.

<div style={{"clear": 'both'}}></div>

# Table Keywords


## TABLEFILE
**Specify another file to open and process for table definitions**

| Parameter | Description | Required |
|-----------|-------------|----------|
| File Name | Name of the file. The file will be looked for in the directory of the current definition file. | True |

## TABLE
**Start a new table definition**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the table in quotes. The name will appear on the GUI tab. | True |
| Endianness | Indicates if the data in this table is in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | True |
| Display | Indicates the table contains KEY_VALUE rows (e.g. each row is unique), or a ROW_COLUMN table with identical rows containing different values.<br/><br/>Valid Values: <span class="values">KEY_VALUE, ROW_COLUMN</span> | False |

When Display is KEY_VALUE the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Description | Description of the table in quotes. The description is used in mouseover popups and status line information. | False |

When Display is ROW_COLUMN the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Rows | The number of rows in the table | False |
| Description | Description of the table in quotes. The description is used in mouseover popups and status line information. | False |

## TABLE Modifiers
The following keywords must follow a TABLE keyword.

### PARAMETER
**Defines a parameter in the current table**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the parameter. Must be unique within the table. | True |
| Bit Offset | Bit offset into the table of the Most Significant Bit of this parameter. May be negative to indicate on offset from the end of the table. Always use a bit offset of 0 for derived parameters. | True |
| Bit Size | Bit size of this parameter. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. If Bit Offset is 0 and Bit Size is 0 then this is a derived parameter and the Data Type must be set to 'DERIVED'. | True |
| Data Type | Data Type of this parameter<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

When Data Type is INT, UINT, FLOAT, DERIVED the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Minimum Value | Minimum allowed value for this parameter | True |
| Maximum Value | Maximum allowed value for this parameter | True |
| Default Value | Default value for this parameter. You must provide a default but if you mark the parameter REQUIRED then scripts will be forced to specify a value. | True |
| Description | Description for this parameter which must be enclosed with quotes | False |
| Endianness | Indicates if the data in this command is to be sent in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

When Data Type is STRING, BLOCK the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Default Value | Default value for this parameter. You must provide a default but if you mark the parameter REQUIRED then scripts will be forced to specify a value. | True |
| Description | Description for this parameter which must be enclosed with quotes | False |
| Endianness | Indicates if the data in this command is to be sent in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

### PARAMETER Modifiers
The following keywords must follow a PARAMETER keyword.

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

If an item's bit offset overlaps another item, OpenC3 issues a warning. This keyword explicitly allows an item to overlap another and suppresses the warning message.


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

#### REQUIRED
**Parameter is required to be populated in scripts**

When sending the command via Script Runner a value must always be given for the current command parameter. This prevents the user from relying on a default value. Note that this does not affect Command Sender which will still populate the field with the default value provided in the PARAMETER definition.


#### MINIMUM_VALUE
**Override the defined minimum value**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Value | The new minimum value for the parameter | True |

#### MAXIMUM_VALUE
**Override the defined maximum value**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Value | The new maximum value for the parameter | True |

#### DEFAULT_VALUE
**Override the defined default value**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Value | The new default value for the parameter | True |

#### STATE
**Defines a key/value pair for the current command parameter**

Key value pairs allow for user friendly strings. For example, you might define states for ON = 1 and OFF = 0. This allows the word ON to be used rather than the number 1 when sending the command parameter and allows for much greater clarity and less chance for user error.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Key | The string state name | True |
| Value | The numerical state value | True |
| Hazardous / Disable Messages | Indicates the state is hazardous. This will cause a popup to ask for user confirmation when sending this command. For non-hazardous states you can also set DISABLE_MESSAGES which will not print the command when using that state.<br/><br/>Valid Values: <span class="values">HAZARDOUS</span> | False |
| Hazardous Description | String describing why this state is hazardous | False |

Example Usage:
```ruby
APPEND_PARAMETER ENABLE 32 UINT 0 1 0 "Enable setting"
  STATE FALSE 0
  STATE TRUE 1
APPEND_PARAMETER STRING 1024 STRING "NOOP" "String parameter"
  STATE "NOOP" "NOOP" DISABLE_MESSAGES
  STATE "ARM LASER" "ARM LASER" HAZARDOUS "Arming the laser is an eye safety hazard"
  STATE "FIRE LASER" "FIRE LASER" HAZARDOUS "WARNING! Laser will be fired!"
```

#### WRITE_CONVERSION
**Applies a conversion when writing the current command parameter**

Conversions are implemented in a custom Ruby or Python file which should be
located in the target's lib folder. The class must inherit from Conversion.
It must implement the `initialize` (Ruby) or `__init__` (Python) method if it
takes extra parameters and must always implement the `call` method. The conversion
factor is applied to the value entered by the user before it is written into
the binary command packet and sent.

:::info Multiple write conversions on command parameters
When a command is built, each item gets written (and write conversions are run)
to set the default value. Then items are written (again write conversions are run)
with user provided values. Thus write conversions can be run twice. Also there are
no guarantees which parameters have already been written. The packet itself has a
given_values() method which can be used to retrieve a hash of the user provided
values to the command. That can be used to check parameter values passed in.
:::


| Parameter | Description | Required |
|-----------|-------------|----------|
| Class Filename | The filename which contains the Ruby or Python class. The filename must be named after the class such that the class is a CamelCase version of the underscored filename. For example, 'the_great_conversion.rb' should contain 'class TheGreatConversion'. | True |
| Parameter | Additional parameter values for the conversion which are passed to the class constructor. | False |

Ruby Example:
```ruby
WRITE_CONVERSION the_great_conversion.rb 1000

Defined in the_great_conversion.rb:

require 'openc3/conversions/conversion'
module OpenC3
  class TheGreatConversion < Conversion
    def initialize(multiplier)
      super()
      @multiplier = multiplier.to_f
    end
    def call(value, packet, buffer)
      return value * multiplier
    end
  end
end
```

Python Example:
```python
WRITE_CONVERSION the_great_conversion.py 1000

Defined in the_great_conversion.py:

from openc3.conversions.conversion import Conversion
class TheGreatConversion(Conversion):
    def __init__(self, multiplier):
        super().__init__()
        self.multiplier = float(multiplier)
    def call(self, value, packet, buffer):
        return value * multiplier
```

#### POLY_WRITE_CONVERSION
**Adds a polynomial conversion factor to the current command parameter**

The conversion factor is applied to the value entered by the user before it is written into the binary command packet and sent.

| Parameter | Description | Required |
|-----------|-------------|----------|
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

Example Usage:
```ruby
POLY_WRITE_CONVERSION 10 0.5 0.25
```

#### SEG_POLY_WRITE_CONVERSION
**Adds a segmented polynomial conversion factor to the current command parameter**

This conversion factor is applied to the value entered by the user before it is written into the binary command packet and sent.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Lower Bound | Defines the lower bound of the range of values that this segmented polynomial applies to. Is ignored for the segment with the smallest lower bound. | True |
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

Example Usage:
```ruby
SEG_POLY_WRITE_CONVERSION 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_WRITE_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_WRITE_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100
```

#### GENERIC_WRITE_CONVERSION_START
**Start a generic write conversion**

Adds a generic conversion function to the current command parameter.
This conversion factor is applied to the value entered by the user before it
is written into the binary command packet and sent. The conversion is specified
as Ruby or Python code that receives two implied parameters. 'value' which is the raw
value being written and 'packet' which is a reference to the command packet
class (Note, referencing the packet as 'myself' is still supported for backwards
compatibility). The last line of code should return the converted
value. The GENERIC_WRITE_CONVERSION_END keyword specifies that all lines of
code for the conversion have been given.

:::info Multiple write conversions on command parameters
When a command is built, each item gets written (and write conversions are run)
to set the default value. Then items are written (again write conversions are run)
with user provided values. Thus write conversions can be run twice. Also there are
no guarantees which parameters have already been written. The packet itself has a
given_values() method which can be used to retrieve a hash of the user provided
values to the command. That can be used to check parameter values passed in.
:::


:::warning
Generic conversions are not a good long term solution. Consider creating a conversion class and using WRITE_CONVERSION instead. WRITE_CONVERSION is easier to debug and higher performance.
:::


Ruby Example:
```ruby
APPEND_PARAMETER ITEM1 32 UINT 0 0xFFFFFFFF 0
  GENERIC_WRITE_CONVERSION_START
    return (value * 1.5).to_i # Convert the value by a scale factor
  GENERIC_WRITE_CONVERSION_END
```

Python Example:
```python
APPEND_PARAMETER ITEM1 32 UINT 0 0xFFFFFFFF 0
  GENERIC_WRITE_CONVERSION_START
    return int(value * 1.5) # Convert the value by a scale factor
  GENERIC_WRITE_CONVERSION_END
```

#### GENERIC_WRITE_CONVERSION_END
**Complete a generic write conversion**


#### OVERFLOW
**Set the behavior when writing a value overflows the type**

By default OpenC3 throws an error if you try to write a value which overflows its specified type, e.g. writing 255 to a 8 bit signed value. Setting the overflow behavior also allows for OpenC3 to 'TRUNCATE' the value by eliminating any high order bits. You can also set 'SATURATE' which causes OpenC3 to replace the value with the maximum or minimum allowable value for that type. Finally you can specify 'ERROR_ALLOW_HEX' which will allow for a maximum hex value to be written, e.g. you can successfully write 255 to a 8 bit signed value.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Behavior | How OpenC3 treats an overflow value. Only applies to signed and unsigned integer data types.<br/><br/>Valid Values: <span class="values">ERROR, ERROR_ALLOW_HEX, TRUNCATE, SATURATE</span> | True |

Example Usage:
```ruby
OVERFLOW TRUNCATE
```

#### HIDDEN
**Indicates that the parameter should not be shown to the user in the Table Manager GUI**

Hidden parameters still exist and will be saved to the resulting binary. This is useful for padding and other essential but non-user editable fields.


#### UNEDITABLE
**Indicates that the parameter should be shown to the user but not editable.**

Uneditable parameters are useful for control fields which the user may be interested in but should not be able to edit.


### APPEND_PARAMETER
**Defines a parameter in the current table**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the parameter. Must be unique within the table. | True |
| Bit Size | Bit size of this parameter. Zero or Negative values may be used to indicate that a string fills the packet up to the offset from the end of the packet specified by this value. If Bit Offset is 0 and Bit Size is 0 then this is a derived parameter and the Data Type must be set to 'DERIVED'. | True |
| Data Type | Data Type of this parameter<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

When Data Type is INT, UINT, FLOAT, DERIVED the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Minimum Value | Minimum allowed value for this parameter | True |
| Maximum Value | Maximum allowed value for this parameter | True |
| Default Value | Default value for this parameter. You must provide a default but if you mark the parameter REQUIRED then scripts will be forced to specify a value. | True |
| Description | Description for this parameter which must be enclosed with quotes | False |
| Endianness | Indicates if the data in this command is to be sent in Big Endian or Little Endian format. See guide on [Little Endian Bitfields](../guides/little-endian-bitfields.md).<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

When Data Type is STRING, BLOCK the remaining parameters are:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Default Value | Default value for this parameter. You must provide a default but if you mark the parameter REQUIRED then scripts will be forced to specify a value. | True |
| Description | Description for this parameter which must be enclosed with quotes | False |
| Endianness | Indicates if the data in this command is to be sent in Big Endian or Little Endian format<br/><br/>Valid Values: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

## SELECT_TABLE
**Select an existing table for editing, typically done to override an existing definition**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Table | The name of the existing table | True |

## DEFAULT
**Specify default values for a SINGLE row in a multi-column table**

If you have multiple rows you need a DEFAULT line for each row. If all your rows are identical consider using ERB as shown in the OpenC3 demo.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Default values | A STATE value or data value corresponding to the data type | False |


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
