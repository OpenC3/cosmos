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
JsonPacket represents a packet that was stored as JSON in a packet log file.

This is used when reading decommutated (JSON) packet logs, where the packet
data has already been processed and stored as key-value pairs rather than
raw binary data.
"""

import json
from datetime import datetime, timezone
from typing import Any


class JsonPacket:
    """
    Represents a JSON packet read from a packet log file.

    Attributes:
        cmd_or_tlm: "CMD" or "TLM" indicating command or telemetry
        target_name: Name of the target
        packet_name: Name of the packet
        packet_time: Packet timestamp as datetime
        stored: Whether packet was stored (vs real-time)
        json_hash: Dictionary of item names to values
        received_time: Time packet was received as datetime
        extra: Optional extra metadata dictionary
    """

    def __init__(
        self,
        cmd_or_tlm: str,
        target_name: str,
        packet_name: str,
        time_nsec_since_epoch: int,
        stored: bool,
        json_data,
        key_map: dict | None = None,
        received_time_nsec_since_epoch: int | None = None,
        extra: dict | None = None,
    ):
        """
        Initialize a JsonPacket.

        Args:
            cmd_or_tlm: "CMD" or "TLM"
            target_name: Target name
            packet_name: Packet name
            time_nsec_since_epoch: Packet timestamp in nanoseconds since epoch
            stored: Whether packet was stored (vs real-time)
            json_data: Either a dict or JSON string of packet data
            key_map: Optional key mapping for CBOR compressed keys
            received_time_nsec_since_epoch: Received timestamp in nanoseconds
            extra: Optional extra metadata
        """
        self.cmd_or_tlm = cmd_or_tlm.upper() if isinstance(cmd_or_tlm, str) else cmd_or_tlm
        self.target_name = target_name
        self.packet_name = packet_name
        self._time_nsec = time_nsec_since_epoch
        self.packet_time = self._nsec_to_datetime(time_nsec_since_epoch)
        self.stored = bool(stored)

        if received_time_nsec_since_epoch is not None:
            self._received_time_nsec = received_time_nsec_since_epoch
            self.received_time = self._nsec_to_datetime(received_time_nsec_since_epoch)
        else:
            self._received_time_nsec = time_nsec_since_epoch
            self.received_time = self.packet_time

        self.extra = extra

        # Parse JSON if string, otherwise use dict directly
        if isinstance(json_data, str):
            self.json_hash = json.loads(json_data)
        else:
            self.json_hash = json_data

        # Apply key map if present (CBOR uses compressed short keys)
        if key_map and isinstance(self.json_hash, dict):
            uncompressed = {}
            for key, value in self.json_hash.items():
                uncompressed_key = key_map.get(key, key)
                uncompressed[uncompressed_key] = value
            self.json_hash = uncompressed

    @staticmethod
    def _nsec_to_datetime(nsec: int) -> datetime:
        """Convert nanoseconds since epoch to datetime."""
        seconds = nsec / 1_000_000_000
        return datetime.fromtimestamp(seconds, tz=timezone.utc)

    def read(self, name: str, value_type: str = "CONVERTED", reduced_type: str | None = None) -> Any:
        """
        Read an item value from the packet.

        Args:
            name: Item name (should be uppercase)
            value_type: One of "RAW", "CONVERTED", "FORMATTED"
            reduced_type: Optional reduced data type: "AVG", "STDDEV", "MIN", "MAX"

        Returns:
            The item value, or None if not found
        """
        value = None
        array_index = None

        # Check for array index notation like "ITEM[0]"
        if name.endswith("]") and name not in self.json_hash:
            bracket_idx = name.find("[")
            if bracket_idx != -1:
                array_index = int(name[bracket_idx + 1 : -1])
                name = name[:bracket_idx]

        # Handle reduced types
        if reduced_type:
            if value_type in ("FORMATTED", "WITH_UNITS"):
                raise ValueError(f"Reduced types only support RAW or CONVERTED value types: {value_type} unsupported")

            if value_type == "CONVERTED":
                suffix_map = {"AVG": "__CA", "STDDEV": "__CS", "MIN": "__CN", "MAX": "__CX"}
                suffix = suffix_map.get(reduced_type)
                if suffix:
                    value = self.json_hash.get(f"{name}{suffix}")
                    if value is not None:
                        if array_index is not None:
                            value = value[array_index]
                        return value

            # Fall back to raw reduced values
            suffix_map = {"AVG": "__A", "STDDEV": "__S", "MIN": "__N", "MAX": "__X"}
            suffix = suffix_map.get(reduced_type)
            if suffix:
                value = self.json_hash.get(f"{name}{suffix}")
                if value is not None:
                    if array_index is not None:
                        value = value[array_index]
                    return value

        # Handle FORMATTED and WITH_UNITS
        if value_type in ("WITH_UNITS", "FORMATTED"):
            # Try formatted value first
            value = self.json_hash.get(f"{name}__F")
            if value is not None:
                if array_index is not None:
                    value = value[array_index]
                return value

            # Try converted value
            value = self.json_hash.get(f"{name}__C")
            if value is not None:
                if array_index is not None:
                    value = value[array_index]
                return str(value)

            # Try raw value
            value = self.json_hash.get(name)
            if value is not None:
                if array_index is not None:
                    value = value[array_index]
                return str(value)

            return None

        # Handle CONVERTED
        if value_type == "CONVERTED":
            value = self.json_hash.get(f"{name}__C")
            if value is not None:
                if array_index is not None:
                    value = value[array_index]
                return value

        # RAW or fallback
        value = self.json_hash.get(name)
        if value is not None:
            if array_index is not None:
                value = value[array_index]
            return value

        return None

    def read_with_limits_state(self, name: str, value_type: str = "CONVERTED", reduced_type: str | None = None):
        """
        Read an item value along with its limits state.

        Args:
            name: Item name
            value_type: Value type
            reduced_type: Optional reduced type

        Returns:
            Tuple of (value, limits_state) where limits_state may be None
        """
        value = self.read(name, value_type, reduced_type)
        limits_state = self.json_hash.get(f"{name}__L")
        return (value, limits_state)

    def read_all(
        self, value_type: str = "CONVERTED", reduced_type: str | None = None, names: list | None = None
    ) -> dict:
        """
        Read all items in the packet.

        Args:
            value_type: Value type for all items
            reduced_type: Optional reduced type
            names: Optional list of names to read (defaults to all)

        Returns:
            Dictionary of name -> value
        """
        if names is None:
            names = self.read_all_names()
        return {name: self.read(name, value_type, reduced_type) for name in names}

    def read_all_with_limits_states(
        self, value_type: str = "CONVERTED", reduced_type: str | None = None, names: list | None = None
    ) -> dict:
        """
        Read all items with their limits states.

        Args:
            value_type: Value type for all items
            reduced_type: Optional reduced type
            names: Optional list of names to read (defaults to all)

        Returns:
            Dictionary of name -> (value, limits_state)
        """
        if names is None:
            names = self.read_all_names()
        return {name: self.read_with_limits_state(name, value_type, reduced_type) for name in names}

    def read_all_names(self, value_type: str | None = None, reduced_type: str | None = None) -> list:
        """
        Get all item names in the packet.

        Args:
            value_type: Optional filter by value type
            reduced_type: Optional filter by reduced type

        Returns:
            List of item names
        """
        result = {}

        if value_type:
            # Build expected postfix based on value_type and reduced_type
            postfix_map = {"RAW": "", "CONVERTED": "C", "FORMATTED": "F"}
            postfix = postfix_map.get(value_type, "")

            reduced_suffix_map = {"MIN": "N", "MAX": "X", "AVG": "A", "STDDEV": "S"}
            if reduced_type:
                postfix += reduced_suffix_map.get(reduced_type, "")
            elif value_type == "RAW":
                postfix = None  # RAW with no reduced type has no suffix

            for key in self.json_hash:
                key_split = key.split("__")
                if postfix is None:
                    # RAW with no reduced: only include keys without suffix
                    if len(key_split) == 1:
                        result[key_split[0]] = True
                elif len(key_split) > 1 and key_split[1] == postfix:
                    result[key_split[0]] = True
        else:
            # Return all base names
            for key in self.json_hash:
                base_name = key.split("__")[0]
                result[base_name] = True

        return list(result.keys())

    def formatted(
        self,
        value_type: str = "CONVERTED",
        reduced_type: str | None = None,
        names: list | None = None,
        indent: int = 0,
    ) -> str:
        """
        Create a formatted string showing all item names and values.

        Args:
            value_type: Value type for all items
            reduced_type: Optional reduced type
            names: Optional list of names to include
            indent: Number of spaces to indent

        Returns:
            Formatted string representation
        """
        if names is None:
            names = self.read_all_names()

        indent_str = " " * indent
        lines = []
        for name in names:
            value = self.read(name, value_type, reduced_type)
            lines.append(f"{indent_str}{name}: {value}")

        return "\n".join(lines)

    @property
    def time_nsec(self) -> int:
        """Return packet time as nanoseconds since epoch."""
        return self._time_nsec

    @property
    def received_time_nsec(self) -> int:
        """Return received time as nanoseconds since epoch."""
        return self._received_time_nsec
