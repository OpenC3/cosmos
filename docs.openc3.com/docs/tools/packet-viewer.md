---
title: Packet Viewer
---

## Introduction

Packet Viewer is a live telemetry viewer which requires no configuration to display the current values for all defined target, packet, items. Items with limits are displayed colored (blue, green, yellow, or red) according to their current state. Items can be right clicked to get detailed information.

![Packet Viewer](/img/packet_viewer/packet_viewer.png)

## Packet Viewer Menus

### File Menu Items

Packet Viewer has one menu under File -> Options:

![File Menu](/img/packet_viewer/file_menu.png)

This dialog changes the refresh rate of Packet Viewer to reduce load on both your browser window and the backend server.

### View Menu Items

<!-- Image sized to match up with bullets -->

<img src="/img/packet_viewer/view_menu.png"
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 240 + 'px'}} />

- Shows [ignored items](../configuration/target.md#ignore_item)
- Display [derived](../configuration/telemetry.md#derived-items) items last
- Display formatted items with units
- Display formatted items
- Display converted items
- Display raw items

## Selecting Packets

Initially opening Packet Viewer will open the first alphabetical Target and Packet. Click the drop down menus to update the Items table to a new packet. To filter the list of items you can type in the search box.

![Items Table TEMP](/img/packet_viewer/select_packet.png)

### Details

Right-clicking an item and selecting Details will open the details dialog.

![Details](/img/packet_viewer/temp1_details.png)

This dialog lists everything defined on the telemetry item.
