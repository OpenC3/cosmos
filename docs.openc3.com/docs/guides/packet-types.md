---
title: Packet Types
description: Understanding Different Packet Types
sidebar_custom_props:
  myEmoji: 📦
---

## Regular Packets

Most packets defined in COSMOS are "regular packets". These are standard command and telemetry packets that flow through interfaces. Regular telemetry packets are identified at the interface level and then the identified raw packets flow through Redis streams for additional processing like decomutation and logging.

## LATEST

LATEST is a special packet name that can be used in place of an actual packet name when retrieving telemetry. It returns the most recently received value of a telemetry item across all packets that contain it. This is useful in systems where the same telemetry item appears in multiple packets, potentially at different rates.

For example, assume the target INST has two packets: PACKET1 and PACKET2. Both packets have a telemetry item called TEMP.

```ruby
# Get the value of TEMP from the most recently received PACKET1
value = tlm("INST PACKET1 TEMP")
# Get the value of TEMP from the most recently received PACKET2
value = tlm("INST PACKET2 TEMP")
# Get the value of TEMP from whichever packet (PACKET1 or PACKET2) was received most recently
value = tlm("INST LATEST TEMP")
```

LATEST works by comparing the `PACKET_TIMESECONDS` timestamp of each packet containing the requested item in the Current Value Table (CVT) and selecting the one with the newest timestamp.

LATEST can be used with:

- [tlm, tlm_raw, tlm_formatted](/docs/guides/scripting-api#tlm-tlm_raw-tlm_formatted) for reading telemetry values
- [Telemetry Screen](/docs/configuration/telemetry-screens) widgets like LABELVALUE and FORMATVALUE
- [get_tlm_values](/docs/guides/scripting-api#get_tlm_values) for reading multiple values at once

:::note
LATEST cannot be used with methods that operate on entire packets such as [get_tlm_packet](/docs/guides/scripting-api#get_tlm_packet) or [get_tlm_buffer](/docs/guides/scripting-api#get_tlm_buffer) since those require a specific packet name. If an item only exists in a single packet, LATEST still works but is equivalent to using the packet name directly.
:::

## Subpackets

Subpackets are marked with the keyword [SUBPACKET](/docs/configuration/telemetry#subpacket). Subpackets exist inside of regular packets and are identified and broken out during decom processing by a [SUBPACKETIZER](/docs/configuration/telemetry#subpacketizer) Python/Ruby class. Subpackets are used for channelized telemetry and for multi-sampled telemetry points in a regular packet. They can also be used for any content that may or may not be present in the parent packet. Note: because subpackets exist inside of regular packets, there is no "raw" version of a subpacket ie. the raw subpacket is part of its parent regular packet.

## Virtual Packets

[VIRTUAL](/docs/configuration/telemetry#virtual) packets are used to define structures that can be used inside of regular packets or subpackets. Virtual packets are not identified by either interfaces or subpacketizers, and generally contain no ID fields (though they can).

The [STRUCTURE](/docs/configuration/telemetry#structure) and [APPEND_STRUCTURE](/docs/configuration/telemetry#append_structure) keywords can be used to add the fields from a virtual packet to a regular packet or subpacket.

Packets marked [VIRTUAL](/docs/configuration/telemetry#virtual) are also automatically marked HIDDEN and DISABLED.

## Stored Packets

Packets can be marked as "stored" which means they represent non-realtime data such as back-orbit data, recorded data playback, or data read from files. Stored packets are fully processed through the COSMOS pipeline (identification, decommutation, logging) but they **do not update the Current Value Table (CVT)**. This means stored telemetry will not affect real-time displays like Packet Viewer or Telemetry Viewer.

The stored flag is primarily set in two ways:

1. **By an Interface** - The [File Interface](../configuration/interfaces#file-interface) has a `Stored` parameter (default: true) that automatically marks all telemetry read from files as stored.
2. **By a Protocol** - Custom protocols can set `packet.stored = true` in their `read_packet()` method. The [Preidentified Protocol](../configuration/protocols#preidentified-protocol) also encodes and decodes the stored flag in its packet header.

When building a [Custom Interface](../configuration/interfaces#custom-interfaces), you can set the stored flag on packets returned by the `read` method. When building a [Custom Protocol](../configuration/protocols#custom-protocols), the `read_packet()` method is the appropriate place to set the stored flag. See those sections for more details.

Common use cases for stored packets include:

- Processing archived telemetry files through the [File Interface](../configuration/interfaces#file-interface)
- Replaying recorded data without disrupting real-time displays
- Ingesting back-orbit or store-and-forward data from a spacecraft

:::note
Stored packets are still logged and available in tools like Telemetry Grapher and Data Extractor. The only difference is they do not update the CVT, so they won't change values shown in Packet Viewer, Telemetry Viewer, or affect LATEST packet lookups.
:::

## Hidden Packets

[HIDDEN](/docs/configuration/command#hidden-1) packets are regular packets that are intentionally hidden from packet chooser widgets and from code completion. Hidden command packets can still be sent from scripts. Hidden telemetry packet data can still be used in TlmViewer screens.

## Disabled Packets

[DISABLED](/docs/configuration/command#disabled) packets are the same as hidden, except disabled command packets also cannot be sent. The [disable_cmd](/docs/guides/scripting-api#disable_cmd) and [enable_cmd](/docs/guides/scripting-api#enable_cmd) api methods can be used to temporarily make a command disabled or enabled.

## Hazardous Packets

[HAZARDOUS](/docs/configuration/command#hazardous) command packets will present the user with an "Are You Sure?" message before being sent. Using [cmd_no_hazardous_check](/docs/guides/scripting-api#cmd_no_hazardous_check) can be used to avoid this popup for automated scripts.

Hazardous commands also require additional approval if [Critical Commanding](/docs/configuration/command#critical-commanding-enterprise) is enabled in COSMOS Enterprise.

## Restricted Packets

[RESTRICTED](/docs/configuration/command#restricted) command packets require additional approval if [Critical Commanding](/docs/configuration/command#critical-commanding-enterprise) is enabled in COSMOS Enterprise.

Note that restricted packets don't cause an "Are You Sure?" dialog.
