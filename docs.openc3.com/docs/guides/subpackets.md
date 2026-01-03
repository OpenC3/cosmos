---
title: Subpackets and Channels
description: How COSMOS handles channelized telemetry and different time series
sidebar_custom_props:
  myEmoji: 🧩
---

The unit of processing within COSMOS is a packet. Telemetry packets coming into COSMOS are delineated and identified in Interfaces, and sometimes the same is done for commands being received by Routers.

Packets are also the unit of data that COSMOS keeps track of with timestamps. Each packet has a received time (the time that COSMOS received the packet), and a packet time (the real time that the packet data was generated which is usually derived from the packet's own data). If no packet time is available then packet time is set to the received time.

Each packet item therefore is part of a time-series with one sample per packet which can be graphed in [Telemetry Grapher](/docs/tools/tlm-grapher), extracted by [Data Extractor](/docs/tools/data-extractor) or played back in [Telemetry Viewer](/docs/tools/tlm-viewer).

However there are three primary use cases where this abstraction doesn't work as well as desired.

## Channelized Telemetry

Systems that produce channelized telemetry generally send down a single packet of telemetry that has variable content. The content within these packets are called channels.

Each channel has some form of id field that allows you to identify the channel data. Sometimes each channel has its own timestamp and sometimes the packet timestamp is applied to each channel.

For example, you might have a 32-bit id field, followed by a 64-bit timestamp field, followed by a structure that is unknown until you look up what the 32-bit id field references.

Channelized telemetry packets are therefore very dynamic and until COSMOS 6.10 were very difficult to define.

COSMOS 6.10 introduced the concepts of [SUBPACKET](/docs/configuration/telemetry#subpacket) and [SUBPACKETIZER](/docs/configuration/telemetry#subpacketizer) in order to handle channelized telemetry (and the other use case described below).

## Repeated Values in the Same Packet

The other use case for subpackets is when you have a single packet that has a lot of samples of the same data point in the same packet. Historically COSMOS would put all of these samples into an array item but that has several downsides.

The primary downside is that you couldn't graph the data like a time series in [Telemetry Grapher](/docs/tools/tlm-grapher). Each of the samples generally has its own timestamp (typically derived from a known data rate), but that wasn't usable in [Telemetry Grapher](/docs/tools/tlm-grapher), because there is only one timestamp per packet.

Using a [SUBPACKETIZER](/docs/configuration/telemetry#subpacketizer) to breakup each sample into its own [SUBPACKET](/docs/configuration/telemetry#subpacket) solves this problem, and makes the entire series of subpackets available to [Telemetry Grapher](/docs/tools/tlm-grapher) to graph.

## Optional content

COSMOS packet definitions expect every item in the packet to be present. Subpackets can also be used for optional content by having the Subpacketizer only return the optional content if it is present.

## Defining a Subpacket

Defining a [SUBPACKET](/docs/configuration/telemetry#subpacket) is easy. All it requires is adding the SUBPACKET keyword to the packet definition. Note that both commands and telemetry packets can be marked as [SUBPACKET](/docs/configuration/telemetry#subpacket), but only telemetry is currently processed in any meaningful way.

Subpackets will generally have id fields that the subpacketizer code can use to differentiate them.

Here is an example of what would be one of many possible subpackets in a channelized telemetry scenario in F-Prime. Note that the packet has the [SUBPACKET](/docs/configuration/telemetry#subpacket) marking, and includes ID items:

<Tabs groupId="script-language">
<TabItem value="python" label="Python Subpacketizer">

```python
TELEMETRY <%= target_name %> ServerDeployment.rateGroup3.RgMaxTime BIG_ENDIAN "Max execution time rate group"
  SUBPACKET
  APPEND_ID_ITEM FPRIME_CHANNEL_ID 32 UINT 1024
  APPEND_ITEM FPRIME_TIMEBASE 16 UINT
    STATE TB_NONE 0 # No time base has been established
    STATE TB_PROC_TIME 1 # Indicates time is processor cycle time. Not tied to external time
    STATE TB_WORKSTATION_TIME 2 # Time as reported on workstation where software is running
    STATE TB_DONT_CARE 0xFFFF
  APPEND_ITEM FPRIME_CONTEXT 8 UINT
  APPEND_ITEM FPRIME_TIME_SEC 32 UINT
  APPEND_ITEM FPRIME_TIME_USEC 32 UINT
  APPEND_ITEM RgMaxTime 32 UINT "Max execution time rate group"
  ITEM PACKET_TIME 0 0 DERIVED "Python time based on FPRIME_TIME_SEC and FPRIME_TIME_USEC"
    READ_CONVERSION openc3/conversions/unix_time_conversion.py FPRIME_TIME_SEC FPRIME_TIME_USEC
```

</TabItem>
<TabItem value="ruby" label="Ruby Subpacketizer">

```ruby
TELEMETRY <%= target_name %> ServerDeployment.rateGroup3.RgMaxTime BIG_ENDIAN "Max execution time rate group"
  SUBPACKET
  APPEND_ID_ITEM FPRIME_CHANNEL_ID 32 UINT 1024
  APPEND_ITEM FPRIME_TIMEBASE 16 UINT
    STATE TB_NONE 0 # No time base has been established
    STATE TB_PROC_TIME 1 # Indicates time is processor cycle time. Not tied to external time
    STATE TB_WORKSTATION_TIME 2 # Time as reported on workstation where software is running
    STATE TB_DONT_CARE 0xFFFF
  APPEND_ITEM FPRIME_CONTEXT 8 UINT
  APPEND_ITEM FPRIME_TIME_SEC 32 UINT
  APPEND_ITEM FPRIME_TIME_USEC 32 UINT
  APPEND_ITEM RgMaxTime 32 UINT "Max execution time rate group"
  ITEM PACKET_TIME 0 0 DERIVED "Ruby time based on FPRIME_TIME_SEC and FPRIME_TIME_USEC"
    READ_CONVERSION unix_time_conversion.rb FPRIME_TIME_SEC FPRIME_TIME_USEC
```

</TabItem>
</Tabs>

## Defining a Subpacketizer

A [SUBPACKETIZER](/docs/configuration/telemetry#subpacketizer) is added to the parent packet with the code necessary to break it up into any internal subpackets.

Subpackets receive the parent packet as input and return an array of packets and subpackets as output. They can return as many subpackets as necessary, including no subpackets. Note that if the parent packet is not returned, then it will not be processed.

The following is an example Subpacketizer class that works with the F-Prime Flight Software. Note that this is just one example. A Subpacketizer can contain whatever code necessary to break the packet into subpackets.

<Tabs groupId="script-language">
<TabItem value="python" label="Python Subpacketizer">

```python
from openc3.subpacketizers.subpacketizer import Subpacketizer
from openc3.system.system import System

class FprimeSubpacketizer(Subpacketizer):
    def call(self, packet):
        # Create a list of packets to return
        packets = []

        # Read the packet item "CHANNELS" which contains all the subpackets
        channels = packet.read("CHANNELS")

        # While we still have data to process
        while len(channels) > 0:
            # Identify the next subpacket using the entire block of data
            subpacket = System.telemetry.identify(channels, target_names=[packet.target_name], subpackets=True)

            if subpacket:
                # If it identified then breakout the subpacket content based on fixed size
                # (like the FIXED protocol)
                subpacket.buffer = channels[:subpacket.defined_length]
                subpacket = subpacket.clone()

                # Add to list of subpackets to return
                packets.append(subpacket)

                # Remove this subpacket from the block of data
                channels = channels[subpacket.defined_length:]
            else:
                # If we can't identify then just give up
                break

        # Append the parent packet so it gets processed too
        packets.append(packet)

        # Return the parent packet and subpackets
        return packets

# The Subpacketizer is then referenced in a packet definition like this:
TELEMETRY <%= target_name %> TELEMETRY BIG_ENDIAN "Channelized Telemetry Packet"
  SUBPACKETIZER fprime_subpacketizer.py
  APPEND_ITEM FPRIME_SIZE 32 UINT
  APPEND_ID_ITEM FPRIME_PACKET_ID 32 UINT 1
  APPEND_ITEM CHANNELS -32 BLOCK
    HIDDEN
  ITEM CRC32 -32 32 UINT
```

</TabItem>
<TabItem value="ruby" label="Ruby Subpacketizer">

```ruby
require "openc3/subpacketizers/subpacketizer"
require "openc3/system/system"

module OpenC3
  class FprimeSubpacketizer < Subpacketizer
    def call(packet)
      # Create an array of packets to return
      packets = []

      # Read the packet item "CHANNELS" which contains all the subpackets
      channels = packet.read("CHANNELS")

      # While we still have data to process
      while channels.length > 0
        # Identify the next subpacket using the entire block of data
        subpacket = System.telemetry.identify(channels, [packet.target_name], subpackets: true)
        if subpacket
          # If it identified then breakout the subpacket content based on fixed size
          # (like the FIXED protocol)
          subpacket.buffer = channels[0...subpacket.defined_length]
          subpacket = subpacket.clone()

          # Add to list of subpackets to return
          packets << subpacket

          # Remove this subpacket from the block of data
          channels = channels[subpacket.defined_length..-1]
        else
          # If we can't identify then just give up
          break
        end
      end

      # Append the parent packet so it gets processed too
      packets << packet

      # Return the parent packet and subpackets
      return packets
    end
  end
end

# The Subpacketizer is then referenced in a packet definition like this:
TELEMETRY <%= target_name %> TELEMETRY BIG_ENDIAN "Channelized Telemetry Packet"
  SUBPACKETIZER fprime_subpacketizer.rb
  APPEND_ITEM FPRIME_SIZE 32 UINT
  APPEND_ID_ITEM FPRIME_PACKET_ID 32 UINT 1
  APPEND_ITEM CHANNELS -32 BLOCK
    HIDDEN
  ITEM CRC32 -32 32 UINT

```

</TabItem>
</Tabs>
