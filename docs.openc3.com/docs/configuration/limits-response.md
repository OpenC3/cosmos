---
sidebar_position: 11
title: Limits Response
description: Custom code invoked when a item with limits changes state
sidebar_custom_props:
  myEmoji: ⚠️
---

# Overview

A limits response is custom code which can respond to a telemetry item changing limits states (red, yellow, green or blue). To apply a limits response to a telemetry item you use the [LIMITS_RESPONSE](/docs/configuration/telemetry#limits_response) keyword.

## Creating a Limits Response

You can easily create a limits response by using the [Limits Response Code Generator](/docs/getting-started/generators#limits-response-generator). To generate a limits response you must be inside an existing COSMOS plugin. The generator takes both a target name and the limits response name. For example if your plugin is called `openc3-cosmos-gse` and you have an existing target named `GSE`:

```bash
openc3-cosmos-gse % openc3.sh cli generate limits_response GSE abort --python
Limits response targets/GSE/lib/abort_limits_response.py successfully generated!
To use the limits response add the following to a telemetry item:
  LIMITS_RESPONSE abort_limits_response.py
```

Note: To create a Ruby conversion simply replace `--python` with `--ruby`

This creates a limits response called `abort_limits_response.py` at `targets/GSE/lib/abort_limits_response.py`. The code which is generated looks like the following:

```python
from openc3.packets.limits_response import LimitsResponse
from openc3.api import *

class AbortLimitsResponse(LimitsResponse):
    # @param packet [Packet] Packet the limits response is assigned to
    # @param item [PacketItem] PacketItem the limits response is assigned to
    # @param old_limits_state [Symbol] Previous value of the limit. One of nil,
    #   "GREEN_HIGH", "GREEN_LOW", "YELLOW", "YELLOW_HIGH", "YELLOW_LOW",
    #   "RED", "RED_HIGH", "RED_LOW". nil if the previous limit state has not yet
    #   been established.
    def call(self, packet, item, old_limits_state):
        # Take action based on the current limits state
        # Delete any of the case lines that do not apply or you don't care about
        match item.limits.state:
            case "RED_HIGH":
                # Take action like sending a command:
                # cmd("TARGET SAFE")
                pass
            case "RED_LOW":
                pass
            case "YELLOW_LOW":
                pass
            case "YELLOW_HIGH":
                pass
            # GREEN limits are only available if a telemetry item has them defined
            # COSMOS refers to these as "operational limits"
            # See https://docs.openc3.com/docs/configuration/telemetry#limits
            case "GREEN_LOW":
                pass
            case "GREEN_HIGH":
                pass
            # :RED and :YELLOW limits are triggered for STATES with defined RED and YELLOW states
            # See https://docs.openc3.com/docs/configuration/telemetry#state
            case "RED":
                pass
            case "YELLOW":
                pass
```

There are a lot of comments to help you know what to do. The only thing you need to modify is the `call` method.

### call

The call method is where the limits response logic is implemented. As an example, suppose we want to send the `INST ABORT` command every time we enter a RED_HIGH or RED_LOW state. The final result with comments removed looks like the following:

```python
from openc3.packets.limits_response import LimitsResponse
from openc3.api import *
class AbortLimitsResponse(LimitsResponse):
    def call(self, packet, item, old_limits_state):
        match item.limits.state:
            case "RED_HIGH" | "RED_LOW":
                cmd("INST ABORT")
```

### Apply Conversion

Now that we have implemented the limits response logic we need to apply it to a telemetry item by adding the line `LIMITS_RESPONSE abort_limits_response.py` in the [telemetry](/docs/configuration/telemetry) definition file. This could look something like this:

```bash
TELEMETRY GSE DATA BIG_ENDIAN "Data packet"
  ... # Header items
  APPEND_ITEM VALUE 16 UINT "limits response item"
    LIMITS DEFAULT 1 ENABLED -90 -80 80 90
    LIMITS_RESPONSE abort_limits_response.py
```

The definition combined with the `AbortLimitsResponse` means that each time the `GSE DATA VALUE` item goes below -90 or above 90 the `INST ABORT` command will be sent.
