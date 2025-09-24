---
title: JSON API
description: Interfacing to the COSMOS APIs using JSON-RPC
sidebar_custom_props:
  myEmoji: 🖥️
---

:::note This documentation is for COSMOS Developers
If you're looking for the methods available to write test procedures using the COSMOS scripting API, refer to the [Scripting API Guide](../guides/scripting-api.md) page. If you're trying to interface to COSMOS from an external application using any language then this is the right place.
:::

This document provides the information necessary for external applications to interact with COSMOS using the COSMOS API. External applications written in any language can send commands and retrieve individual telemetry points using this API. External applications also have the option of connecting to the COSMOS Command and Telemetry server to interact with raw tcp/ip streams of commands/telemetry. However, the COSMOS JSON API removes the requirement that external applications have knowledge of the binary formats of packets.

## Authorization

The HTTP Authorization request header contains the credentials to authenticate a user agent with a server, usually, but not necessarily, after the server has responded with a 401 Unauthorized status and the WWW-Authenticate header.

```
Authorization: <token/password>
```

## JSON-RPC 2.0

The COSMOS API implements a relaxed version of the [JSON-RPC 2.0 Specification](http://www.jsonrpc.org/specification). Requests with an "id" of NULL are not supported. Numbers can contain special non-string literal's such as NaN, and +/-inf. Request params must be specified by-position, by-name is not supported. Section 6 of the spec, Batch Operations, is not supported. The COSMOS scope must be specified in a `"keyword_params"` object.

## Socket Connections

The COSMOS Command and Telemetry Server listens for connections to the COSMOS API on an HTTP server (default port of 7777).

COSMOS listens for HTTP API requests at the default 2900 port at the `/openc3-api/api` endpoint.

## Supported Methods

The list of methods supported by the COSMOS API may be found in the [api](https://github.com/openc3/cosmos/tree/main/openc3/lib/openc3/api) source code on Github. The @api_whitelist variable is initialized with an array of all methods accepted by the CTS. This page will not show the full argument list for every method in the API, but it should be noted that the JSON API methods correspond to the COSMOS scripting API methods documented in the [Scripting Writing Guide](../guides/script-writing.md). This page will show a few example JSON requests and responses, and the scripting guide can be used as a reference to extrapolate how to build requests and parse responses for methods not explicitly documented here.

## Existing Implementations

The COSMOS JSON API has been implemented in the following languages: Ruby, Python and Javascript.

## Example Usage

### Sending Commands

The following methods are used to send commands: cmd, cmd_no_range_check, cmd_no_hazardous_check, cmd_no_checks

The cmd method sends a command to a COSMOS target in the system. The cmd_no_range_check method does the same but ignores parameter range errors. The cmd_no_hazardous_check method does the same, but allows hazardous commands to be sent. The cmd_no_checks method does the same but allows hazardous commands to be sent, and ignores range errors.

Two parameter syntaxes are supported.

The first is a single string of the form "TARGET_NAME COMMAND_NAME with PARAMETER_NAME_1 PARAMETER_VALUE_1, PARAMETER_NAME_2 PARAMETER_VALUE_2, ..." The "with ..." portion of the string is optional. Any unspecified parameters will be given default values.

| Parameter      | Data Type | Description                                                         |
| -------------- | --------- | ------------------------------------------------------------------- |
| command_string | string    | A single string containing all required information for the command |

The second is two or three parameters with the first parameter being a string denoting the target name, the second being a string with the command name, and an optional third being a hash of parameter names/values. This format should be used if the command contains parameters that take binary data that is not capable of being expressed as ASCII text. The cmd and cmd_no_range_check methods will fail on all attempts to send a command that has been marked hazardous. To send hazardous commands, the cmd_no_hazardous_check, or cmd_no_checks methods must be used.

| Parameter      | Data Type | Description                               |
| -------------- | --------- | ----------------------------------------- |
| target_name    | String    | Name of the target to send the command to |
| command_name   | String    | The name of the command                   |
| command_params | Hash      | Optional hash of command parameters       |

Example Usage:

```bash
--> {"jsonrpc": "2.0", "method": "cmd", "params": ["INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'"], "id": 1, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1}

--> {"jsonrpc": "2.0", "method": "cmd", "params": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1}
```

### Getting Telemetry

The following methods are used to get telemetry: tlm, tlm_raw, tlm_formatted

The tlm method returns the current converted value of a telemetry point. The tlm_raw method returns the current raw value of a telemetry point. The tlm_formatted method returns the current formatted value of a telemetry point with its units appended.

Two parameter syntaxes are supported.

The first is a single string of the form "TARGET_NAME PACKET_NAME ITEM_NAME"

| Parameter  | Data Type | Description                                                                |
| ---------- | --------- | -------------------------------------------------------------------------- |
| tlm_string | String    | A single string containing all required information for the telemetry item |

The second is three parameters with the first parameter being a string denoting the target name, the second being a string with the packet name, and the third being a string with the item name.

| Parameter   | Data Type | Description                                        |
| ----------- | --------- | -------------------------------------------------- |
| target_name | String    | Name of the target to get the telemetry value from |
| packet_name | String    | Name of the packet to get the telemetry value from |
| item_name   | String    | Name of the telemetry item                         |

Example Usage:

```bash
--> {"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "id": 2, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": 94.9438, "id": 2}

--> {"jsonrpc": "2.0", "method": "tlm", "params": ["INST", "HEALTH_STATUS", "TEMP1"], "id": 2, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": 94.9438, "id": 2}
```

## Further Debugging

If developing an interface for the JSON API from another language, the best way to debug is to send the same messages from the supported Ruby interface first, like the following. By enabling the debug mode, you can see the exact request and response sent from the Ruby Implementation.

1. Launch COSMOS
2. Open Command Sender
3. Open browser developer tools (right-click->Inspect in Chrome)
4. Click "Network" tab (may need to add it with `+` button)
5. Send a command with the GUI
6. View the request in the developer tool. Click the "Payload" sub-tab to view the JSON

You can also try sending these raw commands from the terminal with a program like `curl`:

```bash
curl -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "id": 2, "keyword_params":{"type":"FORMATTED","scope":"DEFAULT"}}' http://localhost:2900/openc3-api/api  -H "Authorization: password"
```
