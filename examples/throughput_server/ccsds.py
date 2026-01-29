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

"""CCSDS packet encoding and decoding utilities."""

import struct
import time
from dataclasses import dataclass
from typing import Tuple

from config import (
    CCSDS_CMD_HEADER_SIZE,
    CCSDS_TLM_HEADER_SIZE,
    LENGTH_ADJUSTMENT,
)


@dataclass
class CcsdsCommand:
    """Parsed CCSDS command packet."""

    version: int
    packet_type: int
    secondary_header_flag: int
    apid: int
    sequence_flags: int
    sequence_count: int
    length: int
    pktid: int
    payload: bytes


@dataclass
class CcsdsTelemetry:
    """CCSDS telemetry packet structure."""

    apid: int
    sequence_count: int
    pktid: int
    payload: bytes
    time_sec: int = 0
    time_us: int = 0


def parse_ccsds_command(data: bytes) -> CcsdsCommand:
    """Parse a CCSDS command packet.

    CCSDS Command Header (8 bytes):
    Bits 0-2:   CCSDSVER (3 bits) = 0
    Bit 3:      CCSDSTYPE (1 bit) = 1 (command)
    Bit 4:      CCSDSSHF (1 bit) = 0
    Bits 5-15:  CCSDSAPID (11 bits)
    Bits 16-17: CCSDSSEQFLAGS (2 bits) = 3
    Bits 18-31: CCSDSSEQCNT (14 bits)
    Bits 32-47: CCSDSLENGTH (16 bits) = packet_length - 7
    Bits 48-63: PKTID (16 bits)

    Args:
        data: Raw packet bytes (must be at least CCSDS_CMD_HEADER_SIZE bytes)

    Returns:
        Parsed CcsdsCommand object
    """
    if len(data) < CCSDS_CMD_HEADER_SIZE:
        raise ValueError(
            f"Command packet too short: {len(data)} < {CCSDS_CMD_HEADER_SIZE}"
        )

    # Parse first two bytes (big-endian): version(3) + type(1) + shf(1) + apid(11)
    word0 = struct.unpack(">H", data[0:2])[0]
    version = (word0 >> 13) & 0x07
    packet_type = (word0 >> 12) & 0x01
    secondary_header_flag = (word0 >> 11) & 0x01
    apid = word0 & 0x07FF

    # Parse next two bytes: seqflags(2) + seqcnt(14)
    word1 = struct.unpack(">H", data[2:4])[0]
    sequence_flags = (word1 >> 14) & 0x03
    sequence_count = word1 & 0x3FFF

    # Parse length field (2 bytes)
    length = struct.unpack(">H", data[4:6])[0]

    # Parse PKTID (2 bytes)
    pktid = struct.unpack(">H", data[6:8])[0]

    # Extract payload (after 8-byte header)
    payload = data[CCSDS_CMD_HEADER_SIZE:]

    return CcsdsCommand(
        version=version,
        packet_type=packet_type,
        secondary_header_flag=secondary_header_flag,
        apid=apid,
        sequence_flags=sequence_flags,
        sequence_count=sequence_count,
        length=length,
        pktid=pktid,
        payload=payload,
    )


def build_ccsds_telemetry(
    tlm: CcsdsTelemetry, use_current_time: bool = True
) -> bytes:
    """Build a CCSDS telemetry packet.

    CCSDS Telemetry Header (16 bytes):
    Bits 0-2:   CCSDSVER (3 bits) = 0
    Bit 3:      CCSDSTYPE (1 bit) = 0 (telemetry)
    Bit 4:      CCSDSSHF (1 bit) = 1 (secondary header present)
    Bits 5-15:  CCSDSAPID (11 bits)
    Bits 16-17: CCSDSSEQFLAGS (2 bits) = 3
    Bits 18-31: CCSDSSEQCNT (14 bits)
    Bits 32-47: CCSDSLENGTH (16 bits)
    Bits 48-79: TIMESEC (32 bits)
    Bits 80-111: TIMEUS (32 bits)
    Bits 112-127: PKTID (16 bits)

    Args:
        tlm: Telemetry packet data
        use_current_time: If True, use current time; otherwise use tlm.time_sec/time_us

    Returns:
        Raw packet bytes
    """
    if use_current_time:
        now = time.time()
        time_sec = int(now)
        time_us = int((now - time_sec) * 1_000_000)
    else:
        time_sec = tlm.time_sec
        time_us = tlm.time_us

    # Calculate total packet length
    # CCSDSLENGTH = (packet_length - 7), where packet_length includes primary header
    # Packet = primary header (6) + secondary header (8: TIMESEC+TIMEUS) + PKTID (2) + payload
    total_length = 6 + 8 + 2 + len(tlm.payload)
    ccsds_length = total_length - LENGTH_ADJUSTMENT

    # Build first word: version(3) + type(1) + shf(1) + apid(11)
    # version=0, type=0 (telemetry), shf=1 (secondary header present)
    word0 = (0 << 13) | (0 << 12) | (1 << 11) | (tlm.apid & 0x07FF)

    # Build second word: seqflags(2) + seqcnt(14)
    # seqflags=3 (standalone packet)
    word1 = (3 << 14) | (tlm.sequence_count & 0x3FFF)

    # Pack header
    header = struct.pack(
        ">HHHIIH",
        word0,
        word1,
        ccsds_length,
        time_sec,
        time_us,
        tlm.pktid,
    )

    return header + tlm.payload


def read_packet_from_stream(data: bytes) -> Tuple[bytes, bytes]:
    """Extract a complete packet from a data stream using LengthProtocol.

    Uses the CCSDSLENGTH field to determine packet boundaries.

    Args:
        data: Raw data buffer

    Returns:
        Tuple of (complete_packet, remaining_data)
        If no complete packet is available, returns (b"", data)
    """
    if len(data) < 6:
        # Not enough data for primary header
        return b"", data

    # Read length field at bytes 4-5
    ccsds_length = struct.unpack(">H", data[4:6])[0]
    total_length = ccsds_length + LENGTH_ADJUSTMENT

    if len(data) < total_length:
        # Not enough data for complete packet
        return b"", data

    return data[:total_length], data[total_length:]
