---
title: Logging
description: The log files in COSMOS
sidebar_custom_props:
  myEmoji: 🪵
---

The COSMOS [Bucket Explorer](../tools/bucket-explorer.md) tool provides a way to browse the COSMOS bucket storage backend whether you are running locally or in a cloud environment. Browse to http://localhost:2900/tools/bucketexplorer and you should see the list of buckets at the top:

![Bucket Explorer](/img/guides/logging/logs.png)

Note the config and logs buckets are organized by scopes of which there initially is just one: DEFAULT. Clicking the DEFAULT folder in the logs bucket shows the decom_logs, raw_logs, reduced_xxx_logs, text_logs and tool_logs.

### decom_logs & raw_logs

The decom_logs and raw_logs folders contain the decommutated and raw command and telemetry data. Both are further broken down by target, packet, then date. For example, browsing into the DEFAULT/raw_logs/tlm/INST2/&lt;YYYYMMDD&gt;/ directory:

![raw_tlm_logs](/img/guides/logging/raw_tlm_logs.png)

Note the presence of the gzipped .bin files which contain the raw binary data. For more information about the structure of these files see the [Log Structure](../development/log-structure.md) developer documentation.

The default settings for the Logging microservice is to start a new log file every 10 minutes or 50MB, which ever comes first. In the case of the low data rate demo, the 10 minute mark is hit first.

To change the logging settings add the various CYCLE_TIME [Target Modifiers](../configuration/plugins.md#target-modifiers) under the declared [TARGET](../configuration/plugins.md#target-1) name in your plugin.txt.

### text_logs

The text_logs folder contains openc3_log_messages which contains text files that are again sorted by date and timestamped. These log messages come from the various microservices including the server and the target microservices. Thus these logs contain all the commands sent (in plain text) and telemetry checked. These log messages files are long term records of the messages in the CmdTlmServer Log Messages window:

![log_messages](/img/guides/logging/log_messages.png)

### tool_logs

The tool_logs directory contains logs from the various COSMOS tools. Note that if you have not yet run any tools you may not see this directory as it is created on demand. Tool sub-directories are also created on demand. For example, after running a script in Script Runner a new 'sr' subdirectory appears which contains the script runner log resulting from running the script. In some cases logs in this directory may also be directly available from the tool itself. In the Script Runner case, the Script Messages pane below the script holds the output messages from the last script. Clicking the Download link allows you to download these messages as a file.

![log_messages](/img/guides/logging/script_messages.png)
