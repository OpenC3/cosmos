---
title: Metadata
description: Record user defined metadata in a telemetry packet with inject_tlm
sidebar_custom_props:
  myEmoji: 🏷️
---

Metadata is information about your test or operation that doesn't come from a target. Common examples are the operator's name, the test procedure being run, a serial number, the hardware configuration, or environmental conditions. Recording metadata alongside your telemetry lets you correlate it with the target data, filter on it, and graph or extract it later.

The best way to record metadata in COSMOS is to define a telemetry packet for it and set its values from scripts with [inject_tlm](/docs/guides/scripting-api#inject_tlm). The packet is never received from an interface. It only changes when you inject values into it. Because it is a normal telemetry packet, metadata gets everything other telemetry gets: it is logged, stored in the time series database, available in the Current Value Table, and usable in every COSMOS tool.

:::note[Replaces the metadata APIs]
The `metadata_all`, `metadata_get`, `metadata_set`, `metadata_update`, and `metadata_input` scripting methods are deprecated. Use a metadata packet as described here instead.
:::

## Define a Metadata Target

Put metadata packets in their own target that is not mapped to an interface. Since no interface reads data for this target, its packets can't be accidentally identified from raw interface data and they only change when you call `inject_tlm`. Telemetry for a target without an interface is still decommutated, logged, and stored like any other target.

Add the target to your plugin's `plugin.txt` without an `INTERFACE`:

```cosmos
TARGET METADATA METADATA
```

Then fully declare each metadata packet in `targets/METADATA/cmd_tlm/tlm.txt`. Give every item an explicit type and size, and add descriptions, units, and states just like any other telemetry packet:

```cosmos
TELEMETRY METADATA RUN BIG_ENDIAN "Information about the current test run"
  APPEND_ITEM OPERATOR 256 STRING "Name of the operator running the test"
  APPEND_ITEM PROCEDURE 512 STRING "Test procedure being executed"
  APPEND_ITEM SERIAL_NUMBER 32 UINT "Serial number of the unit under test"
  APPEND_ITEM AMBIENT_TEMP 32 FLOAT "Ambient temperature in the test chamber"
    UNITS Celsius C
    FORMAT_STRING "%0.1f"
  APPEND_ITEM CONFIG 8 UINT "Hardware configuration"
    STATE FLIGHT 0
    STATE ENGINEERING 1
    STATE SIMULATOR 2
```

Best practices for metadata packets:

- **Size strings for the longest value.** `STRING` items have a fixed bit size (8 bits per character), so `256 STRING` holds up to 32 characters. Longer values are truncated.
- **Use states for fixed choices.** States document the allowed values, display as text in every tool, and `inject_tlm` rejects values that aren't one of the states.
- **Group related values into packets.** Values that change together (for example everything set at the start of a test run) belong in the same packet. Values that change independently can go in separate packets so injecting one doesn't record a new sample of the others.
- **Use descriptions and units.** They show up in Telemetry Viewer, Telemetry Grapher, Data Extractor, and code completion just like other telemetry.

## Setting Metadata

Set metadata by calling `inject_tlm` with a hash of item names and values. Each call creates a new packet with the current time. Items you leave out of the hash keep their current values, so you can update only the values that changed.

<Tabs groupId="script-language">
<TabItem value="python" label="Python Example">

```python
# Set all the metadata at the start of a test
inject_tlm(
    "METADATA",
    "RUN",
    {
        "OPERATOR": "Jane Smith",
        "PROCEDURE": "Thermal Vacuum Cycle 3",
        "SERIAL_NUMBER": 1234,
        "AMBIENT_TEMP": 21.5,
        "CONFIG": "ENGINEERING",
    },
)

# Later, update a single value. The other items keep their current values.
inject_tlm("METADATA", "RUN", {"AMBIENT_TEMP": -40.0})
```

</TabItem>

<TabItem value="ruby" label="Ruby Example">

```ruby
# Set all the metadata at the start of a test
inject_tlm("METADATA", "RUN", {
  "OPERATOR" => "Jane Smith",
  "PROCEDURE" => "Thermal Vacuum Cycle 3",
  "SERIAL_NUMBER" => 1234,
  "AMBIENT_TEMP" => 21.5,
  "CONFIG" => "ENGINEERING"
})

# Later, update a single value. The other items keep their current values.
inject_tlm("METADATA", "RUN", { "AMBIENT_TEMP" => -40.0 })
```

</TabItem>
</Tabs>

### Prompting the Operator

To have the operator enter metadata, combine the [user input methods](/docs/guides/scripting-api#retrieving-user-input) with `inject_tlm`:

<Tabs groupId="script-language">
<TabItem value="python" label="Python Example">

```python
operator = ask_string("Enter your name")
config = combo_box("Select the hardware configuration", "FLIGHT", "ENGINEERING", "SIMULATOR")
inject_tlm("METADATA", "RUN", {"OPERATOR": operator, "CONFIG": config})
```

</TabItem>

<TabItem value="ruby" label="Ruby Example">

```ruby
operator = ask_string("Enter your name")
config = combo_box("Select the hardware configuration", "FLIGHT", "ENGINEERING", "SIMULATOR")
inject_tlm("METADATA", "RUN", { "OPERATOR" => operator, "CONFIG" => config })
```

</TabItem>
</Tabs>

## Reading Metadata

Read the current metadata the same way you read any telemetry:

<Tabs groupId="script-language">
<TabItem value="python" label="Python Example">

```python
operator = tlm("METADATA RUN OPERATOR")
values = get_tlm_packet("METADATA", "RUN")
check("METADATA RUN CONFIG == 'ENGINEERING'")
```

</TabItem>

<TabItem value="ruby" label="Ruby Example">

```ruby
operator = tlm("METADATA RUN OPERATOR")
values = get_tlm_packet("METADATA", "RUN")
check("METADATA RUN CONFIG == 'ENGINEERING'")
```

</TabItem>
</Tabs>

Since metadata is stored like any other telemetry, you can also:

- Display it next to target telemetry on a [Telemetry Viewer](/docs/tools/tlm-viewer) screen.
- Graph numeric metadata alongside target data in [Telemetry Grapher](/docs/tools/tlm-grapher).
- Extract the history of metadata values over a time range with [Data Extractor](/docs/tools/data-extractor), along with the target data from the same period.
- Look at every metadata packet that was injected with [Packet Viewer](/docs/tools/packet-viewer) or [Data Viewer](/docs/tools/data-viewer).

## Migrating from the Metadata APIs

| Deprecated method | Replacement                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| metadata_set      | `inject_tlm` with every metadata item                                                                                      |
| metadata_update   | `inject_tlm` with only the items that changed                                                                              |
| metadata_get      | [tlm](/docs/guides/scripting-api#tlm-tlm_raw-tlm_formatted) or [get_tlm_packet](/docs/guides/scripting-api#get_tlm_packet) |
| metadata_all      | Data Extractor or Telemetry Grapher over the time range you need                                                           |
| metadata_input    | [User input methods](/docs/guides/scripting-api#retrieving-user-input) followed by `inject_tlm`                            |

Unlike the old metadata APIs, which accepted any keys, a metadata packet has a fixed set of items. Declare an item for every value you want to record.

:::info[Permissions]
`inject_tlm` requires the `tlm_set` permission for the target. In COSMOS Enterprise, make sure the roles of users who record metadata include it.
:::
