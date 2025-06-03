---
sidebar_position: 12
title: Screens
description: Telemetry Viewer screen definition and widget documentation
sidebar_custom_props:
  myEmoji: 🖥️
---

<!-- Be sure to edit _telemetry_screens.md because telemetry_screens.md is a generated file -->

This document provides the information necessary to generate and use COSMOS Telemetry Screens, which are displayed by the COSMOS Telemetry Viewer application.

<div style={{"clear": 'both'}}></div>

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

# Screen Keywords

COSMOS_META

## Example File

Example File: TARGET/myscreen.txt

<!-- prettier-ignore -->
```ruby
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
