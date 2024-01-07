---
title: Log Structure
---

Updated: 8-21-2023 to the format as of OpenC3 COSMOS 5.11.0

## Packet Log File Format

Packet logs in OpenC3 COSMOS 5 are used to store raw binary packets as received from various targets, as
well as decommutated packets stored as JSON structures.

### File Header

COSMOS 5 Packet log files start with the 8-character sequence "COSMOS5\_". This can be used to identify the type of file independent of filename and differentiate them from newer and older versions.

### Entry Types

Packet log files have 6 different entry types with room for future expansion. All entry headers are big endian binary data.

#### Common Entry Format

This common format is used for all packet log entries:

| Field              | Data Type               | Description                                                                                                                                          |
| ------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Length             | 32-bit Unsigned Integer | Total length of the entry in bytes not including the length field. Max entry size is therefore 4GiB.                                                 |
| Entry Type         | 4-bit Unsigned Integer  | Entry Type:<br/>1 = Target Declaration<br/>2 = Packet Declaraction<br/>3 = Raw Packet<br/>4 = JSON/CBOR Packet<br/>5 = Offset Marker<br/>6 = Key Map |
| Cmd/Tlm Flag       | 1-bit Unsigned Integer  | 1 = Command<br/>0 = Telemetry                                                                                                                        |
| Stored Flag        | 1-bit Unsigned Integer  | 1 = Stored Data<br/>0 = Realtime Data                                                                                                                |
| Id Flag            | 1-bit Unsigned Integer  | 1 = ID present<br/>0 = ID not present                                                                                                                |
| CBOR Flag          | 1-bit Unsigned Integer  | Only Valid for "JSON/CBOR Packets"<br/>1 = CBOR Data<br/>0 = JSON Data                                                                               |
| Extra Flag         | 1-bit Unsigned Integer  | 1 = Extra present<br/>0 = Extra Not Present (Added COSMOS 5.11)                                                                                      |
| Received Time Flag | 1-bit Unsigned Integer  | 1 = Received Time Present<br/>0 = No Received Time (Added COSMOS 5.11.0)                                                                             |
| Reserved           | 6-bit Unsigned Integer  | Reserved for Future expansion. Should be set to 0 if unused.                                                                                         |
| Entry Data         | Variable                | Unique data based on entry type. See Entry Types Below                                                                                               |
| Id (Optional)      | 32-byte Binary Hash     | If the ID field is set, this is a binary 256-bit SHA-256 hash uniquely identifying a target configuration or packet configuration                    |

#### Target Declaration Entry

Declares the name of a target the first time it is seen when writing the log file.

| Field       | Data Type                    | Description |
| ----------- | ---------------------------- | ----------- |
| Target Name | Variable-Length ASCII String | Target Name |

#### Packet Declaration Entry

Declares the name of a packet the first time it is seen when writing the log file. References the associated target name by index.

| Field        | Data Type                    | Description                                                                                                                                                                                                        |
| ------------ | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Target Index | 16-bit Unsigned Integer      | Index into a dynamically built table of target names, generated from the order of the target declarations in the file. The first target declaration gets index 0, the second target declaration gets index 1, etc. |
| Packet Name  | Variable-Length ASCII String | Packet Name                                                                                                                                                                                                        |

#### Raw Packet and JSON Packet Entries

Holds the main data for a packet. Raw packets are the data before the COSMOS decommutation phase. "JSON" packets are the data after decommutation. Note that "JSON" packets are now generally stored as CBOR rather than JSON to reduce storage size.

| Field                         | Data Type                  | Description                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Packet Index                  | 16-bit Unsigned Integer    | Index into a dynamically built table of cmd_or_tlm/target name/packet name tuples, generated from the order of the packet declarations in the file. The first packet declaration gets index 0, the second packet declaration gets index 1, etc. This limits the max number of unique packet types in a single file to 65536.                                                   |
| Packet Timestamp              | 64-bit Unsigned Integer    | Packet timestamp in nanoseconds from the unix epoch (Jan 1st, 1970, midnight). This field contains the “packet time” for both Raw and JSON packet entries (which are used to store decommutated date). For JSON packet entries, the packet received time can also be extracted from the JSON data if needed.                                                                   |
| Received Timestamp (Optional) | 64-bit Unsigned Integer    | Only present if Received Time Flag is Set (Only currently in Raw log files). Received timestamp in nanoseconds from the unix epoch (Jan 1st, 1970, midnight). This field contains the received time” for both Raw packet entries (which are used to store decommutated date). For JSON packet entries, the packet received time can be extracted from the JSON data if needed. |
| Extra Length (Optional)       | 32-bit Unsigned Integer    | Only Present if Extra Flag is Set. Length of extra data in bytes not including itself.                                                                                                                                                                                                                                                                                         |
| Extra Data (Optional)         | Variable-Length Block Data | Only Present if Extra Flag is Set. CBOR or JSON encoded object of extra data.                                                                                                                                                                                                                                                                                                  |
| Packet Data                   | Variable-Length Block Data | The Raw binary packet data for Raw Packet entries, and ASCII JSON data (or CBOR if flag set) for JSON packet entries. Note the Common Entry Format Id field is not supported with either type of packet entry.                                                                                                                                                                 |

#### Offset Marker Entry

This contains the Redis stream offset for the last packet stored in this log file. This entry allows for a seamless transition from log files to Redis streams holding the most recent data received by COSMOS.

| Field         | Data Type                    | Description         |
| ------------- | ---------------------------- | ------------------- |
| Offset Marker | Variable-Length ASCII String | Redis Offset Marker |

#### Key Map Entry

The key map entry is used to further reduce log file sizes by reducing the size of the names of the decommutated values. Each value is given a numeric name counting up from 0 which drastically reduces decommutated data size. Note: This could be further enhanced in the future by changing to a denser encoding similar to base64. The key map is generated on the first reception of a packet. If future packets have different keys, then the names are used as-is and no reduction is gained. Typically packet keys don't change within a file.

| Field        | Data Type                    | Description                                                                                                                                                                                                        |
| ------------ | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Packet Index | 16-bit Unsigned Integer      | Index into a dynamically built table of packet names, generated from the order of the packet declarations in the file. The first packet declaration gets index 0, the second packet declaration gets index 1, etc. |
| Key Map      | Variable-Length ASCII String | Key Map Data with Mapping from numeric key to actual packet item name                                                                                                                                              |
