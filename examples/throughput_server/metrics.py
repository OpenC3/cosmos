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

"""Throughput metrics tracking and reporting."""

import struct
import time
from dataclasses import dataclass, field
from threading import Lock

from config import APID_THROUGHPUT_STATUS, PKTID_THROUGHPUT_STATUS


@dataclass
class ThroughputMetrics:
    """Track throughput statistics for a connection."""

    cmd_recv_count: int = 0
    tlm_sent_count: int = 0
    bytes_recv: int = 0
    bytes_sent: int = 0
    start_time: float = field(default_factory=time.time)
    target_rate: int = 0
    _lock: Lock = field(default_factory=Lock, repr=False)

    # For rate calculation
    _last_rate_time: float = field(default_factory=time.time)
    _last_cmd_count: int = 0
    _last_tlm_count: int = 0
    _cmd_rate: float = 0.0
    _tlm_rate: float = 0.0

    def record_command(self, bytes_received: int) -> None:
        """Record a received command."""
        with self._lock:
            self.cmd_recv_count += 1
            self.bytes_recv += bytes_received

    def record_telemetry(self, bytes_sent: int) -> None:
        """Record a sent telemetry packet."""
        with self._lock:
            self.tlm_sent_count += 1
            self.bytes_sent += bytes_sent

    def update_rates(self) -> None:
        """Update rate calculations (call periodically)."""
        with self._lock:
            now = time.time()
            elapsed = now - self._last_rate_time

            if elapsed >= 1.0:  # Update every second
                self._cmd_rate = (
                    self.cmd_recv_count - self._last_cmd_count
                ) / elapsed
                self._tlm_rate = (
                    self.tlm_sent_count - self._last_tlm_count
                ) / elapsed

                self._last_rate_time = now
                self._last_cmd_count = self.cmd_recv_count
                self._last_tlm_count = self.tlm_sent_count

    def get_uptime(self) -> int:
        """Get server uptime in seconds."""
        return int(time.time() - self.start_time)

    def get_cmd_rate(self) -> float:
        """Get current command rate."""
        with self._lock:
            return self._cmd_rate

    def get_tlm_rate(self) -> float:
        """Get current telemetry rate."""
        with self._lock:
            return self._tlm_rate

    def reset(self) -> None:
        """Reset all metrics."""
        with self._lock:
            self.cmd_recv_count = 0
            self.tlm_sent_count = 0
            self.bytes_recv = 0
            self.bytes_sent = 0
            self.start_time = time.time()
            self._last_rate_time = time.time()
            self._last_cmd_count = 0
            self._last_tlm_count = 0
            self._cmd_rate = 0.0
            self._tlm_rate = 0.0


class ThroughputStatusPacket:
    """Build THROUGHPUT_STATUS telemetry packets with pre-allocated buffer.

    Optimized for high-throughput streaming with minimal allocations.
    Uses struct.pack_into() to update fields in-place.

    Packet layout (56 bytes total):
        Header (16 bytes):
            0-1:   word0 (version/type/shf/apid) - STATIC
            2-3:   word1 (seqflags/seqcnt) - seqcnt updates
            4-5:   ccsdslength - STATIC
            6-9:   timesec - updates
            10-13: timeus - updates
            14-15: pktid - STATIC
        Payload (40 bytes):
            16-19: CMD_RECV_COUNT
            20-23: CMD_RECV_RATE
            24-27: TLM_SENT_COUNT
            28-31: TLM_SENT_RATE
            32-35: TLM_TARGET_RATE
            36-43: BYTES_RECV
            44-51: BYTES_SENT
            52-55: UPTIME_SEC
    """

    PACKET_SIZE = 56
    PAYLOAD_OFFSET = 16

    def __init__(self):
        self._sequence_count = 0
        # Pre-allocate buffer
        self._buffer = bytearray(self.PACKET_SIZE)

        # Build static header fields once
        # word0: version=0, type=0 (telemetry), shf=1, apid
        word0 = (0 << 13) | (0 << 12) | (1 << 11) | (APID_THROUGHPUT_STATUS & 0x07FF)
        struct.pack_into(">H", self._buffer, 0, word0)

        # ccsdslength: total_length - 7 = 56 - 7 = 49
        struct.pack_into(">H", self._buffer, 4, 49)

        # pktid
        struct.pack_into(">H", self._buffer, 14, PKTID_THROUGHPUT_STATUS)

    def update(self, metrics: ThroughputMetrics) -> None:
        """Update the packet buffer with current values.

        Call this before sending. Does not allocate memory.
        """
        # Update sequence count (preserving seqflags=3 in upper 2 bits)
        word1 = (3 << 14) | (self._sequence_count & 0x3FFF)
        struct.pack_into(">H", self._buffer, 2, word1)
        self._sequence_count = (self._sequence_count + 1) & 0x3FFF

        # Update timestamp
        now = time.time()
        struct.pack_into(">II", self._buffer, 6, int(now), int((now % 1) * 1_000_000))

        # Update payload - grab all values under lock, then pack
        with metrics._lock:
            struct.pack_into(
                ">IfIfIQQI",
                self._buffer,
                self.PAYLOAD_OFFSET,
                metrics.cmd_recv_count,
                metrics._cmd_rate,
                metrics.tlm_sent_count,
                metrics._tlm_rate,
                metrics.target_rate,
                metrics.bytes_recv,
                metrics.bytes_sent,
                int(now - metrics.start_time),  # uptime inline
            )

    def get_buffer(self) -> bytearray:
        """Get the packet buffer for sending.

        Returns the internal buffer directly - do not modify.
        """
        return self._buffer

    def reset_sequence(self) -> None:
        """Reset the sequence counter to 0."""
        self._sequence_count = 0

    def build(self, metrics: ThroughputMetrics) -> bytes:
        """Build and return packet as bytes (for compatibility).

        Less efficient than update() + get_buffer() but simpler for one-off sends.
        """
        self.update(metrics)
        return bytes(self._buffer)


@dataclass
class StreamState:
    """Track streaming state for a connection."""

    streaming: bool = False
    rate: int = 0  # Packets per second
    packet_types: int = 0x01  # Bitmask of packet types to stream
    last_send_time: float = 0.0
    send_interval: float = 0.0  # Seconds between packets

    def start(self, rate: int, packet_types: int = 0x01) -> None:
        """Start streaming at the specified rate."""
        self.streaming = True
        self.rate = rate
        self.packet_types = packet_types
        self.send_interval = 1.0 / rate if rate > 0 else 0.0
        self.last_send_time = time.time()

    def stop(self) -> None:
        """Stop streaming."""
        self.streaming = False
        self.rate = 0
        self.send_interval = 0.0

    def should_send(self) -> bool:
        """Check if it's time to send the next packet."""
        if not self.streaming:
            return False

        now = time.time()
        if now - self.last_send_time >= self.send_interval:
            self.last_send_time = now
            return True
        return False
