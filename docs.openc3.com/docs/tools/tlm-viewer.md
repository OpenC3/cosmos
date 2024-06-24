---
title: Telemetry Viewer
---

## Introduction

Telemetry Viewer is a live telemetry viewer which displays custom built screens. Screens are configured through simple text files which utilize numerous build-in widgets.

![Telemetry Viewer](/img/telemetry_viewer/telemetry_viewer.png)

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/telemetry_viewer/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 90 + 'px'}} />

- Open a saved configuration
- Save the current configuration
- Reset the configuration (default settings)

#### Open Configuration

The Open Configuration dialog displays a list of all saved configurations. You select a configuration and then click Ok to load it. You can delete existing configurations by clicking the Trash icon next to a configuration name.

#### Save Configuration

The Save Configuration dialog also displays a list of all saved configurations. You click the Configuration Name text field, enter the name of your new configuration, and click Ok to save. You can delete existing configurations by clicking the Trash icon next to a configuration name.

## Selecting Screens

Selecting a target from the Select Target drop down automatically updates the available screens for that target in the Select Screen drop down. Clicking Show Screen causes that screen to display.

## New Screen

Clicking New Screen brings up the new screen dialog.

![Telemetry Viewer](/img/telemetry_viewer/new_screen.png)

Screens are owned by Targets so Select Target chooses where the screen will be created. Screens can be based on a Packet such that all the items in that particular packet will be generated in a simple vertical screen similar to Packet Viewer. This is a good starting point for customizing a screen. Note that screen names must be unique so the screen name is set to 'adcs2' since an 'ADCS' screen already exists.

## Edit Screen

Clicking the pencil icon in the title bar of the screen brings up the edit dialog.

![Telemetry Viewer](/img/telemetry_viewer/edit_screen.png)

The screen source is displayed in an editor with syntax highlighting and auto-completion. You can download the screen source using the download button in the upper right or delete the screen using the trash icon in the upper left. Click Save to save the screen edits at which point Telemetry Viewer will re-render the screen.

## Screen Window Management

All screens can be moved around the browser window by clicking their title bar and moving them. Other screens will move around intelligently to fill the space. This allows you to order the screens no matter which order they were created in.

You can also float the screens by clicking the grid icon in the upper left of the title bar. It will change to a balloon icon and allow you to click up and down to change the relative Z index of the window. The image screen is floated in the following screen shot.

The dash button in the upper right of the title bar minimizes the screen to effectively hide it. This allows you to focus on a single screen without closing existing screens. In the screen shot below there are two minimized windows at the very bottom.

![Float Minimized](/img/telemetry_viewer/float_minimize.png)

The X button closes the screen.

## Building Screens

For documentation on how to build Telemetry Screens and how to configure the
screen widgets please see the [Telemetry Screens](../configuration/telemetry-screens.md).
