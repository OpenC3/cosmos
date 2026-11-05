---
title: Data Viewer
description: View packet or item data
sidebar_custom_props:
  myEmoji: 🖥️
---

## Introduction

Data Viewer allows you to view packet data or individual item data in both the past and in real time.

![Data Viewer](/img/data_viewer/data_viewer.png)

## Data Viewer Menus

### File Menu Items

{/* Image sized to match up with bullets */}

<img src={require('@site/static/img/data_viewer/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 6 + 'em'}} />

- Opens a saved configuration
- Save the current configuration
- Reset the configuration (default settings)

#### Open Configuration

The Open Configuration dialog displays a list of all saved configurations. You select a configuration and then click Ok to load it. You can delete existing configurations by clicking the Trash icon next to a configuration name.

#### Save Configuration

The Save Configuration dialog also displays a list of all saved configurations. You click the Configuration Name text field, enter the name of your new configuration, and click Ok to save. You can delete existing configurations by clicking the Trash icon next to a configuration name.

## Selecting a Time Range

The collapsible panel at the top of the tool sets the time range that is streamed when you click Start.

- **Start Date / Start Time** are required and default to the current date and time.
- **End Date / End Time** are optional. Leave them blank to stream indefinitely.

Data Viewer plays back logged data from the Start time up to the End time, then continues in real time if the End time is in the future or is blank. A start time in the future, or a start time equal to the end time, is rejected with a warning.

Click **Start** to begin streaming and **Stop** to disconnect. Changing the time range requires stopping and starting again.

## Tabs and Components

Data Viewer organizes displays into tabs. Each tab holds a single component which is fed by one or more packets or items.

Click the new tab icon to create a tab. This brings up the Configure Component dialog. First you select the component you want to use to visualize the data. Next you add packets (or items) which will populate the component. Finally click Create to see the component visualization.

![Add Component](/img/data_viewer/add_component.png)

Right click a tab to rename it. Click the X on a tab to delete it.

### Built-in Components

| Component               | Input   | Description                                                                       |
| ----------------------- | ------- | --------------------------------------------------------------------------------- |
| COSMOS Packet Raw/Decom | Packets | Dumps whole packets as a hex/ASCII buffer (Raw) or as item name / value text (Decom) |
| COSMOS Item Value       | Items   | Prints selected items on a single line per packet, e.g. `TEMP1: 10.0  TEMP2: 20.0`   |
| COSMOS Event Message    | Items   | Prints just the item values, one per line, expanding arrays into individual lines    |

Plugins can add their own components. Any widget named `DATAVIEWER<NAME>` (declared with `WIDGET DATAVIEWER<NAME>` in plugin.txt) is automatically listed in the Select Component dropdown. See the [demo plugin](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo) `DataviewertimeWidget` and `DataviewerquaternionWidget` for examples.

### Adding Packets and Items

In the Configure Component dialog you choose **Command** or **Telemetry**, then pick the target and packet (and item, for item based components) and click Add Packet / Add Item. Repeat to feed multiple packets into the same component.

Each packet is added with a **Mode**:

- **Raw** streams the packet's binary buffer. No value type applies, so the ValueType column shows `N/A`.
- **Decom** streams the decommutated version of the packet. A **Value Type** must be selected.

Item based components (COSMOS Item Value, COSMOS Event Message) are always Decom; the Raw / Decom radio buttons are disabled for them.

The table at the bottom of the dialog lists everything you have added along with its Mode and ValueType. Click the trash icon to remove an entry.

## Raw View

In Raw mode the component prints the packet buffer as hex bytes. The Display Settings dialog controls the bytes per line, whether the line address is prepended, and whether the ASCII representation is appended:

```text
00000000: 00 01 00 00 00 0a 01 02    ........
00000008: 48 45 4c 4c 4f              HELLO
```

## Decom View

In Decom mode the component prints one line per item as `ITEM_NAME: value`. Which underlying value is printed depends on the **Value Type** you selected when adding the packet.

```text
********************************************
* Received seconds: 1712345678.9012345
* Received time: 2024-04-05T18:14:38.901Z
********************************************
PACKET_TIMESECONDS: 1712345678.901
RECEIVED_COUNT: 143
TEMP1: 22.000
GROUND1STATUS: CONNECTED
```

### Value Types

| Value Type | What is displayed                                                                                                                     |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| RAW        | The value as it appears in the packet buffer, before any read conversion or state conversion                                            |
| CONVERTED  | The value after read conversions and state conversions are applied                                                                      |
| FORMATTED  | The CONVERTED value run through the item's FORMAT_STRING, returned as a string                                                          |

The Value Type is selected per packet, so a single component can mix packets displayed with different value types. FORMATTED is the default.

### Converted Values and Downward Typing

Decommutated packets only store the value types that actually differ from the raw value. An item's CONVERTED value is stored only when the item has a read conversion or [STATE](../configuration/telemetry.md#state) definitions, and its FORMATTED value is stored only when the item defines a [FORMAT_STRING](../configuration/telemetry.md#format_string). COSMOS therefore uses "downward typing" when reading: if the requested value type was not stored for an item, the next lower type is used instead.

- **FORMATTED** falls back to CONVERTED (converted to a string), then to RAW (converted to a string)
- **CONVERTED** falls back to RAW
- **RAW** is always available

The practical effect is that an item with no conversions, no states, and no format string looks identical under all three value types. Differences only appear for items that define them:

| Item definition                             | RAW      | CONVERTED   | FORMATTED |
| ------------------------------------------- | -------- | ----------- | --------- |
| `TEMP1` with a POLY_READ_CONVERSION and `FORMAT_STRING "%0.3f"` | `40000` | `22.0`      | `22.000`  |
| `GROUND1STATUS` with `STATE CONNECTED 1`    | `1`      | `CONNECTED` | `CONNECTED` |
| `RECEIVED_COUNT` with no conversions        | `143`    | `143`       | `143`     |

Data Viewer does not offer the WITH_UNITS value type; use FORMATTED to see an item's format string applied. Note that FORMATTED always produces a string. An item with states but no format string shows the state name under FORMATTED because it falls back to the CONVERTED value.

[DERIVED](../configuration/telemetry.md#derived-items) items are stored under their base name like any other item and follow the same rules.

If a packet was logged with an `extra` hash, it is displayed as a `COSMOS_EXTRA` line containing the JSON.

### Commands in Decom View

Commands can be viewed the same way by selecting the Command radio button. For command packets, the CONVERTED value is stored only for parameters that have a write conversion or states:

- Parameters with **states** display the state name, regardless of whether the state name or the state value was used when the command was sent.
- Parameters with a **write conversion** display the value the user supplied to the command, not the post-conversion value that was written into the buffer.
- Commands sent raw (bypassing write conversions) do not log a converted value, so RAW is displayed.

## Display Settings

Click the gear icon on a component to bring up the Display Settings dialog.

![Display Settings](/img/data_viewer/display_settings.png)

| Setting          | Description                                                                             |
| ---------------- | ----------------------------------------------------------------------------------------- |
| Show timestamp   | Prepend the received seconds and received time to each entry                                |
| Show ASCII       | (Raw only) Append the ASCII representation of each line of bytes                            |
| Show line address | (Raw only) Prepend the byte offset to each line                                            |
| Print newest to the | Whether new entries are added at the top or the bottom                                  |
| History Buffer   | Number of entries kept in memory                                                            |
| Bytes per line   | (Raw only) Number of bytes printed per line                                                 |
| Entries to show  | Number of entries displayed at once, up to the History Buffer size                          |

## Viewing and Exporting Data

Each component has a search field, a slider to step backwards and forwards through the history buffer, a pause / play button, and a download button.

The search field filters line by line rather than entry by entry, so searching for `TEMP` in a Decom view shows only the matching item lines from each packet. The download button saves the text currently displayed (including the effect of the search filter) to a `YYYY_MM_DD_HH_MM_SS.txt` file. Pausing, or dragging the slider, stops the display from updating but data continues to be buffered.
