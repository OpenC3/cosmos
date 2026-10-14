---
name: cosmos-dashboards
description: Write OpenC3 COSMOS Dashboards definition files (TARGET/dashboards/*.txt), the panel grid shown by the Dashboards tool. Use when asked to create, lay out or edit a COSMOS dashboard, or to add one to a plugin.
---

# Building COSMOS dashboards

A dashboard is a plain text file that lays out **panels** on a 12 column grid.
Each panel shows telemetry items (from any targets), out of limits items, a
command or script button, or a Telemetry Viewer screen. The Dashboards tool
(beta) opens, edits and saves these files; you can also write them by hand.

Dashboards is a beta feature: the format can change in any release. Every
saved file starts with a comment saying so; keep it.

## Where the file goes

`<TARGET>/dashboards/<name>.txt`, stored with a target the way screens are.
The target only decides where the file lives; panels can show items from any
target.

- **In a plugin:** `targets/<TARGET>/dashboards/<name>.txt`. It installs with
  the plugin. ERB works, e.g. `<%= target_name %>` for the target's installed
  name.
- **On a running system:** open Dashboards, choose **New**, then **Code**, and
  paste the text. Or POST it to `/openc3-api/dashboard` with `target`,
  `dashboard` (the name) and `text`. This needs the `system_set` permission.
- File names are lowercase. The tool opens them at
  `/tools/dashboards/<TARGET>/<NAME>`, e.g. `INST/overview.txt` opens at
  `/tools/dashboards/INST/OVERVIEW`. Files starting with `_` aren't listed.

## File format

```
# Dashboards is a beta feature: this file format can change in any release
DASHBOARD "Power Overview"
  SETTING ICON mdi-battery-outline
  SETTING COLOR "#938bdb"

PANEL <TYPE> <Column> <Row> <Width> <Height> ["Title"]
  <panel keywords>
END
```

| Keyword | Where | Usage |
| --- | --- | --- |
| `DASHBOARD` | first | `DASHBOARD "<Title>"` |
| `SETTING` (dashboard) | before the first `PANEL` | `ICON <mdi-icon>`, `COLOR "<#rrggbb>"`, `POLLING_PERIOD <seconds>` (default 1) |
| `PANEL` | | `PANEL <Type> <Column> <Row> <Width> <Height> ["Title"]` |
| `ITEM` | in a panel | `ITEM <Target> <Packet> <Item> [RAW\|CONVERTED\|FORMATTED\|WITH_UNITS]` |
| `ITEM_SETTING` | after an `ITEM` | `ITEM_SETTING <Name> <Values...>`, applies to the `ITEM` above it |
| `TARGET` | LIMITS panels | `TARGET <Target>` |
| `COMMAND` | COMMAND panels | `COMMAND <Target> <Command>` |
| `PARAMETER` | COMMAND panels | `PARAMETER <Parameter> <Value>` |
| `SCRIPT` | COMMAND panels | `SCRIPT <TARGET/procedures/file.rb>` |
| `SCREEN` | SCREEN panels | `SCREEN <Target> <Screen>` |
| `SETTING` (panel) | in a panel | `SETTING <Name> <Values...>` |
| `END` | | closes the panel |

**Rules:**
- Names (targets, packets, items, settings) are case-insensitive and are
  written in uppercase.
- `#` starts a comment, so always quote colors: `"#4dacff"`. Writing them
  without the `#` (`4dacff`) also works.
- Quote titles, and any value with spaces: `"South Point"`.
- Leave off the value type. Panels read converted values and apply the
  item's format string and units themselves. Use `RAW` only to show raw
  values.
- Settings left at their defaults don't need to be written.
- Comments are dropped when a dashboard is saved from the tool.

## The grid

- **Columns:** 12. `Column` is 0 to 11, `Width` is 1 to 12, and
  `Column + Width` must be 12 or less.
- **Rows:** 40px each, with 16px gaps, so a panel `h` rows tall is
  `56h - 16` pixels. `Row` starts at 0, and `Height` is 2 to 18.
- **Panel header:** about 36px of every panel.
- **No overlaps:** panels must not overlap; a file is shown as written. Build
  rows left to right, then start the next row at the bottom of the tallest
  panel above.
- **Smaller screens:** only this desktop layout is written. Tablets give
  panels 4 columns wide or narrower half the width, and the rest full width.
  Phones stack every panel full width, reading left column first.

## Panel types

All values are as of the dashboard's polling, about once a second. Panels
show limits colors and status symbols on their own.

### STAT: one value, big
One `ITEM`. The number, units, an optional limits bar, and a sparkline.

| Setting | Default | |
| --- | --- | --- |
| `PACKET_TIME` | `TRUE` | Show the packet time |
| `GRAPH` | `TRUE` | Show the sparkline |
| `DURATION` | `2` | Sparkline history in minutes (0.5 to 1440), backfilled when opened |
| `LIMITS_LINES` | `TRUE` | Limits lines on the sparkline |
| `LIMITS_BAR` | `TRUE` | Limits bar under the value |

- `ITEM_SETTING COLOR "<#rrggbb>"` colors the sparkline.
- **Sizes:** 3 wide is typical. At height 2 the panel shows the number only.
  Height 3 adds the sparkline, and height 4 or more adds the limits bar.

### STATE: a state value
One `ITEM`, usually one with states (CONNECTED, ON, NORMAL…). It shows the
state with its status symbol and the packet time.

| Setting | Default | |
| --- | --- | --- |
| `PACKET_TIME` | `TRUE` | Show the packet time |

- **Sizes:** 3×2 is typical.

### GRAPH: time series
Up to 6 `ITEM`s, which can mix targets. It backfills `DURATION` when opened,
then streams.

| Setting | Default | |
| --- | --- | --- |
| `DURATION` | `2` | Minutes shown (0.5 to 1440) |
| `THRESHOLDS` | first item with limits | `<Target> <Packet> <Item>`: whose limits are drawn as bands |

- `ITEM_SETTING COLOR "<#rrggbb>"` sets a line color.
- **Sizes:** 8×7 is typical, and 4×4 is the smallest that is still useful.

### VALUES: table of items
Any number of `ITEM`s. Each row shows a status symbol, the name, a limits bar
(for items with limits), the value and units.

| Setting | Default | |
| --- | --- | --- |
| `LIMITS_BARS` | `TRUE` | Show the limits bars |

- **Sizes:** rows are 36px. Height `ceil((36 × items + 68) / 56)` fits every
  row: 4 items → 4, 7 items → 6, 10 items → 8. Taller lists scroll.

### LIMITS: what is out of limits
`TARGET` lines pick the targets; leave them out for all targets. Each row
shows the item, why it's out of limits, its value, and how long it's been
out. No settings.

- **Sizes:** 4×6 is typical.

### COMMAND: send a command or run a script
Either a command (`COMMAND` plus optional `PARAMETER` defaults) or a script
(`SCRIPT`). Parameters show as a form pre-filled from the `PARAMETER` lines.
Hazardous commands are marked, and critical commands go through the normal
approval.

| Setting | Default | |
| --- | --- | --- |
| `CONFIRM` | `HOLD` | `HOLD`: hold the button 0.8 s (2 s when hazardous). `CLICK`: one click, plus a confirmation when hazardous |
| `DETAILS` | none | Text shown above the button; `\n` for line breaks |
| `OPEN_SCRIPT` | `FALSE` | Scripts only: open Script Runner when it starts |

- **Sizes:** 4×6 for a command with parameters, 4×4 for a script or a command
  with none.
- **Height 2:** just the button and its status, for a one-tap action. The
  parameter form and `DETAILS` are hidden; details become the button's
  tooltip. The command sends its `PARAMETER` values, so give every required
  parameter one: the button stays disabled while a required parameter has no
  value.

### SCREEN: a Telemetry Viewer screen
`SCREEN <Target> <Screen>`. The screen runs as it does in Telemetry Viewer.
No settings.

- **Sizes:** size it to the screen, e.g. 6×8 or 4×12.

### Plugin panel types
Plugin panels, such as **MAP** (2D map) and **ORBIT** (3D globe), work only
when their plugin is installed. If it isn't, the dashboard still opens and
keeps those panels unchanged. Both take position items and up to 6 fixed
locations:

```
PANEL MAP 0 0 8 8 "Ground track"
  ITEM INST ADCS POSX
  ITEM INST ADCS POSY
  ITEM INST ADCS POSZ
  SETTING COORDINATES ECEF        # or LATLON: items in lat, lon pairs
  SETTING LOCATION_1 Wallops
  SETTING LOCATION_1_LAT 37.94
  SETTING LOCATION_1_LON -75.46
END

PANEL ORBIT 8 0 4 8
  ITEM INST ADCS POSX             # ECEF X, Y, Z per spacecraft
  ITEM INST ADCS POSY
  ITEM INST ADCS POSZ
  SETTING FRAME ECEF              # or ECI
  SETTING TRAIL 90                # minutes
END
```

See each plugin's README for its full list of settings.

## Example

```
# Dashboards is a beta feature: this file format can change in any release
DASHBOARD "INST Overview"
  SETTING ICON mdi-satellite-variant

PANEL STAT 0 0 3 4 "Temperature 1"
  ITEM INST HEALTH_STATUS TEMP1
END

PANEL STAT 3 0 3 4 "Temperature 4"
  ITEM INST2 HEALTH_STATUS TEMP4
  SETTING DURATION 30
END

PANEL STATE 6 0 3 2 "Ground station 1"
  ITEM INST HEALTH_STATUS GROUND1STATUS
END

PANEL STATE 6 2 3 2 "Ground station 2"
  ITEM INST HEALTH_STATUS GROUND2STATUS
END

PANEL LIMITS 9 0 3 4 "Limits"
  TARGET INST
  TARGET INST2
END

PANEL GRAPH 0 4 8 7 "Temperatures"
  ITEM INST HEALTH_STATUS TEMP1
  ITEM INST HEALTH_STATUS TEMP2
  ITEM INST2 HEALTH_STATUS TEMP1
    ITEM_SETTING COLOR "#938bdb"
  SETTING DURATION 5
  SETTING THRESHOLDS INST HEALTH_STATUS TEMP1
END

PANEL VALUES 8 4 4 7 "Health"
  ITEM INST HEALTH_STATUS TEMP1
  ITEM INST HEALTH_STATUS TEMP2
  ITEM INST HEALTH_STATUS TEMP3
  ITEM INST HEALTH_STATUS COLLECT_TYPE
  ITEM INST HEALTH_STATUS DURATION
END

PANEL COMMAND 0 11 4 6 "Collect"
  COMMAND INST COLLECT
  PARAMETER TYPE NORMAL
  PARAMETER DURATION 1
  SETTING CONFIRM HOLD
END

PANEL COMMAND 4 11 4 6 "Collect procedure"
  SCRIPT INST/procedures/collect.rb
  SETTING DETAILS "Runs a NORMAL then a SPECIAL collect."
  SETTING CONFIRM CLICK
END

PANEL SCREEN 8 11 4 6
  SCREEN INST HS
END
```

The COSMOS demo plugin has more examples in
`openc3-cosmos-demo/targets/INST/dashboards/`.

## Checklist

1. **Use real names.** Take target, packet, item, command and parameter names
   from the target's `cmd_tlm/*.txt` files, or from the API (`get_target`,
   `get_tlm_packet`, `get_cmd`). Names aren't checked against the system
   when the file is parsed; a wrong name only shows as missing data.
2. **Pick the panel for the job:**
   - STAT for a headline number
   - STATE for a status with states
   - GRAPH for trends
   - VALUES for a group of related values
   - LIMITS for an overview of what's out of limits
   - COMMAND for frequent actions
3. **Lay out without overlaps.** Every row's widths add up to 12 or less.
   Put the most important panels at the top left: phones show panels in that
   order.
4. **Keep it parseable:**
   - quote titles and colors
   - one `END` per `PANEL`
   - `ITEM_SETTING` right after its `ITEM`
   - only the keywords each type allows (the table above)
   - item limits: STAT and STATE take 1 item, GRAPH up to 6
5. **Check it.** Open the dashboard: a banner lists any problems with line
   numbers, and **Code** shows the file with the problems marked. Problems
   include unknown keywords or settings, out-of-range values, and panels
   missing items.

## Where the format is defined

In `openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-dashboards/src/tools/Dashboards/`:

- `dashboardParser.js`: the keywords, and the parser and serializer
- `panels/registry.js`: each panel type's keywords, item limits, settings and
  defaults
- `panels/options.js`: setting value types (boolean, select, number, text,
  color, item)
- `layout.js`: the grid constants and the tablet and phone layouts

Settings declared in `registry.js` are what the parser accepts. If this file
and the code disagree, the code is right.
