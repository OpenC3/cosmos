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
Packet log reader for COSMOS5 binary log files.

Reads packet logs containing either commands or telemetry in raw or JSON format.
This is a port of the Ruby PacketLogReader class.
"""

import json
import struct
from collections.abc import Iterator
from datetime import datetime, timezone

import cbor2

from openc3.logs.packet_log_constants import (
    COSMOS2_FILE_HEADER,
    COSMOS4_FILE_HEADER,
    OPENC3_CBOR_FLAG_MASK,
    OPENC3_CMD_FLAG_MASK,
    OPENC3_ENTRY_TYPE_MASK,
    OPENC3_EXTRA_FLAG_MASK,
    OPENC3_EXTRA_LENGTH_FIXED_SIZE,
    OPENC3_FILE_HEADER,
    OPENC3_HEADER_LENGTH,
    OPENC3_ID_FIXED_SIZE,
    OPENC3_ID_FLAG_MASK,
    OPENC3_JSON_PACKET_ENTRY_TYPE_MASK,
    OPENC3_KEY_MAP_ENTRY_TYPE_MASK,
    OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE,
    OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK,
    OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK,
    OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE,
    OPENC3_PRIMARY_FIXED_SIZE,
    OPENC3_RAW_PACKET_ENTRY_TYPE_MASK,
    OPENC3_RECEIVED_TIME_FIXED_SIZE,
    OPENC3_RECEIVED_TIME_FLAG_MASK,
    OPENC3_STORED_FLAG_MASK,
    OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK,
    OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE,
)
from openc3.packets.json_packet import JsonPacket
from openc3.packets.packet import Packet


class PacketLogReader:
    """
    Reads a packet log of either commands or telemetry.

    Supports both raw packet data and JSON (decommutated) packet data.
    """

    MAX_READ_SIZE = 1_000_000_000

    def __init__(self):
        """Create a new log file reader."""
        self._reset()

    def _reset(self):
        """Reset internal state for a new file."""
        self._file = None
        self._filename = None
        self._max_read_size = self.MAX_READ_SIZE
        self._target_names = []
        self._target_ids = []
        self._packets = []  # List of [cmd_or_tlm, target_name, packet_name, id, key_map]
        self._packet_ids = []
        self._redis_offset = None
        self._last_offsets = {}

    @property
    def redis_offset(self) -> str | None:
        """The Redis offset from the log file."""
        return self._redis_offset

    @property
    def last_offsets(self) -> dict:
        """Dictionary of topic -> offset from the log file."""
        return self._last_offsets

    @property
    def filename(self) -> str | None:
        """The currently open filename."""
        return self._filename

    def each(
        self,
        filename: str,
        identify_and_define: bool = True,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
    ) -> Iterator[Packet | JsonPacket]:
        """
        Iterate over each packet in the log file.

        Args:
            filename: The log file to read
            identify_and_define: Whether to identify and define raw packets
            start_time: Optional start time filter (packets before are skipped)
            end_time: Optional end time filter (packets after cause iteration to stop)

        Yields:
            Packet or JsonPacket objects

        Returns:
            True if end_time was reached, False otherwise (via StopIteration value)
        """
        reached_end_time = False
        try:
            self.open(filename)

            while True:
                packet = self.read(identify_and_define)
                if packet is None:
                    break

                time = packet.packet_time
                if time:
                    if start_time and time < start_time:
                        continue
                    if end_time and time > end_time:
                        reached_end_time = True
                        break

                yield packet

        finally:
            self.close()

        return reached_end_time

    def open(self, filename: str):
        """
        Open a log file for reading.

        Args:
            filename: Path to the log file

        Raises:
            ValueError: If the file header is invalid
            IOError: If the file cannot be read
        """
        self.close()
        self._reset()
        self._filename = filename
        self._file = open(filename, "rb")  # noqa: SIM115

        file_size = self._file.seek(0, 2)  # Seek to end to get size
        self._file.seek(0)  # Seek back to start

        self._max_read_size = min(file_size, self.MAX_READ_SIZE)
        self._read_file_header()

    def close(self):
        """Close the current log file."""
        if self._file and not self._file.closed:
            self._file.close()
        self._file = None

    def read(self, identify_and_define: bool = True) -> Packet | JsonPacket | None:
        """
        Read a packet from the log file.

        Args:
            identify_and_define: Whether to identify and define raw packets
                using the System definitions

        Returns:
            Packet or JsonPacket, or None if end of file
        """
        # Read entry length (4 bytes, big-endian)
        length_bytes = self._file.read(4)
        if not length_bytes or len(length_bytes) < 4:
            return None

        length = struct.unpack(">I", length_bytes)[0]
        entry = self._file.read(length)
        if len(entry) < length:
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
            return self._read_json_packet(entry, cmd_or_tlm, stored, is_cbor, has_received_time, has_extra)

        elif entry_type == OPENC3_RAW_PACKET_ENTRY_TYPE_MASK:
            return self._read_raw_packet(
                entry, cmd_or_tlm, stored, is_cbor, has_received_time, has_extra, identify_and_define
            )

        elif entry_type == OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK:
            self._read_target_declaration(entry, length, has_id)
            return self.read(identify_and_define)

        elif entry_type == OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK:
            self._read_packet_declaration(entry, length, cmd_or_tlm, has_id)
            return self.read(identify_and_define)

        elif entry_type == OPENC3_KEY_MAP_ENTRY_TYPE_MASK:
            self._read_key_map(entry, length, is_cbor)
            return self.read(identify_and_define)

        elif entry_type == OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK:
            self._read_offset_marker(entry)
            return self.read(identify_and_define)

        else:
            raise ValueError(f"Invalid Entry Flags: {flags:#06x}")

    @property
    def size(self) -> int:
        """The size of the log file being processed."""
        if self._file:
            pos = self._file.tell()
            self._file.seek(0, 2)
            size = self._file.tell()
            self._file.seek(pos)
            return size
        return 0

    @property
    def bytes_read(self) -> int:
        """The current file position in the log file."""
        if self._file:
            return self._file.tell()
        return 0

    def _read_file_header(self):
        """Read and validate the file header."""
        header = self._file.read(OPENC3_HEADER_LENGTH)

        if not header or len(header) < OPENC3_HEADER_LENGTH:
            raise ValueError(f"Failed to read at least {OPENC3_HEADER_LENGTH} bytes from packet log")

        if header == OPENC3_FILE_HEADER:
            # Found OpenC3 5 File Header - valid
            pass
        elif header == COSMOS4_FILE_HEADER:
            raise ValueError("COSMOS 4 log file must be converted to OpenC3 5")
        elif header == COSMOS2_FILE_HEADER:
            raise ValueError("COSMOS 2 log file must be converted to OpenC3 5")
        else:
            raise ValueError("OpenC3 file header not found")

    def _handle_received_time_extra_and_data(
        self, entry: bytes, time_nsec: int, has_received_time: bool, has_extra: bool, is_cbor: bool
    ):
        """
        Handle optional received_time and extra fields, then return the data portion.

        Args:
            entry: The full entry bytes
            time_nsec: The packet timestamp in nanoseconds
            has_received_time: Whether entry includes received_time
            has_extra: Whether entry includes extra data
            is_cbor: Whether data is CBOR encoded

        Returns:
            Tuple of (received_time_nsec, extra, data_bytes)
        """
        next_offset = 12  # After flags (2) + packet_index (2) + timestamp (8)
        received_time_nsec = time_nsec

        if has_received_time:
            received_time_nsec = struct.unpack(">Q", entry[next_offset : next_offset + 8])[0]
            next_offset += OPENC3_RECEIVED_TIME_FIXED_SIZE

        extra = None
        if has_extra:
            extra_length = struct.unpack(">I", entry[next_offset : next_offset + 4])[0]
            next_offset += OPENC3_EXTRA_LENGTH_FIXED_SIZE
            extra_encoded = entry[next_offset : next_offset + extra_length]
            next_offset += extra_length

            if is_cbor:
                extra = cbor2.loads(extra_encoded)
            else:
                extra = json.loads(extra_encoded)

        data = entry[next_offset:]
        return received_time_nsec, extra, data

    def _read_json_packet(
        self, entry: bytes, cmd_or_tlm: str, stored: bool, is_cbor: bool, has_received_time: bool, has_extra: bool
    ) -> JsonPacket:
        """Read a JSON packet entry."""
        # Parse packet_index (2 bytes) and timestamp (8 bytes)
        packet_index, time_nsec = struct.unpack(">HQ", entry[2:12])

        received_time_nsec, extra, json_data = self._handle_received_time_extra_and_data(
            entry, time_nsec, has_received_time, has_extra, is_cbor
        )

        if packet_index >= len(self._packets):
            raise ValueError(f"Invalid packet_index {packet_index}, only {len(self._packets)} packets declared")

        packet_info = self._packets[packet_index]
        lookup_cmd_or_tlm, target_name, packet_name, _id = packet_info[:4]
        key_map = packet_info[4] if len(packet_info) > 4 else None

        if cmd_or_tlm != lookup_cmd_or_tlm:
            raise ValueError(f"Packet type mismatch, packet:{cmd_or_tlm}, lookup:{lookup_cmd_or_tlm}")

        if is_cbor:
            json_hash = cbor2.loads(json_data)
        else:
            # Decode bytes to string for JsonPacket to parse
            json_hash = json_data.decode("utf-8") if isinstance(json_data, bytes) else json_data

        return JsonPacket(
            cmd_or_tlm,
            target_name,
            packet_name,
            time_nsec,
            stored,
            json_hash,
            key_map,
            received_time_nsec_since_epoch=received_time_nsec,
            extra=extra,
        )

    def _read_raw_packet(
        self,
        entry: bytes,
        cmd_or_tlm: str,
        stored: bool,
        is_cbor: bool,
        has_received_time: bool,
        has_extra: bool,
        identify_and_define: bool,
    ) -> Packet:
        """Read a raw packet entry."""
        # Parse packet_index (2 bytes) and timestamp (8 bytes)
        packet_index, time_nsec = struct.unpack(">HQ", entry[2:12])

        received_time_nsec, extra, packet_data = self._handle_received_time_extra_and_data(
            entry, time_nsec, has_received_time, has_extra, is_cbor
        )

        if packet_index >= len(self._packets):
            raise ValueError(f"Invalid packet_index {packet_index}, only {len(self._packets)} packets declared")

        packet_info = self._packets[packet_index]
        lookup_cmd_or_tlm, target_name, packet_name, _id = packet_info[:4]

        if cmd_or_tlm != lookup_cmd_or_tlm:
            raise ValueError(f"Packet type mismatch, packet:{cmd_or_tlm}, lookup:{lookup_cmd_or_tlm}")

        if identify_and_define:
            packet = self._identify_and_define_packet_data(cmd_or_tlm, target_name, packet_name, packet_data)
        else:
            packet = Packet(target_name, packet_name, "BIG_ENDIAN", None, packet_data)

        packet.packet_time = self._nsec_to_datetime(time_nsec)
        packet.received_time = self._nsec_to_datetime(received_time_nsec)
        packet.cmd_or_tlm = cmd_or_tlm
        packet.stored = stored
        packet.extra = extra
        # Store original nanosecond timestamps for high-precision access
        packet._time_nsec = time_nsec
        packet._received_time_nsec = received_time_nsec
        packet.received_count += 1

        return packet

    def _read_target_declaration(self, entry: bytes, length: int, has_id: bool):
        """Read a target declaration entry."""
        target_name_length = length - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE
        if has_id:
            target_name_length -= OPENC3_ID_FIXED_SIZE

        target_name = entry[2 : 2 + target_name_length].decode("utf-8")

        if has_id:
            target_id = entry[2 + target_name_length : 2 + target_name_length + OPENC3_ID_FIXED_SIZE]
            self._target_ids.append(target_id)

        self._target_names.append(target_name)

    def _read_packet_declaration(self, entry: bytes, length: int, cmd_or_tlm: str, has_id: bool):
        """Read a packet declaration entry."""
        target_index = struct.unpack(">H", entry[2:4])[0]

        if target_index < len(self._target_names):
            target_name = self._target_names[target_index]
        else:
            # Workaround for bug in PacketLogWriter before version 5.6.0
            # Try to extract target name from filename
            if self._filename:
                filename_parts = self._filename.split("__")
                target_name = filename_parts[3] if len(filename_parts) > 3 else "UNKNOWN"
            else:
                target_name = "UNKNOWN"

        packet_name_length = length - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE
        if has_id:
            packet_name_length -= OPENC3_ID_FIXED_SIZE

        packet_name = entry[4 : 4 + packet_name_length].decode("utf-8")

        packet_id = None
        if has_id:
            packet_id = entry[4 + packet_name_length :]
            self._packet_ids.append(packet_id)

        # Store packet info (key_map will be appended later if KEY_MAP entry follows)
        self._packets.append([cmd_or_tlm, target_name, packet_name, packet_id])

    def _read_key_map(self, entry: bytes, length: int, is_cbor: bool):
        """Read a key map entry for CBOR compressed packets."""
        packet_index = struct.unpack(">H", entry[2:4])[0]
        key_map_length = length - OPENC3_PRIMARY_FIXED_SIZE - OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE

        key_map_bytes = entry[4 : 4 + key_map_length]

        if is_cbor:
            key_map = cbor2.loads(key_map_bytes)
        else:
            key_map = json.loads(key_map_bytes)

        if packet_index < len(self._packets):
            # Append key_map to existing packet entry
            if len(self._packets[packet_index]) == 4:
                self._packets[packet_index].append(key_map)
            else:
                self._packets[packet_index][4] = key_map

    def _read_offset_marker(self, entry: bytes):
        """Read an offset marker entry."""
        data = entry[2:].decode("utf-8")
        parts = data.split(",")
        redis_offset = parts[0]

        if len(parts) > 1:
            redis_topic = parts[1]
            self._last_offsets[redis_topic] = redis_offset
        else:
            self._redis_offset = redis_offset

    def _identify_and_define_packet_data(
        self, cmd_or_tlm: str, target_name: str, packet_name: str, packet_data: bytes
    ) -> Packet:
        """
        Identify and define a packet using System definitions.

        This is best effort - may return unidentified/undefined packets.
        """
        packet = None

        if target_name and packet_name:
            try:
                from openc3.system.system import System

                if cmd_or_tlm == "CMD":
                    packet = System.commands.packet(target_name, packet_name)
                else:
                    packet = System.telemetry.packet(target_name, packet_name)
                packet.buffer = packet_data
            except Exception:
                # Could not find a definition for this packet
                from openc3.utilities.logger import Logger

                Logger.error(f"Unknown packet {target_name} {packet_name}")
                packet = Packet(target_name, packet_name, "BIG_ENDIAN", None, packet_data)
        else:
            try:
                from openc3.system.system import System

                if cmd_or_tlm == "CMD":
                    packet = System.commands.identify(packet_data)
                else:
                    packet = System.telemetry.identify(packet_data)
            except Exception:
                packet = Packet(target_name, packet_name, "BIG_ENDIAN", None, packet_data)

        if packet is None:
            packet = Packet(target_name, packet_name, "BIG_ENDIAN", None, packet_data)

        return packet

    @staticmethod
    def _nsec_to_datetime(nsec: int) -> datetime:
        """Convert nanoseconds since epoch to datetime."""
        seconds = nsec / 1_000_000_000
        return datetime.fromtimestamp(seconds, tz=timezone.utc)
