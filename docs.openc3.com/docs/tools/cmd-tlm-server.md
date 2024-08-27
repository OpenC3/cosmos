---
title: Command and Telemetry Server
---

## Introduction

The Command and Telemetry Server application provides status about the [interfaces](../configuration/interfaces.md) and targets instantiated in your COSMOS installation. Interfaces can be connected or disconnected and raw byte counts are returned. The application also provides quick shortcuts to view
both raw and formatted command and telemetry packets as they go through the COSMOS system. At the bottom of the Command and Telemetry Server is the Log Messages showing server messages.

![Cmd Tlm Server](/img/cmd_tlm_server/cmd_tlm_server.png)

## Command and Telemetry Server Menus

### File Menu Items

The Command and Telemetry Server has one menu under File -> Options:

![File Menu](/img/cmd_tlm_server/file_menu.png)

This dialog changes the refresh rate of the Command and Telemetry Server to reduce load on both your browser window and the backend server. Note that this changes the refresh rate of the various tabs in the application. The Log Messages will continue to update as messages are generated.

## Interfaces Tab

The Interfaces tab displays all the interfaces defined by your COSMOS installation. You can Connect or Disconnect interfaces and view raw byte and packet counts.

![Interfaces](/img/cmd_tlm_server/interfaces.png)

## Targets Tab

The Targets tab displays all the targets and their mapped interfaces.

![Targets](/img/cmd_tlm_server/targets.png)

## Command Packets Tab

The Command Packets tab displays all the available commands. The table can be sorted by clicking on the column headers. The table is paginated to support thousands of commands. The search bar searches all pages for a command.

![Commands](/img/cmd_tlm_server/cmd_packets.png)

Clicking on View Raw opens a dialog displaying the raw bytes for that command.

![Raw Command](/img/cmd_tlm_server/cmd_raw.png)

Clicking View in Command Sender opens up a new [Command Sender](cmd-sender.md) window with the specified command.

## Telemetry Packets Tab

The Telemetry Packets tab displays all the available telemetry. The table can be sorted by clicking on the column headers. The table is paginated to support thousands of telemetry packets. The search bar searches all pages for a telemetry packet.

![Telemetry](/img/cmd_tlm_server/tlm_packets.png)

Clicking on View Raw opens a dialog displaying the raw bytes for that telemetry packet.

![Raw Telemetry](/img/cmd_tlm_server/tlm_raw.png)

Clicking View in Packet Viewer opens up a new [Packet Viewer](packet-viewer.md) window with the specified telemetry packet.

## Status Tab

The Status tab displays COSMOS system metrics.

![Status](/img/cmd_tlm_server/status.png)

## Log Messages

The Log Messages table sits below all the tabs in the Command and Telemetry Server application. It displays server messages such as limits events (new RED, YELLOW, GREEN values), logging events (new files) and interface events (connecting and disconnecting). It can be filtered by severity or by entering values in the Search box. It can also be paused and resumed to inspect an individual message.

![Log Messages](/img/cmd_tlm_server/log_messages.png)
