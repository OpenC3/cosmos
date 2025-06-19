---
title: Packet Viewer
description: Displays all packets with their items
sidebar_custom_props:
  myEmoji: 🖥️
---

## Introduction

Packet Viewer is a live telemetry viewer which requires no configuration to display the current values for all defined target, packet, items. Items with limits are displayed colored (blue, green, yellow, or red) according to their current state. Items can be right clicked to get detailed information.

![Packet Viewer](/img/packet_viewer/packet_viewer.png)

## Packet Viewer Menus

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/packet_viewer/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 120 + 'px'}} />

- Change the refresh and stale interval
- Opens a saved configuration
- Save the current configuration (view settings)
- Reset the configuration (default settings)

### View Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/packet_viewer/view_menu.png').default}
alt="View Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 180 + 'px'}} />

- Shows [ignored items](../configuration/target.md#ignore_item)
- Display [derived](../configuration/telemetry.md#derived-items) items last
- Display formatted items with [units](../configuration/telemetry#units)
- Display [formatted](../configuration/telemetry#format_string) items
- Display [converted](../configuration/telemetry#read_conversion) items
- Display raw items

## Selecting Packets

Initially opening Packet Viewer will open the first alphabetical Target and Packet. Click the drop down menus to update the Items table to a new packet. To filter the list of items you can type in the search box.

### Details

Right-clicking an item and selecting Details will open the details dialog.

![Details](/img/packet_viewer/temp1_details.png)

This dialog lists everything defined on the telemetry item.
