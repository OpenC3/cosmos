# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Packet log writer for COSMOS5 binary log files.

Creates packet logs containing either commands or telemetry in raw or JSON format.
This is a port of the Ruby PacketLogWriter class.
"""

import json
import os
import struct
from datetime import datetime, timezone
from typing import Optional, Dict
import cbor2

from openc3.logs.packet_log_constants import (
    OPENC3_FILE_HEADER,
    OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK,
    OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK,
    OPENC3_RAW_PACKET_ENTRY_TYPE_MASK,
    OPENC3_JSON_PACKET_ENTRY_TYPE_MASK,
    OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK,
    OPENC3_KEY_MAP_ENTRY_TYPE_MASK,
    OPENC3_CMD_FLAG_MASK,
    OPENC3_STORED_FLAG_MASK,
    OPENC3_ID_FLAG_MASK,
    OPENC3_CBOR_FLAG_MASK,
    OPENC3_EXTRA_FLAG_MASK,
    OPENC3_RECEIVED_TIME_FLAG_MASK,
    OPENC3_PRIMARY_FIXED_SIZE,
    OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE,
    OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE,
    OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE,
    OPENC3_OFFSET_MARKER_SECONDARY_FIXED_SIZE,
    OPENC3_PACKET_SECONDARY_FIXED_SIZE,
    OPENC3_ID_FIXED_SIZE,
    OPENC3_RECEIVED_TIME_FIXED_SIZE,
    OPENC3_EXTRA_LENGTH_FIXED_SIZE,
    OPENC3_MAX_PACKET_INDEX,
    OPENC3_MAX_TARGET_INDEX,
)


class PacketLogWriter:
    """
    Writes packet log files in COSMOS5 format.

    Supports both raw packet data and JSON (decommutated) packet data.
    """

    # Entry types
    TARGET_DECLARATION = "TARGET_DECLARATION"
    PACKET_DECLARATION = "PACKET_DECLARATION"
    RAW_PACKET = "RAW_PACKET"
    JSON_PACKET = "JSON_PACKET"
    OFFSET_MARKER = "OFFSET_MARKER"
    KEY_MAP = "KEY_MAP"

    # Data formats
    CBOR = "CBOR"
    JSON = "JSON"

    def __init__(self, log_directory: str, label: str = "DEFAULT", data_format: str = "CBOR"):
        """
        Initialize the packet log writer.

        Args:
            log_directory: Directory to write log files
            label: Label for the log filename
            data_format: "CBOR" or "JSON" for JSON packet encoding
        """
        self.log_directory = log_directory
        self.label = label
        self.data_format = data_format

        self._file = None
        self._filename = None
        self._file_size = 0

        # Packet table tracking
        self._cmd_packet_table: Dict[str, Dict[str, int]] = {}
        self._tlm_packet_table: Dict[str, Dict[str, int]] = {}
        self._key_map_table: Dict[int, Dict[str, str]] = {}
        self._target_indexes: Dict[str, int] = {}
        self._next_target_index = 0
        self._next_packet_index = 0

        # Timestamps
        self._first_time: Optional[int] = None
        self._last_time: Optional[int] = None

        # Offset tracking
        self._last_offsets: Dict[str, str] = {}

    @property
    def filename(self) -> Optional[str]:
        """The current log filename."""
        return self._filename

    @property
    def file_size(self) -> int:
        """The current file size in bytes."""
        return self._file_size

    def start_new_file(self):
        """Start a new log file."""
        if self._file:
            self.close_file()

        # Generate filename
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")[:20]
        self._filename = os.path.join(self.log_directory, f"{timestamp}__{self.label}.bin")

        self._file = open(self._filename, "wb")
        self._file.write(OPENC3_FILE_HEADER)
        self._file_size = len(OPENC3_FILE_HEADER)

        # Reset tables for new file
        self._cmd_packet_table = {}
        self._tlm_packet_table = {}
        self._key_map_table = {}
        self._target_indexes = {}
        self._next_target_index = 0
        self._next_packet_index = 0
        self._first_time = None
        self._last_time = None

    def close_file(self):
        """Close the current log file."""
        if self._file:
            # Write offset markers before closing
            for redis_topic, last_offset in self._last_offsets.items():
                self._write_offset_marker(f"{last_offset},{redis_topic}")

            self._file.close()
            self._file = None

    def shutdown(self):
        """Shutdown the writer and close any open file."""
        self.close_file()

    def write(
        self,
        entry_type: str,
        cmd_or_tlm: str,
        target_name: str,
        packet_name: str,
        time_nsec_since_epoch: int,
        stored: bool,
        data,
        id: Optional[str] = None,
        redis_offset: str = "0-0",
        received_time_nsec_since_epoch: Optional[int] = None,
        extra: Optional[dict] = None,
    ):
        """
        Write an entry to the log file.

        Args:
            entry_type: One of TARGET_DECLARATION, PACKET_DECLARATION, RAW_PACKET, JSON_PACKET, OFFSET_MARKER, KEY_MAP
            cmd_or_tlm: "CMD" or "TLM"
            target_name: Target name
            packet_name: Packet name
            time_nsec_since_epoch: Timestamp in nanoseconds since epoch
            stored: Whether this is stored data
            data: The data to write (bytes for RAW_PACKET, dict/str for JSON_PACKET)
            id: Optional 64-character hex ID
            redis_offset: Redis stream offset
            received_time_nsec_since_epoch: Optional received timestamp
            extra: Optional extra metadata dict
        """
        if self._file is None:
            self.start_new_file()

        self._write_entry(
            entry_type,
            cmd_or_tlm,
            target_name,
            packet_name,
            time_nsec_since_epoch,
            stored,
            data,
            id,
            received_time_nsec_since_epoch=received_time_nsec_since_epoch,
            extra=extra,
        )

    def _get_packet_index(
        self, cmd_or_tlm: str, target_name: str, packet_name: str, entry_type: str, data
    ) -> int:
        """Get or create the packet index for a target/packet combination."""
        if cmd_or_tlm == "CMD":
            target_table = self._cmd_packet_table.get(target_name)
        else:
            target_table = self._tlm_packet_table.get(target_name)

        if target_table:
            packet_index = target_table.get(packet_name)
            if packet_index is not None:
                return packet_index
        else:
            # New target - need to write target declaration
            target_table = {}
            if cmd_or_tlm == "CMD":
                self._cmd_packet_table[target_name] = target_table
            else:
                self._tlm_packet_table[target_name] = target_table
            self._write_target_declaration(target_name)

        # New packet - need to write packet declaration
        packet_index = self._next_packet_index
        if packet_index > OPENC3_MAX_PACKET_INDEX:
            raise ValueError("Packet Index Overflow")

        target_table[packet_name] = packet_index
        self._next_packet_index += 1

        self._write_packet_declaration(cmd_or_tlm, target_name, packet_name)

        # For JSON packets, write key map if not already done
        if entry_type == self.JSON_PACKET:
            if packet_index not in self._key_map_table:
                parsed = data if isinstance(data, dict) else json.loads(data)
                keys = list(parsed.keys())
                key_map = {str(i): key for i, key in enumerate(keys)}
                reverse_key_map = {key: str(i) for i, key in enumerate(keys)}
                self._key_map_table[packet_index] = reverse_key_map
                self._write_key_map(packet_index, key_map)

        return packet_index

    def _write_target_declaration(self, target_name: str, id: Optional[str] = None):
        """Write a target declaration entry."""
        target_index = self._next_target_index
        self._target_indexes[target_name] = target_index
        self._next_target_index += 1

        if target_index > OPENC3_MAX_TARGET_INDEX:
            raise ValueError("Target Index Overflow")

        flags = OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK
        if id:
            flags |= OPENC3_ID_FLAG_MASK

        name_bytes = target_name.encode("utf-8")
        length = OPENC3_PRIMARY_FIXED_SIZE + OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE + len(name_bytes)
        if id:
            length += OPENC3_ID_FIXED_SIZE

        entry = struct.pack(">IH", length, flags) + name_bytes
        if id:
            entry += bytes.fromhex(id)

        self._file.write(entry)
        self._file_size += len(entry)

    def _write_packet_declaration(
        self, cmd_or_tlm: str, target_name: str, packet_name: str, id: Optional[str] = None
    ):
        """Write a packet declaration entry."""
        target_index = self._target_indexes[target_name]

        flags = OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK
        if cmd_or_tlm == "CMD":
            flags |= OPENC3_CMD_FLAG_MASK
        if id:
            flags |= OPENC3_ID_FLAG_MASK

        name_bytes = packet_name.encode("utf-8")
        length = OPENC3_PRIMARY_FIXED_SIZE + OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE + len(name_bytes)
        if id:
            length += OPENC3_ID_FIXED_SIZE

        entry = struct.pack(">IHH", length, flags, target_index) + name_bytes
        if id:
            entry += bytes.fromhex(id)

        self._file.write(entry)
        self._file_size += len(entry)

    def _write_key_map(self, packet_index: int, key_map: dict):
        """Write a key map entry."""
        flags = OPENC3_KEY_MAP_ENTRY_TYPE_MASK
        if self.data_format == self.CBOR:
            flags |= OPENC3_CBOR_FLAG_MASK
            map_bytes = cbor2.dumps(key_map)
        else:
            map_bytes = json.dumps(key_map).encode("utf-8")

        length = OPENC3_PRIMARY_FIXED_SIZE + OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE + len(map_bytes)

        entry = struct.pack(">IHH", length, flags, packet_index) + map_bytes
        self._file.write(entry)
        self._file_size += len(entry)

    def _write_offset_marker(self, data: str):
        """Write an offset marker entry."""
        flags = OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK
        data_bytes = data.encode("utf-8")
        length = OPENC3_PRIMARY_FIXED_SIZE + OPENC3_OFFSET_MARKER_SECONDARY_FIXED_SIZE + len(data_bytes)

        entry = struct.pack(">IH", length, flags) + data_bytes
        self._file.write(entry)
        self._file_size += len(entry)

    def _write_entry(
        self,
        entry_type: str,
        cmd_or_tlm: str,
        target_name: str,
        packet_name: str,
        time_nsec_since_epoch: int,
        stored: bool,
        data,
        id: Optional[str],
        received_time_nsec_since_epoch: Optional[int] = None,
        extra: Optional[dict] = None,
    ):
        """Write an entry to the log file."""
        if id and len(id) != 64:
            raise ValueError(f"Length of id must be 64, got {len(id)}")

        if entry_type == self.TARGET_DECLARATION:
            self._write_target_declaration(target_name, id)

        elif entry_type == self.PACKET_DECLARATION:
            self._write_packet_declaration(cmd_or_tlm, target_name, packet_name, id)

        elif entry_type == self.KEY_MAP:
            packet_index = self._get_packet_index(cmd_or_tlm, target_name, packet_name, entry_type, data)
            self._write_key_map(packet_index, data)

        elif entry_type == self.OFFSET_MARKER:
            self._write_offset_marker(data)

        elif entry_type in (self.RAW_PACKET, self.JSON_PACKET):
            target_name = target_name or "UNKNOWN"
            packet_name = packet_name or "UNKNOWN"

            packet_index = self._get_packet_index(cmd_or_tlm, target_name, packet_name, entry_type, data)

            flags = 0
            if entry_type == self.RAW_PACKET:
                flags |= OPENC3_RAW_PACKET_ENTRY_TYPE_MASK
                data_bytes = data if isinstance(data, bytes) else data.encode("utf-8")
            else:  # JSON_PACKET
                flags |= OPENC3_JSON_PACKET_ENTRY_TYPE_MASK

                # Compress using key map
                key_map = self._key_map_table.get(packet_index)
                if key_map:
                    parsed = data if isinstance(data, dict) else json.loads(data)
                    compressed = {}
                    for key, value in parsed.items():
                        compressed_key = key_map.get(key, key)
                        compressed[compressed_key] = value

                    if self.data_format == self.CBOR:
                        flags |= OPENC3_CBOR_FLAG_MASK
                        data_bytes = cbor2.dumps(compressed)
                    else:
                        data_bytes = json.dumps(compressed).encode("utf-8")
                else:
                    if self.data_format == self.CBOR:
                        flags |= OPENC3_CBOR_FLAG_MASK
                        parsed = data if isinstance(data, dict) else json.loads(data)
                        data_bytes = cbor2.dumps(parsed)
                    else:
                        data_bytes = data.encode("utf-8") if isinstance(data, str) else json.dumps(data).encode("utf-8")

            if cmd_or_tlm == "CMD":
                flags |= OPENC3_CMD_FLAG_MASK
            if stored:
                flags |= OPENC3_STORED_FLAG_MASK

            length = OPENC3_PRIMARY_FIXED_SIZE + OPENC3_PACKET_SECONDARY_FIXED_SIZE + len(data_bytes)

            if received_time_nsec_since_epoch is not None:
                flags |= OPENC3_RECEIVED_TIME_FLAG_MASK
                length += OPENC3_RECEIVED_TIME_FIXED_SIZE

            extra_encoded = None
            if extra:
                flags |= OPENC3_EXTRA_FLAG_MASK
                length += OPENC3_EXTRA_LENGTH_FIXED_SIZE
                if self.data_format == self.CBOR:
                    # Set CBOR flag if extra is CBOR-encoded (needed for RAW_PACKET)
                    flags |= OPENC3_CBOR_FLAG_MASK
                    extra_encoded = cbor2.dumps(extra)
                else:
                    extra_encoded = json.dumps(extra).encode("utf-8")
                length += len(extra_encoded)

            # Build entry
            entry = struct.pack(">IHHQ", length, flags, packet_index, time_nsec_since_epoch)
            if received_time_nsec_since_epoch is not None:
                entry += struct.pack(">Q", received_time_nsec_since_epoch)
            if extra_encoded:
                entry += struct.pack(">I", len(extra_encoded)) + extra_encoded
            entry += data_bytes

            self._file.write(entry)
            self._file_size += len(entry)

            # Track timestamps
            if self._first_time is None or time_nsec_since_epoch < self._first_time:
                self._first_time = time_nsec_since_epoch
            if self._last_time is None or time_nsec_since_epoch > self._last_time:
                self._last_time = time_nsec_since_epoch

        else:
            raise ValueError(f"Unknown entry_type: {entry_type}")
