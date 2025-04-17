---
title: Telemetry Grapher
description: Graph real time or historical data
sidebar_custom_props:
  myEmoji: 🛠️
---

## Introductions

Telemetry Grapher is a graphing application that allows for one or more telemetry points per graph. It supports multiple graphs per screen which can be resized and reordered. Multiple configurations can be saved and restored for different situations.

![Telemetry Grapher](/img/telemetry_grapher/telemetry_grapher.png)

## Telemetry Grapher Menus

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/telemetry_grapher/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 90 + 'px'}} />

- Open a saved configuration (graphs and items)
- Save the current configuration
- Reset the configuration (default settings)

#### Open Configuration

The Open Configuration dialog displays a list of all saved configurations. You select a configuration and then click Ok to load it. You can delete existing configurations by clicking the Trash icon next to a configuration name.

#### Save Configuration

The Save Configuration dialog also displays a list of all saved configurations. You click the Configuration Name text field, enter the name of your new configuration, and click Ok to save. You can delete existing configurations by clicking the Trash icon next to a configuration name.

### Graph Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/telemetry_grapher/graph_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 150 + 'px'}} />

- Add a new graph
- Start / Resume graphing
- Pause graph
- Stop graph
- Edit grapher settings

Editing the grapher settings brings up a dialog to change settings affecting every graph in the Telemetry Grapher tool. Changing the Seconds Graphed changes the visible windows displaying graph points. The smaller of Seconds Graphed and Points Graphed will be used when calculating the number of points to display. Changing the Points Saved will affect performance of the browser window if set too high. The default of 1,000,000 points can store over 11.5 days of 1Hz data points.

Editing an individual graph by clicking the pencil icon in title bar of the graph brings up the edit graph dialog.

![Edit Graph](/img/telemetry_grapher/edit_graph.png)

Editing the Start Date and Start Time will re-query the data to begin at the specified time. This operation can take several seconds depending on how far back data is requested. Similarly, specifying the End Date and End Time will limit the data request to the specified time. Leaving the End Date / End Time fields blank will cause Telemetry Grapher to continue to graph items in real-time as they arrive.

Changing the Min Y and Max Y values simply sets the graph scale. Deleting the Min Y and Max Y values allows the graph to scale automatically as values arrive. Compare the following graph with the minimum set to 0 and the maximum set to 100 with the first graph image (auto-scale).

![Min Max](/img/telemetry_grapher/graph_min_max.png)

## Selecting Items

Selecting a target from the Select Target drop down automatically updates the available packets in the Select Packet drop down which updates the available items in the Select Item drop down. Clicking Add Item adds the item to the graph which immediately begins graphing.

![Temp 1](/img/telemetry_grapher/graph_temp1.png)

As time passes, the main graph fills up and starts scrolling while the overview graph at the bottom shows the entire history.

![Temp 1 History](/img/telemetry_grapher/graph_temp1_time.png)

Selecting a new item and adding it to the graph automatically fills the graph with history until the beginning of the first item. This allows you to add items to the graph incrementally and maintain full history.

![Temp1 Temp2](/img/telemetry_grapher/graph_temp1_temp2.png)

## Graph Window Management

All graphs can be moved around the browser window by clicking their title bar and moving them. Other graphs will move around intelligently to fill the space. This allows you order the graphs no matter which order they were created in.

Each graph has a set of window buttons in the upper right corner. The first shrinks or grows the graph both horizontally and vertically to allow for 4 graphs in the same browser tab. Note that half height graphs no longer show the overview graph.

![Four Graphs](/img/telemetry_grapher/four_graphs.png)

The second button shrinks or grows the graph horizontally so it will either be half or full width of the browser window. This allows for two full width graphs on top of each other.

![Two Full Width](/img/telemetry_grapher/two_full_width.png)

The third button shrinks or grows the graph vertically so it will either be half or full height of the browser window. This allows for two full height graphs side by side.

![Two Full Height](/img/telemetry_grapher/two_full_height.png)

The line button minimizes the graph to effectively hide it. This allows you to focus on a single graph without losing existing graphs.

![Minimized](/img/telemetry_grapher/minimized.png)

The final X button closes the graph.
