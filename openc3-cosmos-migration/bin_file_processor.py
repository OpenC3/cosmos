# Copyright 2026 OpenC3, Inc.
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
Binary packet log file processor for migration.

This module provides utilities for processing COSMOS5 binary log files
for data migration purposes. It uses the PacketLogReader class for
parsing and provides additional helper functions for file management.
"""

import gzip
import os
import tempfile
from datetime import datetime
from typing import Iterator, Optional

from openc3.logs.packet_log_reader import PacketLogReader
from openc3.packets.json_packet import JsonPacket


class BinFileProcessor:
    """
    Processes COSMOS5 binary log files (decom logs) for migration.

    This is a thin wrapper around PacketLogReader that handles
    compressed files and provides iteration over JSON packets.
    """

    def __init__(self, logger=None):
        """
        Initialize the processor.

        Args:
            logger: Optional logger instance
        """
        self.logger = logger
        self._reader = PacketLogReader()

    def process_file(self, file_path: str) -> Iterator[JsonPacket]:
        """
        Process a bin file and yield JsonPacket objects.

        Args:
            file_path: Path to the .bin or .bin.gz file

        Yields:
            JsonPacket objects for each JSON_PACKET entry
        """
        # Handle gzip compressed files
        if file_path.endswith(".gz"):
            with gzip.open(file_path, "rb") as gz_file:
                with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as temp_file:
                    temp_file.write(gz_file.read())
                    temp_path = temp_file.name

            try:
                yield from self._process_file_internal(temp_path)
            finally:
                os.unlink(temp_path)
        else:
            yield from self._process_file_internal(file_path)

    def process_bytes(self, data: bytes, filename: Optional[str] = None) -> Iterator[JsonPacket]:
        """
        Process bin file data from bytes.

        Args:
            data: Raw bytes of the bin file (uncompressed)
            filename: Optional filename for error messages

        Yields:
            JsonPacket objects for each JSON_PACKET entry
        """
        # Write bytes to temp file and process
        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as temp_file:
            temp_file.write(data)
            temp_path = temp_file.name

        try:
            yield from self._process_file_internal(temp_path)
        finally:
            os.unlink(temp_path)

    def _process_file_internal(self, file_path: str) -> Iterator[JsonPacket]:
        """Process an uncompressed bin file using PacketLogReader."""
        for packet in self._reader.each(file_path, identify_and_define=False):
            # Only yield JSON packets (not raw packets)
            if isinstance(packet, JsonPacket):
                yield packet


def extract_timestamp_from_filename(filename: str) -> int:
    """
    Extract timestamp from a decom log filename.

    Filename pattern: {yyyymmddhhmmssmmmuuunnn}__{TARGET}__{PACKET}__rt__decom.bin.gz

    Args:
        filename: The filename to parse

    Returns:
        Timestamp as nanoseconds since epoch, or 0 if parsing fails
    """
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
    basename = os.path.basename(filename)
    parts = basename.split("__")
    if len(parts) >= 3:
        return parts[1], parts[2]
    return None, None
