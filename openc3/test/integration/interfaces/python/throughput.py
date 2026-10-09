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
Simulated devices and a rate limited consumer for the socket throughput tests.

The devices run in a separate process (python throughput.py udp|tcp ...) so
they don't compete with the interface for the GIL. This module must not import
openc3 so the device process doesn't depend on which openc3 is under test.
"""

import json
import os
import socket
import struct
import sys
import time


MB = 1024 * 1024
# Total bytes the simulated device sends
TOTAL_BYTES = int(float(os.environ.get("OPENC3_SOCKET_TEST_MB", "30")) * MB)
# Rate the simulated device sends at
SEND_RATE = float(os.environ.get("OPENC3_SOCKET_TEST_SEND_MBPS", "40")) * MB
# Rate the interface consumer processes data at. This stands in for the
# protocol, decom and Redis work the interface microservice does per packet.
CONSUME_RATE = float(os.environ.get("OPENC3_SOCKET_TEST_CONSUME_MBPS", "20")) * MB
# UDP loss allowed with the read queue. Garbage collection can hold the GIL
# (and in Ruby stops every thread) and a pause of a few ms is enough to
# overflow the default Linux socket receive buffer (~200KB, ~5ms at 40MB/s), so
# a small loss can remain on Linux. Inline reads lose roughly half.
MAX_UDP_LOSS_PERCENT = float(os.environ.get("OPENC3_SOCKET_TEST_MAX_UDP_LOSS_PERCENT", "5"))
# Datagram / write size. Stays below the macOS default net.inet.udp.maxdgram.
CHUNK_SIZE = 8192
# Device transmit buffer. Fixed so the result doesn't depend on the OS TCP
# buffer autotuning (which starts small). Still far smaller than the backlog.
DEVICE_BUFFER_SIZE = 4 * MB
# Sent after the device finishes to tell the UDP consumer to stop
STOP_MARKER = b"STOP_SOCKET_THROUGHPUT_TEST"
# Worst case time to drain everything plus slack
CONSUME_TIMEOUT = ((TOTAL_BYTES / CONSUME_RATE) * 2) + 10


def pace(start, num_bytes, rate):
    """Sleep as needed to hold num_bytes / elapsed to the given rate"""
    ahead = (num_bytes / rate) - (time.monotonic() - start)
    if ahead > 0.0005:
        time.sleep(ahead)


def chunk(seq):
    return struct.pack(">I", seq) + (b"\xa5" * (CHUNK_SIZE - 4))


def udp_device(port):
    """Simulated device which sends datagrams at SEND_RATE"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.connect(("127.0.0.1", port))
    sent = 0
    seq = 0
    start = time.monotonic()
    while sent < TOTAL_BYTES:
        data = chunk(seq)
        try:
            sock.send(data)
        except OSError:
            # Local send queue full (ENOBUFS on macOS), retry the same datagram
            time.sleep(0.0001)
            continue
        sent += len(data)
        seq += 1
        pace(start, sent, SEND_RATE)
    sock.close()
    return {"sent_bytes": sent, "dropped_bytes": 0, "elapsed": time.monotonic() - start}


def tcp_device(server):
    """Simulated device which writes to a TCP client at SEND_RATE. Like real
    hardware it can't block waiting for a slow reader, so whatever can't be
    written without blocking is dropped (a device buffer overrun)."""
    conn, _ = server.accept()
    server.close()
    conn.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, DEVICE_BUFFER_SIZE)
    conn.setblocking(False)
    sent = 0
    dropped = 0
    produced = 0
    seq = 0
    start = time.monotonic()
    while produced < TOTAL_BYTES:
        data = chunk(seq)
        seq += 1
        produced += len(data)
        try:
            written = conn.send(data)
        except BlockingIOError:
            written = 0
        sent += written
        dropped += len(data) - written
        pace(start, produced, SEND_RATE)
    conn.close()
    return {"sent_bytes": sent, "dropped_bytes": dropped, "elapsed": time.monotonic() - start}


def main():
    if sys.argv[1] == "udp":
        result = udp_device(int(sys.argv[2]))
    else:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        # Tell the test which port to connect to
        print(server.getsockname()[1], flush=True)
        result = tcp_device(server)
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
