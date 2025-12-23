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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Binary packet log file processor for COSMOS5 format.
Ported from openc3/lib/openc3/logs/packet_log_reader.rb
"""

import gzip
import json
import struct
import tempfile
from dataclasses import dataclass
from typing import Iterator, Optional
import cbor2


# COSMOS5 File Format Constants
OPENC3_FILE_HEADER = b"COSMOS5_"
OPENC3_HEADER_LENGTH = 8

# Entry type masks (from flags & 0xF000)
OPENC3_ENTRY_TYPE_MASK = 0xF000
OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK = 0x1000
OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK = 0x2000
OPENC3_RAW_PACKET_ENTRY_TYPE_MASK = 0x3000
OPENC3_JSON_PACKET_ENTRY_TYPE_MASK = 0x4000
OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK = 0x5000
OPENC3_KEY_MAP_ENTRY_TYPE_MASK = 0x6000

# Flag masks
OPENC3_CMD_FLAG_MASK = 0x0800
OPENC3_STORED_FLAG_MASK = 0x0400
OPENC3_ID_FLAG_MASK = 0x0200
OPENC3_CBOR_FLAG_MASK = 0x0100
OPENC3_EXTRA_FLAG_MASK = 0x0080
OPENC3_RECEIVED_TIME_FLAG_MASK = 0x0040

# Fixed sizes
OPENC3_PRIMARY_FIXED_SIZE = 2
OPENC3_ID_FIXED_SIZE = 32
OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE = 2
OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE = 0
OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE = 2
OPENC3_RECEIVED_TIME_FIXED_SIZE = 8
OPENC3_EXTRA_LENGTH_FIXED_SIZE = 4


@dataclass
class JsonPacket:
    """Represents a decommutated JSON packet from a bin file."""

    cmd_or_tlm: str  # "CMD" or "TLM"
    target_name: str
    packet_name: str
    time_nsec: int  # Nanoseconds since epoch
    received_time_nsec: int  # Nanoseconds since epoch
    stored: bool
    json_data: dict
    key_map: Optional[dict] = None
    extra: Optional[dict] = None


class BinFileProcessor:
    """
    Processes COSMOS5 binary log files (decom logs).

    Parses the binary format and yields JsonPacket objects for each
    JSON_PACKET entry in the file.
    """

    def __init__(self, logger=None):
        """
        Initialize the processor.

        Args:
            logger: Optional logger instance
        """
        self.logger = logger
        self._reset()

    def _reset(self):
        """Reset internal state."""
        self.target_names = []
        self.target_ids = []
        self.packets = []  # List of (cmd_or_tlm, target_name, packet_name, id, key_map)
        self.packet_ids = []
        self.redis_offset = None
        self.last_offsets = {}

    def process_file(self, file_path: str) -> Iterator[JsonPacket]:
        """
        Process a bin file and yield JsonPacket objects.

        Args:
            file_path: Path to the .bin or .bin.gz file

        Yields:
            JsonPacket objects for each JSON_PACKET entry
        """
        self._reset()

        # Handle gzip compressed files
        if file_path.endswith(".gz"):
            # Download and decompress to temp file for processing
            with gzip.open(file_path, "rb") as gz_file:
                with tempfile.NamedTemporaryFile(delete=False) as temp_file:
                    temp_file.write(gz_file.read())
                    temp_path = temp_file.name

            try:
                yield from self._process_file_internal(temp_path)
            finally:
                import os

                os.unlink(temp_path)
        else:
            yield from self._process_file_internal(file_path)

    def process_bytes(self, data: bytes) -> Iterator[JsonPacket]:
        """
        Process bin file data from bytes.

        Args:
            data: Raw bytes of the bin file (uncompressed)

        Yields:
            JsonPacket objects for each JSON_PACKET entry
        """
        self._reset()

        # Verify header
        if len(data) < OPENC3_HEADER_LENGTH:
            raise ValueError("File too short to contain header")

        header = data[:OPENC3_HEADER_LENGTH]
        if header != OPENC3_FILE_HEADER:
            raise ValueError(f"Invalid file header: {header}, expected {OPENC3_FILE_HEADER}")

        offset = OPENC3_HEADER_LENGTH

        while offset < len(data):
            # Read entry length (4 bytes, big-endian)
            if offset + 4 > len(data):
                break

            length = struct.unpack(">I", data[offset : offset + 4])[0]
            offset += 4

            if offset + length > len(data):
                break

            entry = data[offset : offset + length]
            offset += length

            # Parse entry
            packet = self._parse_entry(entry)
            if packet is not None:
                yield packet

    def _process_file_internal(self, file_path: str) -> Iterator[JsonPacket]:
        """Process an uncompressed bin file."""
        with open(file_path, "rb") as f:
            # Verify header
            header = f.read(OPENC3_HEADER_LENGTH)
            if header != OPENC3_FILE_HEADER:
                raise ValueError(f"Invalid file header: {header}, expected {OPENC3_FILE_HEADER}")

            while True:
                # Read entry length (4 bytes, big-endian)
                length_bytes = f.read(4)
                if not length_bytes or len(length_bytes) < 4:
                    break

                length = struct.unpack(">I", length_bytes)[0]

                # Read entry data
                entry = f.read(length)
                if len(entry) < length:
                    break

                # Parse entry
                packet = self._parse_entry(entry)
                if packet is not None:
                    yield packet

    def _parse_entry(self, entry: bytes) -> Optional[JsonPacket]:
        """
        Parse a single entry from the bin file.

        Returns JsonPacket for JSON_PACKET entries, None for others
        (which are processed internally for metadata).
        """
        if len(entry) < 2:
            return None

        # Parse flags (2 bytes, big-endian)
        flags = struct.unpack(">H", entry[0:2])[0]

        cmd_or_tlm = "CMD" if flags & OPENC3_CMD_FLAG_MASK else "TLM"
        stored = bool(flags & OPENC3_STORED_FLAG_MASK)
        has_id = bool(flags & OPENC3_ID_FLAG_MASK)
        is_cbor = bool(flags & OPENC3_CBOR_FLAG_MASK)
        has_extra = bool(flags & OPENC3_EXTRA_FLAG_MASK)
        has_received_time = bool(flags & OPENC3_RECEIVED_TIME_FLAG_MASK)

        entry_type = flags & OPENC3_ENTRY_TYPE_MASK

        if entry_type == OPENC3_JSON_PACKET_ENTRY_TYPE_MASK:
            return self._parse_json_packet(entry, cmd_or_tlm, stored, is_cbor, has_received_time, has_extra)
        elif entry_type == OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK:
            self._parse_target_declaration(entry, has_id)
        elif entry_type == OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK:
            self._parse_packet_declaration(entry, cmd_or_tlm, has_id)
        elif entry_type == OPENC3_KEY_MAP_ENTRY_TYPE_MASK:
            self._parse_key_map(entry, is_cbor)
        elif entry_type == OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK:
            self._parse_offset_marker(entry)
        elif entry_type == OPENC3_RAW_PACKET_ENTRY_TYPE_MASK:
            # Raw packets are not processed for decom logs
            pass

        return None

    def _parse_json_packet(
        self, entry: bytes, cmd_or_tlm: str, stored: bool, is_cbor: bool, has_received_time: bool, has_extra: bool
    ) -> Optional[JsonPacket]:
        """Parse a JSON_PACKET entry."""
        if len(entry) < 12:
            return None

        # Parse packet_index (2 bytes) and timestamp (8 bytes)
        packet_index, time_nsec = struct.unpack(">HQ", entry[2:12])

        if packet_index >= len(self.packets):
            if self.logger:
                self.logger.warn(f"Invalid packet_index {packet_index}, only {len(self.packets)} packets declared")
            return None

        packet_info = self.packets[packet_index]
        lookup_cmd_or_tlm, target_name, packet_name, _, key_map = packet_info

        if cmd_or_tlm != lookup_cmd_or_tlm:
            if self.logger:
                self.logger.warn(f"Packet type mismatch: {cmd_or_tlm} vs {lookup_cmd_or_tlm}")

        # Handle optional fields
        next_offset = 12
        received_time_nsec = time_nsec

        if has_received_time:
            if len(entry) >= next_offset + OPENC3_RECEIVED_TIME_FIXED_SIZE:
                received_time_nsec = struct.unpack(">Q", entry[next_offset : next_offset + 8])[0]
                next_offset += OPENC3_RECEIVED_TIME_FIXED_SIZE

        extra = None
        if has_extra:
            if len(entry) >= next_offset + OPENC3_EXTRA_LENGTH_FIXED_SIZE:
                extra_length = struct.unpack(">I", entry[next_offset : next_offset + 4])[0]
                next_offset += OPENC3_EXTRA_LENGTH_FIXED_SIZE
                if len(entry) >= next_offset + extra_length:
                    extra_data = entry[next_offset : next_offset + extra_length]
                    next_offset += extra_length
                    try:
                        if is_cbor:
                            extra = cbor2.loads(extra_data)
                        else:
                            extra = json.loads(extra_data)
                    except Exception:
                        pass

        # Parse JSON data
        json_bytes = entry[next_offset:]
        try:
            if is_cbor:
                json_data = cbor2.loads(json_bytes)
            else:
                json_data = json.loads(json_bytes)
        except Exception as e:
            if self.logger:
                self.logger.warn(f"Failed to parse JSON data: {e}")
            return None

        # Apply key map if present (CBOR compression uses short keys)
        if key_map and isinstance(json_data, dict):
            json_data = {key_map.get(k, k): v for k, v in json_data.items()}

        return JsonPacket(
            cmd_or_tlm=cmd_or_tlm,
            target_name=target_name,
            packet_name=packet_name,
            time_nsec=time_nsec,
            received_time_nsec=received_time_nsec,
            stored=stored,
            json_data=json_data,
            key_map=key_map,
            extra=extra,
        )

    def _parse_target_declaration(self, entry: bytes, has_id: bool):
        """Parse a TARGET_DECLARATION entry."""
        length = len(entry)
        target_name_length = length - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE
        if has_id:
            target_name_length -= OPENC3_ID_FIXED_SIZE

        target_name = entry[2 : 2 + target_name_length].decode("utf-8")

        if has_id:
            target_id = entry[2 + target_name_length : 2 + target_name_length + OPENC3_ID_FIXED_SIZE]
            self.target_ids.append(target_id)

        self.target_names.append(target_name)

    def _parse_packet_declaration(self, entry: bytes, cmd_or_tlm: str, has_id: bool):
        """Parse a PACKET_DECLARATION entry."""
        if len(entry) < 4:
            return

        target_index = struct.unpack(">H", entry[2:4])[0]

        if target_index < len(self.target_names):
            target_name = self.target_names[target_index]
        else:
            target_name = "UNKNOWN"

        length = len(entry)
        packet_name_length = length - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE
        if has_id:
            packet_name_length -= OPENC3_ID_FIXED_SIZE

        packet_name = entry[4 : 4 + packet_name_length].decode("utf-8")

        packet_id = None
        if has_id:
            packet_id = entry[4 + packet_name_length :]
            self.packet_ids.append(packet_id)

        # Initialize with None for key_map, will be set later if KEY_MAP entry exists
        self.packets.append([cmd_or_tlm, target_name, packet_name, packet_id, None])

    def _parse_key_map(self, entry: bytes, is_cbor: bool):
        """Parse a KEY_MAP entry."""
        if len(entry) < 4:
            return

        packet_index = struct.unpack(">H", entry[2:4])[0]
        key_map_length = len(entry) - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE

        key_map_bytes = entry[4 : 4 + key_map_length]
        try:
            if is_cbor:
                key_map = cbor2.loads(key_map_bytes)
            else:
                key_map = json.loads(key_map_bytes)

            if packet_index < len(self.packets):
                self.packets[packet_index][4] = key_map
        except Exception:
            pass

    def _parse_offset_marker(self, entry: bytes):
        """Parse an OFFSET_MARKER entry."""
        data = entry[2:].decode("utf-8")
        parts = data.split(",")
        redis_offset = parts[0]
        if len(parts) > 1:
            redis_topic = parts[1]
            self.last_offsets[redis_topic] = redis_offset
        else:
            self.redis_offset = redis_offset


def extract_timestamp_from_filename(filename: str) -> int:
    """
    Extract timestamp from a decom log filename.

    Filename pattern: {yyyymmddhhmmssmmmuuunnn}__{TARGET}__{PACKET}__rt__decom.bin.gz

    Args:
        filename: The filename to parse

    Returns:
        Timestamp as nanoseconds since epoch, or 0 if parsing fails
    """
    import os
    from datetime import datetime

    basename = os.path.basename(filename)
    parts = basename.split("__")
    if len(parts) < 1:
        return 0

    timestamp_str = parts[0]
    if len(timestamp_str) < 17:
        return 0

    try:
        # Parse: yyyymmddhhmmssmmm (17 chars) + uuu (3 chars) + nnn (3 chars)
        year = int(timestamp_str[0:4])
        month = int(timestamp_str[4:6])
        day = int(timestamp_str[6:8])
        hour = int(timestamp_str[8:10])
        minute = int(timestamp_str[10:12])
        second = int(timestamp_str[12:14])
        millisecond = int(timestamp_str[14:17])

        dt = datetime(year, month, day, hour, minute, second, millisecond * 1000)
        # Convert to nanoseconds
        return int(dt.timestamp() * 1_000_000_000)
    except (ValueError, IndexError):
        return 0


def parse_target_packet_from_filename(filename: str) -> tuple:
    """
    Extract target and packet names from a decom log filename.

    Filename pattern: {timestamp}__{TARGET}__{PACKET}__rt__decom.bin.gz

    Args:
        filename: The filename to parse

    Returns:
        Tuple of (target_name, packet_name) or (None, None) if parsing fails
    """
    import os

    basename = os.path.basename(filename)
    parts = basename.split("__")
    if len(parts) >= 3:
        return parts[1], parts[2]
    return None, None
