# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import queue
import threading
import time
import unittest
from unittest.mock import Mock, patch

from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.interfaces.protocols.length_protocol import LengthProtocol
from openc3.interfaces.stream_interface import StreamInterface
from openc3.streams.stream import Stream
from openc3.utilities.read_queue import READ_QUEUE_ENTRY_OVERHEAD


# Stream which returns the data it is given, one read at a time, and then blocks
# until it is disconnected. Reads which return None or b"" mean the stream is
# closed so a test stream can't simply return nothing.
class QueueStream(Stream):
    def __init__(self, *data):
        self.queue = queue.Queue()
        self.reads = 0
        self.closed = False
        for datum in data:
            self.queue.put(datum)

    def push(self, data):
        self.queue.put(data)

    def connect(self):
        pass

    def connected(self):
        return True

    def disconnect(self):
        self.closed = True

    def read(self):
        self.reads += 1
        while True:
            try:
                return self.queue.get(timeout=0.01)
            except queue.Empty:
                if self.closed:
                    # None disconnects the interface
                    return None

    def write(self, data):
        pass


# Stream whose read blocks until released, even across a disconnect, like a
# stream whose disconnect doesn't wake up a pending read
class StuckStream(Stream):
    def __init__(self):
        self.reading = threading.Event()
        self.release = threading.Event()
        self.reads = 0

    def connect(self):
        pass

    def connected(self):
        return True

    def disconnect(self):
        pass

    def read(self):
        self.reads += 1
        self.reading.set()
        self.release.wait(5)
        return b"\x01\x02\x03"

    def write(self, data):
        pass


class TestStreamInterface(unittest.TestCase):
    def setUp(self):
        self.interface = StreamInterface()

    def tearDown(self):
        self.interface.disconnect()

    def wait_for_queue_size(self, size, timeout=2):
        start = time.time()
        while self.interface.read_queue_size() < size and (time.time() - start) < timeout:
            time.sleep(0.001)

    def test_adds_burst_protocol(self):
        i = StreamInterface("burst")
        self.assertEqual(i.name, "StreamInterface")
        self.assertEqual(i.read_protocols[0], i.write_protocols[0])
        self.assertIsInstance(i.read_protocols[0], BurstProtocol)

    def test_adds_length_protocol_with_params(self):
        i = StreamInterface("length", [1, 2])
        self.assertEqual(i.name, "StreamInterface")
        self.assertEqual(i.read_protocols[0], i.write_protocols[0])
        self.assertIsInstance(i.read_protocols[0], LengthProtocol)
        self.assertEqual(i.read_protocols[0].length_bit_offset, 1)
        self.assertEqual(i.read_protocols[0].length_bit_size, 2)
        self.assertEqual(i.read_protocols[0].length_value_offset, 0)
        self.assertEqual(i.read_protocols[0].length_bytes_per_count, 1)

    def test_reads_ahead_of_read_interface(self):
        self.interface.stream = QueueStream(b"\x01", b"\x02", b"\x03")
        self.interface.connect()
        # The read thread drains the stream without read_interface being called
        self.wait_for_queue_size(3)
        self.assertEqual(self.interface.read_queue_size(), 3)

        self.assertEqual(self.interface.read_interface()[0], b"\x01")
        self.assertEqual(self.interface.read_interface()[0], b"\x02")
        self.assertEqual(self.interface.read_interface()[0], b"\x03")
        self.assertEqual(self.interface.read_queue_size(), 0)

    def test_reports_the_bytes_waiting_on_the_queue(self):
        self.interface.stream = QueueStream(b"\x01\x02", b"\x03\x04\x05")
        self.interface.connect()
        self.wait_for_queue_size(2)
        self.assertEqual(self.interface.read_queue_bytes(), 5)

        self.assertEqual(self.interface.read_interface()[0], b"\x01\x02")
        self.assertEqual(self.interface.read_queue_bytes(), 3)
        self.assertEqual(self.interface.read_interface()[0], b"\x03\x04\x05")
        self.assertEqual(self.interface.read_queue_bytes(), 0)

    def test_blocks_until_the_read_thread_queues_data(self):
        stream = QueueStream()
        self.interface.stream = stream
        self.interface.connect()
        result = {}

        def do_read():
            result["data"] = self.interface.read_interface()[0]

        thread = threading.Thread(target=do_read)
        thread.start()
        time.sleep(0.05)
        self.assertTrue(thread.is_alive())
        stream.push(b"\x01\x02")
        thread.join(2)
        self.assertEqual(result["data"], b"\x01\x02")

    def test_counts_the_bytes_read_as_they_are_dequeued(self):
        self.interface.stream = QueueStream(b"\x01\x02\x03")
        self.interface.connect()
        self.assertEqual(self.interface.read_interface()[0], b"\x01\x02\x03")
        self.assertEqual(self.interface.bytes_read, 3)

    def test_returns_none_when_the_stream_closes(self):
        self.interface.stream = QueueStream(b"\x01", b"")
        self.interface.connect()
        self.assertEqual(self.interface.read_interface()[0], b"\x01")
        self.assertEqual(self.interface.read_interface(), (None, None))
        # Still None rather than blocking forever now the read thread is done
        self.assertEqual(self.interface.read_interface(), (None, None))

    def test_reraises_exceptions_from_the_read_thread(self):
        stream = QueueStream()
        stream.read = Mock(side_effect=RuntimeError("read failed"))
        self.interface.stream = stream
        self.interface.connect()
        with self.assertRaisesRegex(RuntimeError, "read failed"):
            self.interface.read_interface()

    def test_returns_none_on_a_read_timeout(self):
        stream = QueueStream()
        stream.read = Mock(side_effect=TimeoutError)
        self.interface.stream = stream
        self.interface.connect()
        self.assertEqual(self.interface.read_interface(), (None, None))

    def test_does_not_start_a_read_thread_when_reading_isnt_allowed(self):
        self.interface.read_allowed = False
        stream = QueueStream(b"\x01")
        self.interface.stream = stream
        self.interface.connect()
        time.sleep(0.05)
        self.assertEqual(stream.reads, 0)
        self.assertEqual(self.interface.read_queue_size(), 0)

    def test_limits_how_many_bytes_are_buffered(self):
        # Each queued read is also charged the per entry overhead so budget for
        # exactly two of the two byte reads below
        max_size = 2 * (2 + READ_QUEUE_ENTRY_OVERHEAD)
        self.interface.set_option("READ_QUEUE_MAX_SIZE", [str(max_size)])
        self.assertEqual(self.interface.read_queue_max_size, max_size)
        self.interface.stream = QueueStream(b"\x01\x02", b"\x03\x04", b"\x05\x06")
        self.interface.connect()
        time.sleep(0.1)
        # The read thread blocks on the third read rather than going over budget
        self.assertEqual(self.interface.read_queue_bytes(), 4)
        self.assertEqual(self.interface.read_queue_size(), 2)

        # Dequeuing makes room so the read thread queues the read it was holding
        self.assertEqual(self.interface.read_interface()[0], b"\x01\x02")
        start = time.time()
        while self.interface.read_queue_bytes() < 4 and (time.time() - start) < 2:
            time.sleep(0.001)
        self.assertEqual(self.interface.read_queue_bytes(), 4)

    def test_queues_a_read_larger_than_the_entire_budget_on_its_own(self):
        self.interface.set_option("READ_QUEUE_MAX_SIZE", ["2"])
        self.interface.stream = QueueStream(b"\x01\x02\x03\x04\x05")
        self.interface.connect()
        # Otherwise the read would never fit and the interface would stall
        self.assertEqual(self.interface.read_interface()[0], b"\x01\x02\x03\x04\x05")

    def test_raises_if_the_max_size_is_negative(self):
        with self.assertRaisesRegex(RuntimeError, r"READ_QUEUE_MAX_SIZE must be 0 \(disabled\) or a positive integer"):
            self.interface.set_option("READ_QUEUE_MAX_SIZE", ["-1"])

    def test_reads_inline_without_a_read_thread_when_the_max_size_is_0(self):
        self.interface.set_option("READ_QUEUE_MAX_SIZE", ["0"])
        stream = QueueStream(b"\x01", b"\x02")
        self.interface.stream = stream
        self.interface.connect()
        self.assertIsNone(self.interface.read_queue_thread)
        # Nothing reads ahead of read_interface
        time.sleep(0.05)
        self.assertEqual(stream.reads, 0)
        self.assertEqual(self.interface.read_queue_size(), 0)

        self.assertEqual(self.interface.read_interface()[0], b"\x01")
        self.assertEqual(stream.reads, 1)
        self.assertEqual(self.interface.read_interface()[0], b"\x02")
        self.assertEqual(stream.reads, 2)
        self.assertEqual(self.interface.read_queue_bytes(), 0)
        self.assertIsNone(self.interface.read_queue_thread)

        # A closed stream still disconnects the interface
        stream.disconnect()
        self.assertEqual(self.interface.read_interface(), (None, None))

    def test_disconnect_stops_the_read_thread_and_clears_the_queue(self):
        self.interface.stream = QueueStream(b"\x01", b"\x02")
        self.interface.connect()
        self.wait_for_queue_size(2)
        self.assertGreater(self.interface.read_queue_size(), 0)
        self.interface.disconnect()
        self.assertEqual(self.interface.read_queue_size(), 0)
        self.assertEqual(self.interface.read_queue_bytes(), 0)
        self.assertIsNone(self.interface.read_queue_thread)

    def test_setting_the_stream_stops_the_read_thread(self):
        self.interface.stream = QueueStream(b"\x01")
        self.interface.connect()
        self.wait_for_queue_size(1)
        self.assertEqual(self.interface.read_queue_size(), 1)
        self.interface.stream = QueueStream(b"\x02")
        self.assertEqual(self.interface.read_queue_size(), 0)
        self.assertEqual(self.interface.read_interface()[0], b"\x02")

    @patch("openc3.utilities.read_queue.THREAD_JOIN_TIMEOUT", 0.05)
    def test_a_replaced_read_thread_stuck_in_a_read_does_not_queue_or_read_again(self):
        stuck = StuckStream()
        self.interface.stream = stuck
        self.interface.connect()
        self.assertTrue(stuck.reading.wait(2))
        old_thread = self.interface.read_queue_thread

        # The old thread can't be stopped because its read never returns
        self.interface.stream = QueueStream(b"\x0a")
        self.interface.connect()
        self.wait_for_queue_size(1)
        self.assertTrue(old_thread.is_alive())

        # Once its read finally returns the old thread must exit without
        # charging the bytes against the new queue or reading the new stream
        stuck.release.set()
        old_thread.join(2)
        self.assertFalse(old_thread.is_alive())
        self.assertEqual(stuck.reads, 1)
        self.assertEqual(self.interface.read_queue_bytes(), 1)
        self.assertEqual(self.interface.read_interface()[0], b"\x0a")
        self.assertEqual(self.interface.read_queue_bytes(), 0)
