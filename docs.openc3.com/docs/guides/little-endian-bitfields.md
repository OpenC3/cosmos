---
title: Little Endian Bitfields
---

Defining little endian bitfields is a little weird but is possible in COSMOS. However, note that APPEND does not work with little endian bitfields.

Here are the rules on how COSMOS handles LITTLE_ENDIAN data:

1. COSMOS bit offsets are always defined in BIG_ENDIAN terms. Bit 0 is always the most significant bit of the first byte in a packet, and increasing from there.

1. All 8, 16, 32, and 64-bit byte-aligned LITTLE_ENDIAN data types define their bit_offset as the most significant bit of the first byte in the packet that contains part of the item. (This is exactly the same as BIG_ENDIAN). Note that for all except 8-bit LITTLE_ENDIAN items, this is the LEAST significant byte of the item.

1. LITTLE_ENDIAN bit fields are defined as any LITTLE_ENDIAN INT or UINT item that is not 8, 16, 32, or 64-bit and byte aligned.

1. LITTLE_ENDIAN bit fields must define their bit_offset as the location of the most significant bit of the bitfield in BIG_ENDIAN space as described in rule 1 above. So for example. The following C struct at the beginning of a packet would be defined like so:

```c
struct {
  unsigned short a:4;
  unsigned short b:8;
  unsigned short c:4;
}

ITEM A 4 4 UINT "struct item a"
ITEM B 12 8 UINT "struct item b"
ITEM C 8 4 UINT "struct item c"
```

This is hard to visualize, but the structure above gets spread out in a byte array like the following after byte swapping: least significant 4 bits of b, 4-bits a, 4-bits c, most significant 4 bits of b.

The best advice is to experiment and use the View Raw feature in the Command and Telemetry Service to inspect the bytes of the packet and adjust as necessary.
