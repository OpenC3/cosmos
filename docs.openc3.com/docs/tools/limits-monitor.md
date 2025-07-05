---
title: Limits Monitor
description: View out of limit items and log messages
sidebar_custom_props:
  myEmoji: 🚥
---

## Introduction

The Limits Monitor application provides situational awareness for all telemetry items with limits. All limits items which violate their yellow or red limits are shown and continue to be shown until explicitly dismissed. Individual items and entire packets can be manually ignored to filter out known issues. In addition, all limits events are logged in a table which can be searched.

![Cmd Tlm Server](/img/limits_monitor/limits_monitor.png)

## Limits Monitor Menus

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/limits_monitor/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 150 + 'px'}} />

- Show the list of ignored items
- Change the overall COSMOS limits set
- Opens a saved configuration
- Save the current configuration (ignored items)
- Reset the configuration (defaults settings)

#### Show Ignored

This dialog displays all the items which the user has manually ignored by clicking the ignore icons next to out of limits items. Note that entire Packets which have been ignored are listed as TARGET PACKET without an item (as shown by INST MECH). Ignored items are removed by clicking the Trash icon. This means that the next time this item goes out of limits it will be displayed.

![Ignored](/img/limits_monitor/ignored.png)

#### Change Limits Set

Limits sets are defined with the [LIMITS](../configuration/telemetry#limits) keyword on telemetry items. Each item must have at least a DEFAULT limits set but can also have other named limit sets. COSMOS only has a single limits set active at one time. This dialog allows the user to change the active limits set and apply new limit values across all of COSMOS.

![Change Limits Set](/img/limits_monitor/change_limits_set.png)

#### Open Configuration

The Open Configuration dialog displays a list of all saved configurations. You select a configuration and then click Ok to load it. You can delete existing configurations by clicking the Trash icon next to a configuration name.

#### Save Configuration

The Save Configuration dialog also displays a list of all saved configurations. You click the Configuration Name text field, enter the name of your new configuration, and click Ok to save. You can delete existing configurations by clicking the Trash icon next to a configuration name.

## Limits Items

The main interface of Limits Monitor is the top where items are displayed when they violate a yellow or red limit.

![Limits](/img/limits_monitor/limits_monitor.png)

Items with limits values are displayed using a red yellow green limits bar displaying where the current value lies within the defined limits (as shown by the various TEMP items). Items with yellow or red [states](../configuration/telemetry.md#state) are simply displayed with their state color (as shown by GROUND1STATUS). The COSMOS Demo contains both INST HEALTH_STATUS TEMP2 and INST2 HEALTH_STATUS TEMP2 which are identically named items within different target packets. Limits Monitor only displays the item name to save space, however if you mouse over the value box the full target and packet name is displayed.

Clicking the first nested 'X' icon ignores the entire packet where the item resides. Any additional items in that packet which go out of limits are also ignored by Limits Monitor. Clicking the second (middle) 'X' ignores ONLY that specific item. If any packets or items are ignored the Overall Limits State is updated to indicate "(Some items ignored)" to indicate the Limits State is potentially being affected by ignored items.

Clicking the last icon (eye with strike-through) temporarily hides the specified item. This is different from ignoring an item because if this item goes out of limits it will be again be displayed. Hiding an item is useful if the item has gone back to green and you want to continue to track it but want to clean up the current list of items. For example, we might hide the GROUND1STATUS items in the above example as they have transitioned back to green.

## Limits Log

The Log section lists all limits events. Events can be filtered by using the Search box as shown.

![Log](/img/limits_monitor/log.png)
