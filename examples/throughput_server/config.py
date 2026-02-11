# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

"""Configuration constants for the throughput server."""

# Network configuration
INST_PORT = 7778  # Port for INST (Ruby) target
INST2_PORT = 7780  # Port for INST2 (Python) target

# CCSDS Command Packet IDs (from _ccsds_cmd.txt template)
CMD_START_STREAM = 200
CMD_STOP_STREAM = 201
CMD_GET_STATS = 202
CMD_GET_STATS_NO_MSG = 203
CMD_RESET_STATS = 204

# CCSDS Telemetry APIDs
APID_THROUGHPUT_STATUS = 100

# Telemetry Packet IDs
PKTID_THROUGHPUT_STATUS = 1

# Default streaming configuration
DEFAULT_STREAM_RATE = 100  # Packets per second
MAX_STREAM_RATE = 100000  # Maximum packets per second

# CCSDS Header sizes
CCSDS_CMD_HEADER_SIZE = 8  # Primary header (6) + PKTID (2)
CCSDS_TLM_HEADER_SIZE = 14  # Primary header (6) + Secondary header (6) + PKTID (2)

# Length protocol configuration (for LengthProtocol framing)
LENGTH_OFFSET = 4  # Byte offset of CCSDSLENGTH field
LENGTH_SIZE = 2  # Size of length field in bytes
LENGTH_ADJUSTMENT = 7  # CCSDS length = total_length - 7
