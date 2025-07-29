---
sidebar_position: 9
title: Conversions
description: Conversions to apply to command parameters and telemetry items
sidebar_custom_props:
  myEmoji: 🔄
---

<!-- Be sure to edit _conversions.md because conversions.md is a generated file -->

# Overview

Conversions can be applied to both command parameters and telemetry items to modify the values sent to and received from targets. To apply a conversion to a command you use the [WRITE_CONVERSION](/docs/configuration/command#write_conversion) keyword. To apply a conversion to a telemetry item you use the [READ_CONVERSION](/docs/configuration/telemetry#read_conversion) keyword.

## Custom Conversions

You can easily create your own custom conversions by using the [Conversion Code Generator](/docs/getting-started/generators#conversion-generator). To generate a telemetry conversion you must be inside an existing COSMOS plugin. The generator takes both a target name and the conversion name. For example if your plugin is called `openc3-cosmos-gse` and you have an existing target named `GSE`:

```bash
openc3-cosmos-gse % openc3.sh cli generate conversion GSE double --python
Conversion targets/GSE/lib/double_conversion.py successfully generated!
To use the conversion add the following to a telemetry item:
  READ_CONVERSION double_conversion.py
```

Note: To create a Ruby conversion simply replace `--python` with `--ruby`.

The above command creates a conversion called `double_conversion.py` at `targets/GSE/lib/double_conversion.py`. The code which is generated looks like the following:

```python
from openc3.conversions.conversion import Conversion
# Using tlm() requires the following:
# from openc3.api.tlm_api import tlm

# Custom conversion class
# See https://docs.openc3.com/docs/configuration/telemetry#read_conversion
class DoubleConversion(Conversion):
    def __init__(self):
        super().__init__()
        # Should be one of 'INT', 'UINT', 'FLOAT', 'STRING', 'BLOCK'
        self.converted_type = 'STRING'
        # Size of the converted type in bits
        # Use 0 for 'STRING' or 'BLOCK' where the size can be variable
        self.converted_bit_size = 0

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(self, value, packet, buffer):
        # Read values from the packet and do a conversion
        # Used for DERIVED items that don't have a value
        # item1 = packet.read("ITEM1") # returns CONVERTED value (default)
        # item2 = packet.read("ITEM2", 'RAW') # returns RAW value
        # return (item1 + item2) / 2
        #
        # Perform conversion logic directly on value
        # Used when conversion is applied to a regular (not DERIVED) item
        # NOTE: You can also use packet.read("ITEM") to get additional values
        # return value / 2 * packet.read("OTHER_ITEM")
        return value
```

There are a lot of comments to help you know what to do. The primary things to modify are the `converted_type`, `converted_bit_size`, and `call` method.

### converted_type

The `converted_type` is the resulting type of the converted value. It lets consumers of the converted value know the resulting type. In our case we're doubling the input value and since this could be applied to an unsigned integer as well as a floating point value we'll choose `FLOAT`.

```python
    self.converted_type = 'FLOAT'
```

### converted_bit_size

The `converted_bit_size` is the resulting size of the converted value. It lets consumers of the converted value know the resulting size. Since we chose `FLOAT` as the type we'll choose `32` as the bit size. We could have also chosen `64` bits. Sometimes you know the type and size of the resulting conversion and can simply hard code them. Other times you need to pass them in as parameters and let the user decide.

```python
    self.converted_bit_size = 32
```

### call

The call method is where the actual conversion logic is implemented. In our case we want to double the input value so we simply return the value multiplied by 2. The final result with comments removed looks like the following:

```python
from openc3.conversions.conversion import Conversion
class DoubleConversion(Conversion):
    def __init__(self):
        super().__init__()
        self.converted_type = 'FLOAT'
        self.converted_bit_size = 32

    def call(self, value, packet, buffer):
        return value * 2
```

### Apply Conversion

Now that we have implemented the conversion logic we need to apply it to a telemetry item by adding the line `READ_CONVERSION double_conversion.py` in the [telemetry](/docs/configuration/telemetry) definition file. This could look something like this:

```bash
TELEMETRY GSE DATA BIG_ENDIAN "Data packet"
  ... # Header items
  APPEND_ITEM VALUE 16 UINT "Value I want to double"
    READ_CONVERSION double_conversion.py
```

# Built-in Conversions

## GENERIC_CONVERSION

**Applies a simple conversion to a single telemetry item.**

The generic conversion is meant to be a quick and easy way to apply a conversion to a single telemetry item. It must be parsed and evaluated and thus is not as performant as a dedicated conversion class.

| Parameter | Description                                                                                                                        | Required                          |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Type      | Data type after the conversion is applied<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, TIME</span> | False (warning will be generated) |
| Size      | Data size in bits after the conversion is applied                                                                                  | False (warning will be generated) |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
GENERIC_READ_CONVERSION_START FLOAT 32
    packet.read('TEMP1') / 1_000_000
GENERIC_READ_CONVERSION_END
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
GENERIC_READ_CONVERSION_START FLOAT 32
  packet.read('TEMP1') / 1_000_000
GENERIC_READ_CONVERSION_END
```

</TabItem>
</Tabs>


## BIT_REVERSE_CONVERSION
**Reverses the bits of the current telemetry item. Can be used as both a read and write conversion.**


<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/bit_reverse_conversion.py
WRITE_CONVERSION openc3/conversions/bit_reverse_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION bit_reverse_conversion.rb
WRITE_CONVERSION bit_reverse_conversion.rb
```
</TabItem>
</Tabs>

## IP_READ_CONVERSION
**Reads a packed 32 bit integer into an IP address string**

This command reads a packed 32 bit integer into an IP address string.
For example, 0xFFFF8000 would be converted to '255.255.128.0'.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/ip_read_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION ip_read_conversion.rb
```
</TabItem>
</Tabs>

## IP_WRITE_CONVERSION
**Write an ip address string into a packed 32 bit integer**

This command writes an IP address string into a packed 32 bit integer. The IP address
string should be in the format 'x.x.x.x' where x is a number between 0 and 255.
For example, '255.255.128.0' would be converted to 0xFFFF8000.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
WRITE_CONVERSION openc3/conversions/ip_write_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
WRITE_CONVERSION ip_write_conversion.rb
```
</TabItem>
</Tabs>

## OBJECT_READ_CONVERSION
**Reads values from the given packet object**

This command reads all the values from the given packet object. The values are
returned as a Ruby hash or Python dict. The packet object must be defined in the target's configuration.


| Parameter | Description | Required |
|-----------|-------------|----------|
| Command or Telemetry | Whether the packet is a command or telemetry<br/><br/>Valid Values: <span class="values">CMD, TLM</span> | True |
| Target Name | Name of the target | True |
| Packet Name | Name of the packet | True |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/object_read_conversion.py CMD INST COLLECT
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION object_read_conversion.rb CMD INST COLLECT
```
</TabItem>
</Tabs>

## OBJECT_WRITE_CONVERSION
**Writes values into the given packet object**

This command writes values into the given packet object. The values are specified
in a hash format where the keys are the field names in the packet and the values
are the values to write. The packet object must be defined in the target's configuration.


| Parameter | Description | Required |
|-----------|-------------|----------|
| Command or Telemetry | Whether the packet is a command or telemetry<br/><br/>Valid Values: <span class="values">CMD, TLM</span> | True |
| Target Name | Name of the target | True |
| Packet Name | Name of the packet | True |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
WRITE_CONVERSION openc3/conversions/object_write_conversion.py CMD INST COLLECT
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
WRITE_CONVERSION object_write_conversion.rb CMD INST COLLECT
```
</TabItem>
</Tabs>

## PACKET_TIME_FORMATTED_CONVERSION
**Converts the packet time to a formatted string like "YYYY/MM/DD HH:MM:SS.US"**

This in an internal conversion which is automatically applied to the
'PACKET_TIMEFORMATTED' derived telemetry item. It is typically not explicitly used.
For more information see the [Received Time and Packet Time](/docs/configuration/telemetry#received-time-and-packet-time) documentation.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/packet_time_formatted_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION packet_time_formatted_conversion.rb
```
</TabItem>
</Tabs>

## PACKET_TIME_SECONDS_CONVERSION
**Converts the packet time to a floating point number of seconds since the epoch**

This in an internal conversion which is automatically applied to the
'PACKET_TIMESECONDS' derived telemetry item. It is typically not explicitly used.
For more information see the [Received Time and Packet Time](/docs/configuration/telemetry#received-time-and-packet-time) documentation.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/packet_time_seconds_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION packet_time_seconds_conversion.rb
```
</TabItem>
</Tabs>

## POLYNOMIAL_CONVERSION
**Adds a polynomial conversion factor to the current item. Can be used as both a read and write conversion.**

For commands, the conversion factor is applied to raw value set by the user (via tool or script) before it is written into the binary command packet and sent. For telemetry, the conversion factor is applied to the raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog.

| Parameter | Description | Required |
|-----------|-------------|----------|
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/polynomial_conversion.py 10 0.5 0.25
# Since this is a common conversion it has an alias:
POLY_READ_CONVERSION 10 0.5 0.25

WRITE_CONVERSION openc3/conversions/polynomial_conversion.py 10 0.5 0.25
# Since this is a common conversion it has an alias:
POLY_WRITE_CONVERSION 10 0.5 0.25
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION polynomial_conversion.rb 10 0.5 0.25
# Since this is a common conversion it has an alias:
POLY_READ_CONVERSION 10 0.5 0.25

WRITE_CONVERSION polynomial_conversion.rb 10 0.5 0.25
# Since this is a common conversion it has an alias:
POLY_WRITE_CONVERSION 10 0.5 0.25
```
</TabItem>
</Tabs>

## PROCESSOR_CONVERSION
**Read a value from a processor**

This command reads a value from a processor. The value is read from the
processor's available values. The processor must be defined in the target's configuration.
See the [Processor](/docs/configuration/processors) documentation for more information.


| Parameter | Description | Required |
|-----------|-------------|----------|
| Processor Name | Name of the processor | True |
| Processor Value | Published processor value | True |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
PROCESSOR TEMP1WATER openc3/conversions/watermark_processor.py TEMP1
ITEM TEMP1HIGH 0 0 DERIVED "High-water mark for TEMP1"
  READ_CONVERSION openc3/conversions/processor_conversion.py TEMP1WATER HIGH_WATER
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
PROCESSOR TEMP1WATER watermark_processor.rb TEMP1
ITEM TEMP1HIGH 0 0 DERIVED "High-water mark for TEMP1"
  READ_CONVERSION processor_conversion.rb TEMP1WATER HIGH_WATER
```
</TabItem>
</Tabs>

## RECEIVED_COUNT_CONVERSION
**Converts the packet received count to a UINT 32 value**

This in an internal conversion which is automatically applied to the
'RECEIVED_COUNT' derived telemetry item. It is typically not explicitly used.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/received_count_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION received_count_conversion.rb
```
</TabItem>
</Tabs>

## RECEIVED_TIME_FORMATTED_CONVERSION
**Converts the packet received time to a formatted string like "YYYY/MM/DD HH:MM:SS.US"**

This in an internal conversion which is automatically applied to the
'RECEIVED_TIMEFORMATTED' derived telemetry item. It is typically not explicitly used.
For more information see the [Received Time and Packet Time](/docs/configuration/telemetry#received-time-and-packet-time) documentation.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/received_time_formatted_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION received_time_formatted_conversion.rb
```
</TabItem>
</Tabs>

## RECEIVED_TIME_SECONDS_CONVERSION
**Converts the packet received to a floating point number of seconds since the epoch**

This in an internal conversion which is automatically applied to the
'RECEIVED_TIMESECONDS' derived telemetry item. It is typically not explicitly used.
For more information see the [Received Time and Packet Time](/docs/configuration/telemetry#received-time-and-packet-time) documentation.



<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/received_time_formatted_conversion.py
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION received_time_formatted_conversion.rb
```
</TabItem>
</Tabs>

## SEGMENTED_POLYNOMIAL_CONVERSION
**Adds a segmented polynomial conversion factor to the current item. Can be used as both a read and write conversion.**

For commands, this conversion factor is applied to the raw value set by the user (via tool or script) before it is written into the binary command packet and sent. For telemetry, the conversion factor is applied to the raw value in the telemetry packet before it is displayed to the user. The user still has the ability to see the raw unconverted value in a details dialog.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Lower Bound | Defines the lower bound of the range of values that this segmented polynomial applies to. Is ignored for the segment with the smallest lower bound. | True |
| C0 | Coefficient | True |
| Cx | Additional coefficient values for the conversion. Any order polynomial conversion may be used so the value of 'x' will vary with the order of the polynomial. Note that larger order polynomials take longer to process than shorter order polynomials, but are sometimes more accurate. | False |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/segmented_polynomial_conversion.py 0 10 0.5 0.25 # Apply the conversion to all values < 50
# Since this is a common conversion it has an alias:
SEG_POLY_READ_CONVERSION 10 0.5 0.25 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_READ_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_READ_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100

WRITE_CONVERSION openc3/conversions/segmented_polynomial_conversion.py 0 10 0.5 0.25 # Apply the conversion to all values < 50
# Since this is a common conversion it has an alias:
SEG_POLY_WRITE_CONVERSION 10 0.5 0.25 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_WRITE_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_WRITE_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION segmented_polynomial_conversion.rb 0 10 0.5 0.25 # Apply the conversion to all values < 50
# Since this is a common conversion it has an alias:
SEG_POLY_READ_CONVERSION 10 0.5 0.25 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_READ_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_READ_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100

WRITE_CONVERSION segmented_polynomial_conversion.rb 0 10 0.5 0.25 # Apply the conversion to all values < 50
# Since this is a common conversion it has an alias:
SEG_POLY_WRITE_CONVERSION 10 0.5 0.25 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_WRITE_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_WRITE_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100
```
</TabItem>
</Tabs>

## UNIX_TIME_CONVERSION
**Converts values to a native Ruby or Python time object**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Seconds Item Name | The name of the item which contains the seconds since the epoch. | True |
| Microseconds Item Name | The name of the item which contains the microseconds since the epoch. | False |
| Seconds Type | How to read the seconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |
| Microseconds Type | How to read the microseconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/unix_time_conversion.py TIMESEC TIMEUS
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION unix_time_conversion.rb TIMESEC TIMEUS
```
</TabItem>
</Tabs>

## UNIX_TIME_FORMATTED_CONVERSION
**Converts values to a formatted time string like "YYYY/MM/DD HH:MM:SS.US"**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Seconds Item Name | The name of the item which contains the seconds since the epoch. | True |
| Microseconds Item Name | The name of the item which contains the microseconds since the epoch. | False |
| Seconds Type | How to read the seconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |
| Microseconds Type | How to read the microseconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/unix_time_formatted_conversion.py TIMESEC TIMEUS
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION unix_time_formatted_conversion.rb TIMESEC TIMEUS
```
</TabItem>
</Tabs>

## UNIX_TIME_SECONDS_CONVERSION
**Converts values to a floating point number of seconds since the epoch**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Seconds Item Name | The name of the item which contains the seconds since the epoch. | True |
| Microseconds Item Name | The name of the item which contains the microseconds since the epoch. | False |
| Seconds Type | How to read the seconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |
| Microseconds Type | How to read the microseconds item. Defaults to 'RAW'.<br/><br/>Valid Values: <span class="values">RAW, CONVERTED</span> | False |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
READ_CONVERSION openc3/conversions/unix_time_seconds_conversion.py TIMESEC TIMEUS
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
READ_CONVERSION unix_time_seconds_conversion.rb TIMESEC TIMEUS
```
</TabItem>
</Tabs>

