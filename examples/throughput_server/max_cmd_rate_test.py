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

"""
Maximum Command Rate Test (Python)

Tests the theoretical maximum command rate by directly connecting to the
throughput server and sending CCSDS commands as fast as possible.
This bypasses COSMOS entirely to measure raw TCP throughput.

Usage:
    python max_cmd_rate_test.py [host] [port] [duration_seconds]

Example:
    python max_cmd_rate_test.py host.docker.internal 7778 10
"""

import socket
import struct
import sys
import time

# Configuration
DEFAULT_HOST = "host.docker.internal"
DEFAULT_PORT = 7778
DEFAULT_DURATION = 10

# CCSDS Command constants
CMD_GET_STATS = 202
APID = 1  # Use APID 1 for commands


def build_ccsds_command(
    pktid: int, sequence_count: int = 0, payload: bytes = b""
) -> bytes:
    """Build a CCSDS command packet.

    Format:
        word0 (2 bytes): version(3) | type(1)=1 | shf(1)=0 | apid(11)
        word1 (2 bytes): seqflags(2)=3 | seqcnt(14)
        length (2 bytes): total_length - 7
        pktid (2 bytes): command ID
    """
    # word0: version=0, type=1 (command), shf=0, apid
    word0 = (0 << 13) | (1 << 12) | (0 << 11) | (APID & 0x07FF)

    # word1: seqflags=3, seqcnt
    word1 = (3 << 14) | (sequence_count & 0x3FFF)

    # Total packet length = 6 (primary header) + 2 (pktid) + payload
    total_length = 6 + 2 + len(payload)
    ccsds_length = total_length - 7

    # Pack the header
    header = struct.pack(">HHHH", word0, word1, ccsds_length, pktid)

    return header + payload


def run_test(host: str, port: int, duration: int) -> None:
    """Run the maximum command rate test."""
    print("=" * 60)
    print("Maximum Command Rate Test (Python)")
    print("=" * 60)
    print(f"Host: {host}:{port}")
    print(f"Duration: {duration} seconds")
    print()

    # Pre-build the command packet (GET_STATS with no payload)
    cmd_packet = build_ccsds_command(CMD_GET_STATS)
    print(f"Command packet size: {len(cmd_packet)} bytes")
    print(f"Command packet (hex): {cmd_packet.hex()}")
    print()

    # Connect to server
    print(f"Connecting to {host}:{port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.connect((host, port))
    sock.setblocking(False)
    print("Connected!")
    print()

    # Discard any initial telemetry from the server
    try:
        sock.recv(65536)
    except BlockingIOError:
        pass

    # Run the test
    print(f"Sending commands for {duration} seconds...")
    print()

    cmd_count = 0
    start_time = time.time()
    end_time = start_time + duration
    last_report_time = start_time
    last_report_count = 0

    # Set socket back to blocking for writes
    sock.setblocking(True)

    try:
        while time.time() < end_time:
            # Send the command
            sock.sendall(cmd_packet)
            cmd_count += 1

            # Periodic progress report (every second)
            now = time.time()
            if now - last_report_time >= 1.0:
                interval_count = cmd_count - last_report_count
                interval_rate = interval_count / (now - last_report_time)
                elapsed = now - start_time
                print(
                    f"  {elapsed:.1f}s: {cmd_count} commands sent ({interval_rate:.0f} cmd/s current)"
                )
                last_report_time = now
                last_report_count = cmd_count

            # Occasionally drain responses to prevent buffer buildup
            if cmd_count % 1000 == 0:
                sock.setblocking(False)
                try:
                    sock.recv(65536)
                except BlockingIOError:
                    pass
                sock.setblocking(True)

    except (BrokenPipeError, ConnectionResetError) as e:
        print(f"Connection error: {e}")
    finally:
        sock.close()

    # Calculate results
    actual_duration = time.time() - start_time
    overall_rate = cmd_count / actual_duration
    bytes_sent = cmd_count * len(cmd_packet)
    throughput_mbps = (bytes_sent * 8) / (actual_duration * 1_000_000)

    # Print results
    print()
    print("=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"Commands sent:     {cmd_count}")
    print(f"Actual duration:   {actual_duration:.3f} seconds")
    print(f"Command rate:      {overall_rate:.0f} commands/second")
    print(f"Bytes sent:        {bytes_sent} ({bytes_sent / 1024 / 1024:.2f} MB)")
    print(f"Throughput:        {throughput_mbps:.2f} Mbps")
    print("=" * 60)


def main():
    """Main entry point."""
    host = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HOST
    port = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_PORT
    duration = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_DURATION

    run_test(host, port, duration)


if __name__ == "__main__":
    main()
