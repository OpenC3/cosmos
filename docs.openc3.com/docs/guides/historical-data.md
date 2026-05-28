---
title: Historical Data Ingest
description: Ingest recorded telemetry files via FileInterface
sidebar_custom_props:
  myEmoji: 🗄️
---

This guide describes a pattern for ingesting historical telemetry into COSMOS using the [FileInterface](/docs/configuration/interfaces#file-interface). For this guide, the following example is used. A historical file dump contains a per-file header describing the recording (timestamps, identifiers, record count, etc.) followed by a stream of records. Each record also contains a header followed by a complete COSMOS telemetry packet.

## File Format

Our example file format consists of COSMOS TLM Packets with message headers contained within a larger file-level header. For the initial example, we discard all headers and simply want to ingest the embedded COSMOS Tlm Packets.

```
+--------------------------------------------------+
| File Header (20 bytes).                          |  <- file-level
|   uint32 Length, RecordCount, DumpID,            |     headers stripped by
|          TimeSeconds, TimeSubSeconds             |     DISCARD_FILE_HEADER_BYTES
+==================================================+
| Repeated RecordCount times:                      |
|   Message Record Header (20 bytes)               |  <- stripped by
|     uint32 RecordNumber, MsgId, MsgSize,         |     LENGTH protocol
|            TimeSeconds, TimeSubSeconds,          |     discard_leading_bytes
|   COSMOS TLM Packet (variable length)            |
+--------------------------------------------------+
```

## Processing Telemetry Packets

If the file header and message record headers contain only extraneous information that can be discarded, the solution can use the unmodified COSMOS interfaces and protocols.

### Plugin Configuration

Configure the interface in `plugin.txt`. The `LENGTH` protocol is attached via a separate `PROTOCOL READ` directive so its arguments can be space-separated.

```cosmos
INTERFACE FILE_INT openc3/interfaces/file_interface.py None /dropbox /archive 65536 True None None
  PROTOCOL READ openc3/interfaces/protocols/length_protocol.py 64 32 20 1 BIG_ENDIAN 20
  MAP_TLM_TARGET INST2 # <!- Change to the name of your target
  OPTION THROTTLE 5
  # Discard the file header information
  OPTION DISCARD_FILE_HEADER_BYTES 20
```

| Argument                              | Meaning                                                                                 |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `openc3/interfaces/file_interface.py` | Standard COSMOS file interface                                                          |
| `None`                                | No command write folder (read-only ingest)                                              |
| `/dropbox`                            | Folder watched for new files                                                            |
| `/archive`                            | Folder files are moved to after ingest (`DELETE` to remove instead)                     |
| `65536`                               | Bytes per read from the file                                                            |
| `True`                                | Mark ingested telemetry as stored (historical)                                          |
| `None None`                           | `protocol_type` / `protocol_args` — protocol attached via `PROTOCOL READ` below instead |

`PROTOCOL READ` arguments (`length_protocol.py`):

| Argument     | Meaning                                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------------------- |
| `64`         | Length field starts at bit offset 64 (= byte 8) — the `MsgSize` position in the record header                   |
| `32`         | Length field is 32 bits                                                                                         |
| `20`         | Add 20 to the length value to get the total record size (the 20-byte record header is not counted in `MsgSize`) |
| `1`          | Length is in bytes                                                                                              |
| `BIG_ENDIAN` | Length field endianness                                                                                         |
| `20`         | Discard 20 leading bytes per record before passing to the identifier — strips the Message Record Header         |

### Design Notes

- **`FileInterface` protocol strips file header.** The protocol strips the 20 bytes of the file header via `DISCARD_FILE_HEADER_BYTES 20` leaving only the records with headers.
- **`LENGTH` protocol handles each record.** Each record looks like `[20-byte Message Record Header][COSMOS packet]`. The stock `LengthProtocol` reads `MsgSize` from the record header, add 20 to the length to account for the header, then discards the 20 byte header passing on only the COSMOS packet.

### Bind Mounts in Docker

Expose `/dropbox` and `/archive` to the operator container in `compose.yaml`:

```yaml
volumes:
  - /home/user/dropbox:/dropbox
  - /home/user/archive:/archive
```

`FileInterface` moves each ingested file from `/dropbox` to `/archive` after reading it.

### Testing the Configuration

At this point you can start COSMOS and generate a file as described in [Building a Test File](#building-a-test-file).

## Keeping the File Header

It there is information in the File Header that you wish to track (download IDs, etc) you can inject this telemetry into COSMOS as a packet. This requires additional steps:

1. Define the telemetry packet that captures the file-level header.
2. Subclass `FileInterface` so the file-level header is consumed once per file and injected as its own telemetry packet via `inject_tlm`.

### ARCHIVE Telemetry Packet

Define a telemetry packet that holds the file-level headers. The interface subclass injects one instance of this packet per ingested file.

```cosmos
TELEMETRY TARGET ARCHIVE BIG_ENDIAN "Archive telemetry"
  APPEND_ID_ITEM PKT_ID        32 UINT 10000
  APPEND_ITEM LENGTH           32 UINT
  APPEND_ITEM RECORD_COUNT     32 UINT
  APPEND_ITEM DUMP_ID          32 UINT
  APPEND_ITEM TIME_SECONDS     32 UINT
  APPEND_ITEM TIME_SUBSECONDS  32 UINT
```

The packet has an `ID_ITEM` called `PKT_ID` to prevent it from becoming a "catch-all" packet. This is a virtual packet only and `inject_tlm` writes it directly.

### ArchiveInterface Subclass

The stock `FileInterface` streams bytes from the watched folder through its protocol stack. To pull the file-level header out before the protocol stack sees the record stream, subclass `FileInterface` and override `read_interface` so a custom `_consume_file_header` runs each time a new file is opened.

Place this file in your target's lib directory, e.g. `targets/INST2/lib/archive_interface.py`:

```python
import os
import gzip
import struct
import shutil # Only if needed to override finish_file

from openc3.api.tlm_api import inject_tlm
from openc3.interfaces.file_interface import FileInterface

PKT_ID = 10000
FILE_HEADER_SIZE = 20  # five 32 bit fields
RECORD_HEADER_SIZE = 20  # five 32 bit fields
TOTAL_HEADER_SIZE = FILE_HEADER_SIZE + RECORD_HEADER_SIZE


class ArchiveInterface(FileInterface):
    def __init__(
        self,
        command_write_folder,
        telemetry_read_folder,
        telemetry_archive_folder,
        file_read_size=65536,
        stored=True,
        protocol_type=None,
        protocol_args=None,
        archive_target_name="TGT",
        archive_packet_name="PKT",
    ):
        super().__init__(
            command_write_folder,
            telemetry_read_folder,
            telemetry_archive_folder,
            file_read_size,
            stored,
            protocol_type,
            protocol_args,
        )
        self.archive_target_name = archive_target_name
        self.archive_packet_name = archive_packet_name

    # Most of this is simply copying the existing read_interface implementation
    def read_interface(self):
        while True:
            if self.file:
                data = self.file.read(self.file_read_size)
                if self.throttle and self.sleeper.sleep(self.throttle):
                    return None, None
                if data is not None and len(data) > 0:
                    self.read_interface_base(data, None)
                    return data, None
                else:
                    self.finish_file()

            file = self.get_next_telemetry_file()
            if file:
                if file.endswith(".gz"):
                    self.file = gzip.open(file, "rb")
                else:
                    self.file = open(file, "rb")
                self.file_path = file
                if self.discard_file_header_bytes is not None:
                    self.file.read(self.discard_file_header_bytes)
                self._consume_file_header()  # <!- NEW METHOD
                continue

            result = self.queue.get()
            if result is None:
                return None, None

    # This is where we read the file header and save it as a packet
    def _consume_file_header(self):
        header = self.file.read(TOTAL_HEADER_SIZE)
        if len(header) < TOTAL_HEADER_SIZE:
            return
        item_hash = self._parse_file_header(header)
        inject_tlm(self.archive_target_name, self.archive_packet_name, item_hash)

    @staticmethod
    def _parse_file_header(header):
        (length, record_count, dump_id, time_seconds, time_subseconds) = struct.unpack(">IIIII", header[0:20])
        return {
            "PKT_ID": PKT_ID,
            "LENGTH": length,
            "RECORD_COUNT": record_count,
            "DUMP_ID": dump_id,
            "TIME_SECONDS": time_seconds,
            "TIME_SUBSECONDS": time_subseconds,
        }

    # Override finish_file before COSMOS 7.2 to change os.rename which raised EXDEV / "Cross-device link"
    # on separate Docker bind mounts to shutil.move which uses copy+delete across filesystems
    # This issue was fixed in the COSMOS 7.2 release and this is no longer needed.
    def finish_file(self):
        self.file.close()
        self.file = None
        if self.telemetry_archive_folder == "DELETE":
            os.remove(self.file_path)
        else:
            new_path = os.path.join(self.telemetry_archive_folder, os.path.basename(self.file_path))
            shutil.move(self.file_path, new_path)
        self.file_path = None
```

### Plugin Configuration

Configure the interface in `plugin.txt`. The stock `FileInteface` is now replaced by `archive_interface.py`. Note we're passing `TARGET ARCHIVE` as parameters to make this more flexible. The `LENGTH` protocol is attached via a separate `PROTOCOL READ` directive so its arguments can be space-separated. The `DISCARD_FILE_HEADER_BYTES` is removed because our interface handles that directly.

```cosmos
# Change TARGET ARCHIVE to the name of your target / packet
INTERFACE FILE_INT archive_interface.py None /dropbox /archive 65536 True None None TARGET ARCHIVE
  PROTOCOL READ openc3/interfaces/protocols/length_protocol.py 64 32 20 1 BIG_ENDIAN 20
  MAP_TLM_TARGET TARGET # <!- Change to your target name
  OPTION THROTTLE 5
```

### Design Notes

- **`ArchiveInterface` protocol processes file header.** The protocol processes the 20 bytes of the file header and internally calls `inject_tlm`.
- **`LENGTH` protocol handles each record.** Each record looks like `[20-byte Message Record Header][COSMOS packet]`. The stock `LengthProtocol` reads `MsgSize` from the record header, add 20 to the length to account for the header, then discards the 20 byte header passing on only the COSMOS packet.

### Bind Mounts in Docker

Expose `/dropbox` and `/archive` to the operator container in `compose.yaml`:

```yaml
volumes:
  - /home/user/dropbox:/dropbox
  - /home/user/archive:/archive
```

`FileInterface` moves each ingested file from `/dropbox` to `/archive` after reading it.

### Testing the Configuration

At this point you can start COSMOS and generate a file as described next.

## Building a Test File

The following script produces a test file with `--count` records and drops it in the watched folder. Run it on the host where the bind mount lives — the operator container is read-only and runs as a different uid, so writes from inside the container often fail.

The example uses a placeholder CCSDS payload to keep the script self-contained. Replace `build_payload` with bytes that match a real telemetry packet from your target (matching APID/ID, size, and length field) so COSMOS can identify and decom each record.

```python
import argparse
import os
import pathlib
import struct
import time

FILE_HEADER_SIZE = 20    # uint32 Length, RecordCount, DumpID, TimeSec, TimeSubs
RECORD_HEADER_SIZE = 20  # uint32 RecordNumber, MsgId, MsgSize, TimeSec, TimeSubs

# --- Example payload: replace with bytes for your target's packet ---
PAYLOAD_MSG_ID = 1
PAYLOAD_SIZE = 64
def build_payload(seq_count, time_sec):
    # Toy CCSDS-like header (6 bytes) followed by zero-filled body.
    word0 = PAYLOAD_MSG_ID & 0x07FF
    word1 = (0b11 << 14) | (seq_count & 0x3FFF)
    ccsds_length = PAYLOAD_SIZE - 7
    header = struct.pack(">HHH", word0, word1, ccsds_length)
    # Also be sure to set any secondary headers and time fields of your packet
    # so COSMOS correct interprets the PACKET_TIME
    return header + b"\x00" * (PAYLOAD_SIZE - len(header))
# --- end example payload ---


def build_file_header(total_length, record_count, dump_id, time_sec, time_subs):
    return struct.pack(">IIIII", total_length, record_count, dump_id, time_sec, time_subs)


def build_record_header(record_number, msg_id, msg_size, time_sec, time_subs):
    return struct.pack(">IIIII", record_number, msg_id, msg_size, time_sec, time_subs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dropbox", default=str(pathlib.Path.home() / "dropbox"))
    parser.add_argument("--count", type=int, default=2)
    parser.add_argument("--dump-id", type=int, default=1)
    args = parser.parse_args()

    now_sec = int(time.time())
    records = b""
    for i in range(1, args.count + 1):
        payload = build_payload(i, now_sec)
        records += build_record_header(i, PAYLOAD_MSG_ID, len(payload), now_sec, 0) + payload

    total_length = FILE_HEADER_SIZE + len(records)
    file_hdr = build_file_header(total_length, args.count, args.dump_id, now_sec, 0)

    pathlib.Path(args.dropbox).mkdir(parents=True, exist_ok=True)
    out_path = os.path.join(args.dropbox, f"archive_{now_sec}.bin")
    with open(out_path, "wb") as f:
        f.write(file_hdr + records)
    print(f"Wrote {os.path.getsize(out_path)} bytes to {out_path}")


if __name__ == "__main__":
    main()
```

### Verifying Ingest

After running the script, two things should happen in COSMOS:

1. One `TARGET ARCHIVE` packet appears with the parsed file-level header (LENGTH, RECORD_COUNT, DUMP_ID, TIME_SECONDS, TIME_SUBSECONDS).
2. `--count` instances of the inner packet appear with `stored=True`.

The source file moves from `/dropbox` to `/archive` after ingest. View these via Telemetry Viewer, Packet Viewer, or by querying the historical store.

```python
print(tlm("TARGET ARCHIVE RECORD_COUNT"))
print(tlm("TARGET ARCHIVE DUMP_ID"))
print(tlm("TARGET ARCHIVE TIME_SECONDS"))
```

## Troubleshooting

| Error                                                                | Cause                                                                                        | Fix                                                                                                                                                      |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `OSError: [Errno 18] Cross-device link` on `finish_file`             | `/dropbox` and `/archive` are separate bind mounts                                           | `FileInterface.finish_file` now uses `shutil.move`; pull latest COSMOS or override in your subclass                                                      |
| `No such file or directory: '/dropbox/...'` when running the builder | Builder run inside the read-only operator container with insufficient bind-mount permissions | Run the builder on the host (where the bind-mount source folder is user-owned. Also ensure the docker.compose lists the `dropbox` and `archive` volues.) |
| Bytes consumed but no inner packets appear                           | `LENGTH` protocol args wrong — `MsgSize` semantics or discard count mismatched               | Verify `MsgSize` counts payload bytes only (not record header + payload) and `discard_leading_bytes` correct                                             |
| `TARGET ARCHIVE` packet never appears                                | File shorter than header bytes, or `_consume_file_header` returned early                     | Check that the file has the full header before any records                                                                                               |
