# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Packet log format constants for COSMOS5 binary log files.

These constants define the binary structure of packet log files used for
storing commands and telemetry data.
"""

# Constants to detect old file formats
COSMOS2_FILE_HEADER = b"COSMOS2_"
COSMOS4_FILE_HEADER = b"COSMOS4_"

# OpenC3 5 Constants
OPENC3_FILE_HEADER = b"COSMOS5_"
OPENC3_INDEX_HEADER = b"COSIDX5_"
OPENC3_HEADER_LENGTH = len(OPENC3_FILE_HEADER)

# Entry type flags (masked with OPENC3_ENTRY_TYPE_MASK from flags field)
OPENC3_ENTRY_TYPE_MASK = 0xF000
OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK = 0x1000
OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK = 0x2000
OPENC3_RAW_PACKET_ENTRY_TYPE_MASK = 0x3000
OPENC3_JSON_PACKET_ENTRY_TYPE_MASK = 0x4000
OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK = 0x5000
OPENC3_KEY_MAP_ENTRY_TYPE_MASK = 0x6000

# Flag masks for packet metadata
OPENC3_RECEIVED_TIME_FLAG_MASK = 0x0040
OPENC3_EXTRA_FLAG_MASK = 0x0080
OPENC3_CBOR_FLAG_MASK = 0x0100
OPENC3_ID_FLAG_MASK = 0x0200
OPENC3_STORED_FLAG_MASK = 0x0400
OPENC3_CMD_FLAG_MASK = 0x0800

# Fixed sizes for various entry components
OPENC3_ID_FIXED_SIZE = 32
OPENC3_MAX_PACKET_INDEX = 65535
OPENC3_MAX_TARGET_INDEX = 65535

# Primary fixed size: 2 bytes for flags (length field size not included)
OPENC3_PRIMARY_FIXED_SIZE = 2

# Target declaration has no additional fixed data beyond flags
OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE = 0

# Packet declaration has 2 bytes for target index
OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE = 2

# Offset marker has no additional fixed data
OPENC3_OFFSET_MARKER_SECONDARY_FIXED_SIZE = 0

# Key map has 2 bytes for packet index
OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE = 2

# Packet entry has 2 bytes packet_index + 8 bytes timestamp
OPENC3_PACKET_SECONDARY_FIXED_SIZE = 10

# Received time is 8 bytes (nanoseconds since epoch)
OPENC3_RECEIVED_TIME_FIXED_SIZE = 8

# Extra data length field is 4 bytes
OPENC3_EXTRA_LENGTH_FIXED_SIZE = 4
