---
sidebar_position: 13
title: Screens
description: Telemetry Viewer screen definition and widget documentation
sidebar_custom_props:
  myEmoji: 🖥️
---

{/* Be sure to edit _telemetry_screens.md because telemetry_screens.md is a generated file */}

This document provides the information necessary to generate and use COSMOS Telemetry Screens, which are displayed by the COSMOS Telemetry Viewer application.

<div style={{ clear: "both" }}></div>

## Definitions

| Name                   | Definition                                                                                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Widget                 | A widget is a graphical element on a COSMOS telemetry screen. It could display text, graph data, provide a button, or perform any other display/user input task.                                                                            |
| Screen                 | A screen is a single window that contains any number of widgets which are organized and layed-out in a useful fashion.                                                                                                                      |
| Screen Definition File | A screen definition file is an ASCII file that tells Telemetry Viewer how to draw a screen. It is made up of a series of keyword/parameter lines that define the telemetry points that are displayed on the screen and how to display them. |

## Telemetry Screen Definition Files

Telemetry screen definition files define the the contents of telemetry screens. They take the general form of a SCREEN keyword followed by a series of widget keywords that define the telemetry screen. Screen definition files specific to a particular target go in that target's screens directory. For example: TARGET/screens/version.txt. Screen definition files must be lowercase.

## New Widgets

When a telemetry screen definition is parsed and a keyword is encountered that is unrecognized, it is assumed that a file of the form widgetname_widget.rb exists, and contains a class called WidgetnameWidget. Because of this convention, new widgets can be added to the system without any change to the telemetry screen definition format. For more information about creating custom widgets please read the [Custom Widgets](../guides/custom-widgets.md) guide.

## Screen API

When writing button scripts in telemetry screens, you have access to the following objects and methods:

### api

The `api` object provides methods for commanding and telemetry operations:

#### Commanding

| Method                                                          | Description                                                                                                             |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `api.cmd(target_name, command_name, params)`                    | Sends a command with hazardous and range checks. Can also use string syntax: `api.cmd("INST COLLECT with TYPE NORMAL")` |
| `api.cmd_no_checks(target_name, command_name, params)`          | Sends a command without hazardous or range checks                                                                       |
| `api.cmd_no_hazardous_check(target_name, command_name, params)` | Sends a command without hazardous checks                                                                                |
| `api.cmd_no_range_check(target_name, command_name, params)`     | Sends a command without range checks                                                                                    |
| `api.cmd_raw(...)`                                              | Sends a command without converting parameter values                                                                     |
| `api.cmd_raw_no_checks(...)`                                    | Sends a raw command without any checks                                                                                  |
| `api.cmd_raw_no_hazardous_check(...)`                           | Sends a raw command without hazardous checks                                                                            |
| `api.cmd_raw_no_range_check(...)`                               | Sends a raw command without range checks                                                                                |

#### Telemetry

| Method                                                                 | Description                                                                                                                 |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `api.tlm(target_name, packet_name, item_name, value_type)`             | Returns a Promise that resolves with the telemetry value. Can also use string syntax: `api.tlm("INST HEALTH_STATUS TEMP1")` |
| `api.get_tlm_packet(target_name, packet_name, value_type, stale_time)` | Returns a Promise that resolves with the entire telemetry packet                                                            |

#### Limits

| Method                                     | Description                                    |
| ------------------------------------------ | ---------------------------------------------- |
| `api.enable_limits(target, packet, item)`  | Enables limits checking for an item            |
| `api.disable_limits(target, packet, item)` | Disables limits checking for an item           |
| `api.get_out_of_limits()`                  | Returns array of items currently out of limits |
| `api.get_overall_limits_state(ignored)`    | Returns the overall limits state               |

#### Utilities

| Method              | Description                      |
| ------------------- | -------------------------------- |
| `api.open_tab(url)` | Opens a URL in a new browser tab |

**Example using telemetry in a command:**

```javascript
api
  .tlm("INST PARAMS VALUE3", "RAW")
  .then((dur) => api.cmd("INST COLLECT with DURATION " + dur));
```

### screen

The `screen` object provides methods for interacting with widgets and screens:

| Method                         | Description                                                                             |
| ------------------------------ | --------------------------------------------------------------------------------------- |
| `screen.getNamedWidget(name)`  | Returns a reference to a named widget (see NAMED_WIDGET). The name is case insensitive. |
| `screen.open(target, screen)`  | Opens another telemetry screen                                                          |
| `screen.close(target, screen)` | Closes a specific telemetry screen                                                      |
| `screen.closeAll()`            | Closes all open telemetry screens                                                       |

**Example using named widgets:**

```javascript
var type = screen.getNamedWidget("COLLECT_TYPE").text();
api.cmd("INST COLLECT with TYPE " + type);
```

### runScript

The `runScript` function starts a script in Script Runner:

| Syntax                                            | Description                                   |
| ------------------------------------------------- | --------------------------------------------- |
| `runScript(scriptName)`                           | Runs the script and opens Script Runner       |
| `runScript(scriptName, false)`                    | Runs the script without opening Script Runner |
| `runScript(scriptName, true, {ENV_VAR: 'value'})` | Runs the script with environment variables    |

**Example:**

```javascript
runScript("INST/procedures/collect.rb", true, { TYPE: "NORMAL" });
```

## Layout and Alignment

Widgets are positioned by the layout widgets that contain them, not by coordinates (except inside a [CANVAS](#canvas)). [VERTICAL](#vertical) stacks widgets top to bottom, [HORIZONTAL](#horizontal) places them left to right, and [MATRIXBYCOLUMNS](#matrixbycolumns) arranges them in a table. By default widgets are aligned to the left.

To change alignment, apply a [SETTING](#setting) to the layout widget. A SETTING applies to the widget defined immediately before it, so put it either directly after the layout keyword (before any widgets inside it) or directly after the layout's `END`. The [RAW](#raw) setting applies any CSS property, which lets you use standard [flexbox](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_flexible_box_layout/Basic_concepts_of_flexbox) alignment because HORIZONTAL is a flexbox row.

### Centering a Button

Wrap the button in a HORIZONTAL and center its contents with `justify-content`:

```cosmos
SCREEN AUTO AUTO 1.0
VERTICAL
  TITLE "Centered Button"
  LABELVALUE INST HEALTH_STATUS COLLECTS
  HORIZONTAL
    SETTING RAW justify-content center # Applies to the HORIZONTAL
    BUTTON 'Start Collect' "api.cmd('INST COLLECT with TYPE NORMAL')"
  END
END
```

The same approach centers a group of widgets, e.g. several buttons in a row:

```cosmos
HORIZONTAL
  SETTING RAW justify-content center
  BUTTON 'Collect' "api.cmd('INST COLLECT with TYPE NORMAL')"
  BUTTON 'Abort' "api.cmd('INST ABORT')"
END
```

Other `justify-content` values include `flex-end` (align right), `space-between` (spread out with the first and last widgets at the edges), and `space-evenly` (equal gaps between the widgets and at both edges). Some widgets, such as LABEL, grow to fill the available width by default, which leaves no space to distribute. Give them a fixed size with [WIDTH](#width) if they don't line up as expected.

### Centering Everything in a Column

[TEXTALIGN](#textalign) on a VERTICAL or VERTICALBOX centers the text of its labels and also centers buttons and other inline widgets inside it:

```cosmos
VERTICALBOX "Commands"
  SETTING TEXTALIGN CENTER # Applies to the VERTICALBOX
  LABEL "Choose a command"
  BUTTON 'Collect' "api.cmd('INST COLLECT with TYPE NORMAL')"
  BUTTON 'Abort' "api.cmd('INST ABORT')"
END
```

### Vertical Alignment

Widgets in a HORIZONTAL stretch to the height of the tallest widget and their contents sit at the top. Use `align-items` to center them vertically instead, for example to line a button up with a taller widget next to it:

```cosmos
HORIZONTAL
  SETTING RAW align-items center
  LABEL "Collect:"
  BUTTON 'Start' "api.cmd('INST COLLECT with TYPE NORMAL')"
  SPARKLINE INST HEALTH_STATUS TEMP1
END
```

### Sizing and Spacing

- [WIDTH](#width) and [HEIGHT](#height) give a widget a fixed size, e.g. `SETTING WIDTH 200` to make a button 200 pixels wide.
- [MARGIN](#margin) and [PADDING](#padding) add space around and inside a widget.
- [SPACER](#spacer) inserts a fixed amount of empty space between widgets.
- VERTICAL and HORIZONTAL accept an optional margin parameter that is applied to every widget inside them, e.g. `HORIZONTAL 10`.
- Use [GLOBAL_SETTING](#global_setting) to apply the same setting to every widget of a type, e.g. `GLOBAL_SETTING BUTTON WIDTH 150` to make all buttons the same width.

# Screen Keywords

COSMOS_META

## Example File

Example File: TARGET/myscreen.txt

```cosmos
SCREEN AUTO AUTO 0.5
VERTICAL
  TITLE "<%= target_name %> Commanding Examples"
  LABELVALUE INST HEALTH_STATUS COLLECTS
  LABELVALUE INST HEALTH_STATUS COLLECT_TYPE
  LABELVALUE INST HEALTH_STATUS DURATION
  VERTICALBOX "Send Collect Command:"
    HORIZONTAL
      LABEL "Type: "
      NAMED_WIDGET COLLECT_TYPE COMBOBOX NORMAL SPECIAL
    END
    HORIZONTAL
      LABEL "  Duration: "
      NAMED_WIDGET DURATION TEXTFIELD 12 "10.0"
    END
    BUTTON 'Start Collect' "api.cmd('INST COLLECT with TYPE '+screen.getNamedWidget('COLLECT_TYPE').text()+', DURATION '+screen.getNamedWidget('DURATION').text())"
  END
  SETTING BACKCOLOR 163 185 163
  VERTICALBOX "Parameter-less Commands:"
    NAMED_WIDGET GROUP RADIOGROUP 1 # Select 'Clear' initially, 0-based index
      RADIOBUTTON 'Abort'
      RADIOBUTTON 'Clear'
    END
    NAMED_WIDGET CHECK CHECKBUTTON 'Ignore Hazardous Checks' # No option is by default UNCHECKED
    BUTTON 'Send' "screen.getNamedWidget('GROUP').selected() === 0 ? api.cmd('INST ABORT') : (screen.getNamedWidget('CHECK').checked() ? api.cmd_no_hazardous_check('INST CLEAR') : api.cmd('INST CLEAR'))"
  END
  SETTING BACKCOLOR 163 185 163
END
```
