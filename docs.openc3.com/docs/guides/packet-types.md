---
title: Packet Types
description: Understanding Different Packet Types
sidebar_custom_props:
  myEmoji: 📦
---

## Regular Packets

Most packets defined in COSMOS are "regular packets". These are standard command and telemetry packets that flow through interfaces. Regular telemetry packets are identified at the interface level and then the identified raw packets flow through Redis streams for additional processing like decomutation and logging.

## Subpackets

Subpackets are marked with the keyword SUBPACKET. Subpackets exist inside of regular packets and are identified and broken out during decom processing by a SUBPACKETIZER Python/Ruby class. Subpackets are used for channelized telemetry and for multi-sampled telemetry points in a regular packet. They can also be used for any content that may or may not be present in the parent packet. Note: because subpackets exist inside of regular packets, their is no "raw" version of a subpacket ie. the raw subpacket is part of its parent regular packet.

## Virtual Packets

Virtual packets are used to define structures that can be used inside of regular packets or subpackets. Virtual packets are not identified by either interfaces or subpacketizers, and generally contain no ID fields (though they can).

The STRUCTURE and APPEND_STRUCTURE keywords can be used to add the fields from a virtual packet to a regular packet or subpacket.

Packets marked VIRTUAL are also automatically marked HIDDEN and DISABLED.

## Hidden Packets

Hidden packets are regular packets that are intentionally hidden from packet chooser widgets and from code completion. Hidden command packets can still be sent from scripts. Hidden telemetry packet data can still be used in TlmViewer screens.

## Disabled Packets

Disabled packets are the same as hidden, except disabled command packets also cannot be sent. The disable_cmd and enable_cmd api methods can be used to temporarily make a command disabled or enabled.

## Hazardous Packets

Hazardous command packets will present the user with an "Are You Sure?" message before being sent. Using cmd_no_hazardous_check can be used to avoid this popup for automated scripts.

Hazardous commands also require additional approval if critical commanding is enabled in COSMOS Enterprise.

## Restricted Packets

Restricted command packets require additional approval if critical commanding is enabled in COSMOS Enterprise.

Note that restricted packets don't cause an "Are You Sure?" dialog.
