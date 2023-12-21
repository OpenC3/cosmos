---
title: Data Viewer
---

## Introduction

Data Viewer allows you to view packet data in both the past and in real time.

![Data Viewer](/img/data_viewer/data_viewer.png)

## Data Viewer Menus

### File Menu Items

<!-- Image sized to match up with bullets -->

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

### Adding Components

DataViewer displays data in a component. To add a new component to the interface click the plus icon. This brings up the Add Component dialog. First you select the component you want to use to visual the data. Next you add packets which will populate the component. Finally click Create to see the DataViewer component visualization.

![Add Component](/img/data_viewer/add_component.png)

To adjust the settings of the COSMOS Raw/Decom component click the gear icon to bring up the Display Settings dialog. You can turn on and off various visualizations, increase the number of packets displayed and the history.

![Add a packet](/img/data_viewer/display_settings.png)
