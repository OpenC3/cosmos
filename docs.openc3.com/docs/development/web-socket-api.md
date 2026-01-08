---
title: Web Socket API
description: Using web sockets to retrieve data.
---

:::note This documentation is for COSMOS Developers
This information is just generally used behind the scenes in COSMOS tools
:::

# Web Socket Channels
- `StreamingChannel`: for telemetry data, used by [Data Extractor](../tools/data-extractor.md) and [Data Viewer](../tools/data-viewer.md). Refer to the [Streaming API documentation](./streaming-api.md) for more details.
- `SystemEventsChannel`: used by Targets tab in [CmdTlmServer](../tools/cmd-tlm-server.md)
- `LimitsEventsChannel`: for limits information, used by [Limits Monitor](../tools/limits-monitor.md)
- `ConfigEventsChannel`: used by [Limits Monitor](../tools/limits-monitor.md)
- `MessagesChannel`: for log messages, used by [Log Explorer](../tools/log-explorer.md) and [CmdTlmServer](../tools/cmd-tlm-server.md)'s Log Messages table
- `AllScriptsChannel`: used by the notification bell
- `RunningScriptChannel`: used in [Script Runner](../tools/script-runner.md)
- `AutonomicEventsChannel`: used in [Autonomic](../tools/autonomic.md) tool
- `TimelineEventsChannel`: used in [Calendar](../tools/calendar.md) tool
- `CalendarEventsChannel`: used in [Calendar](../tools/calendar.md) tool
- `QueueEventsChannel`: used in [Command Queue](../tools/command-queue.md) tool
