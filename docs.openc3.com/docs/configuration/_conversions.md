---
sidebar_position: 9
title: Conversions
description: Conversions to apply to command parameters and telemetry items
sidebar_custom_props:
  myEmoji: 🔄
---

{/* Be sure to edit _conversions.md because conversions.md is a generated file */}

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

There are a lot of comments to help you implement the `call` method.

### call

The call method is where the actual conversion logic is implemented. In our case we want to double the input value so we simply return the value multiplied by 2. The final result with comments removed looks like the following:

```python
from openc3.conversions.conversion import Conversion
class DoubleConversion(Conversion):
    def call(self, value, packet, buffer):
        return value * 2
```

### Apply Conversion

Now that we have implemented the conversion logic we need to apply it to a telemetry item by adding the line `READ_CONVERSION double_conversion.py` in the [telemetry](/docs/configuration/telemetry) definition file. We also apply a `CONVERTED_DATA` keyword to indicate we're changing the data type.

```bash
TELEMETRY GSE DATA BIG_ENDIAN "Data packet"
  ... # Header items
  APPEND_ITEM VALUE 16 UINT "Value I want to double"
    READ_CONVERSION double_conversion.py
    CONVERTED_DATA 32 FLOAT
```

# Built-in Conversions

## GENERIC_CONVERSION

**Applies a simple conversion to a single telemetry item.**

The generic conversion is meant to be a quick and easy way to apply a conversion to a single telemetry item. It must be parsed and evaluated and thus is not as performant as a dedicated conversion class. To specify the bit size, type, and array size of the converted data, use the CONVERTED_DATA keyword.

| Parameter | Description                                                                                                                                                  | Required                          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| Type      | Data type after the conversion is applied<br/><br/>Valid Values: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, BOOL, ARRAY, OBJECT, ANY, TIME</span> | False (warning will be generated) |
| Size      | Data size in bits after the conversion is applied                                                                                                            | False (warning will be generated) |

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
GENERIC_READ_CONVERSION_START
    packet.read('TEMP1') / 1_000_000
GENERIC_READ_CONVERSION_END
CONVERTED_DATA 32 FLOAT
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
GENERIC_READ_CONVERSION_START
  packet.read('TEMP1') / 1_000_000
GENERIC_READ_CONVERSION_END
CONVERTED_DATA 32 FLOAT
```

</TabItem>
</Tabs>

COSMOS_META
