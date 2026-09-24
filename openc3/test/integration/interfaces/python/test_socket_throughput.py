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
A simulated device sends TOTAL_BYTES at SEND_RATE while the interface consumer
can only process CONSUME_RATE (slower). If the interface only reads the socket
when the consumer asks for the next packet, the backlog sits in the operating
system socket buffers which overflow: UDP datagrams are dropped by the kernel
and a TCP device can't write (so it overruns). With the read queue the socket
is drained by a dedicated thread and the backlog is buffered in memory (up to
READ_QUEUE_MAX_SIZE).
"""

import json
import socket
import subprocess
import sys
import threading
import time

import throughput as t

from openc3.interfaces.tcpip_client_interface import TcpipClientInterface
from openc3.interfaces.udp_interface import UdpInterface
from openc3.utilities.logger import Logger


# The interfaces log connect / disconnect info which clutters the report
Logger.stdout = False


def new_stats():
    return {"received_bytes": 0, "packets": 0, "peak_queue_bytes": 0, "error": None}


def consume(interface, stats):
    """Read packets from the interface until it disconnects or the STOP_MARKER
    arrives, processing no faster than CONSUME_RATE"""
    start = None
    try:
        while True:
            packet = interface.read()
            if packet is None:
                break
            data = packet.buffer_no_copy()
            if data.startswith(t.STOP_MARKER):
                break
            if start is None:
                start = time.monotonic()
            stats["received_bytes"] += len(data)
            stats["packets"] += 1
            if hasattr(interface, "read_queue_bytes"):
                stats["peak_queue_bytes"] = max(stats["peak_queue_bytes"], interface.read_queue_bytes())
            t.pace(start, stats["received_bytes"], t.CONSUME_RATE)
    except Exception as error:
        stats["error"] = error


def start_device(*args):
    return subprocess.Popen(
        [sys.executable, t.__file__, *[str(arg) for arg in args]],
        stdout=subprocess.PIPE,
        text=True,
    )


def wait_device(device):
    output, _ = device.communicate(timeout=t.CONSUME_TIMEOUT)
    assert device.returncode == 0
    return json.loads(output.strip().splitlines()[-1])


def report(label, device, stats):
    total = device["sent_bytes"] + device["dropped_bytes"]
    lost = total - stats["received_bytes"]
    print(
        f"\n    {label}: produced {total / t.MB:.1f}MB in {device['elapsed']:.2f}s, "
        f"received {stats['received_bytes'] / t.MB:.1f}MB, lost {lost / t.MB:.1f}MB "
        f"({100.0 * lost / total:.1f}%), peak queue {stats['peak_queue_bytes'] / t.MB:.1f}MB"
    )
    return lost


def lost_percent(device, stats):
    total = device["sent_bytes"] + device["dropped_bytes"]
    return 100.0 * (total - stats["received_bytes"]) / total


def set_read_queue_max_size(interface, read_queue_max_size):
    if read_queue_max_size is not None:
        interface.set_option("READ_QUEUE_MAX_SIZE", [str(read_queue_max_size)])


def run_udp(read_queue_max_size):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    interface = UdpInterface("127.0.0.1", None, port, None, None, 128, 10.0, None, "127.0.0.1")
    interface.name = "UDP_THROUGHPUT"
    set_read_queue_max_size(interface, read_queue_max_size)
    interface.connect()

    stats = new_stats()
    consumer = threading.Thread(target=consume, args=(interface, stats), daemon=True)
    consumer.start()
    device = wait_device(start_device("udp", port))

    # The STOP_MARKER queues up behind whatever is still waiting so keep
    # sending it (in case the kernel drops it) until the consumer sees it
    deadline = time.monotonic() + t.CONSUME_TIMEOUT
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stop_sock:
        while consumer.is_alive() and time.monotonic() < deadline:
            stop_sock.sendto(t.STOP_MARKER, ("127.0.0.1", port))
            consumer.join(0.1)
    interface.disconnect()
    consumer.join(5)
    if stats["error"]:
        raise stats["error"]
    return device, stats


def run_tcp(read_queue_max_size):
    process = start_device("tcp")
    port = int(process.stdout.readline())
    interface = TcpipClientInterface("127.0.0.1", port, port, 10.0, None)
    interface.name = "TCP_THROUGHPUT"
    set_read_queue_max_size(interface, read_queue_max_size)
    interface.connect()

    stats = new_stats()
    # The device closing the socket disconnects the consumer
    consumer = threading.Thread(target=consume, args=(interface, stats), daemon=True)
    consumer.start()
    device = wait_device(process)
    consumer.join(t.CONSUME_TIMEOUT)
    interface.disconnect()
    consumer.join(5)
    if stats["error"]:
        raise stats["error"]
    return device, stats


class TestUdp:
    def test_drops_datagrams_when_reads_are_inline(self):
        device, stats = run_udp(0)
        lost = report("UDP inline", device, stats)
        # Sanity check that the scenario actually overflows the socket buffer
        assert lost > 0

    def test_keeps_up_with_the_device_with_the_default_read_queue(self):
        device, stats = run_udp(None)
        report("UDP read queue", device, stats)
        assert lost_percent(device, stats) <= t.MAX_UDP_LOSS_PERCENT


class TestTcp:
    def test_overruns_the_device_when_reads_are_inline(self):
        device, stats = run_tcp(0)
        report("TCP inline", device, stats)
        # TCP doesn't lose data in transit but the device couldn't send it
        assert device["dropped_bytes"] > 0
        assert stats["received_bytes"] == device["sent_bytes"]

    def test_never_blocks_the_device_with_the_default_read_queue(self):
        device, stats = run_tcp(None)
        report("TCP read queue", device, stats)
        assert device["dropped_bytes"] == 0
        assert stats["received_bytes"] == device["sent_bytes"]
