# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest

from openc3.interfaces.protocols.protocol import Protocol
from openc3.interfaces.stream_interface import StreamInterface
from test.test_helper import *


class TestProtocol(unittest.TestCase):
    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        self.interface = TestProtocol.MyInterface()

    def test_handles_true_false_and_none_allow_empty_data(self):
        self.assertIsNone(Protocol(None).allow_empty_data)
        self.assertTrue(Protocol(True).allow_empty_data)
        self.assertFalse(Protocol(False).allow_empty_data)
        # Config file values come through as strings
        self.assertIsNone(Protocol("NONE").allow_empty_data)
        self.assertTrue(Protocol("TRUE").allow_empty_data)
        self.assertFalse(Protocol("FALSE").allow_empty_data)

    def test_passes_through_data_which_isnt_empty(self):
        self.interface.add_protocol(Protocol, [None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b"\x01"), (b"\x01", None))
        self.assertEqual(self.interface.read_protocols[0].read_data(b"\x01", "extra"), (b"\x01", "extra"))

    def test_returns_stop_on_empty_data_when_allow_empty_data_is_false(self):
        # False means STOP even though this isn't the last protocol in the chain
        self.interface.add_protocol(Protocol, [False], "READ_WRITE")
        self.interface.add_protocol(Protocol, [None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), ("STOP", None))
        self.assertEqual(self.interface.read_protocols[0].read_data(b"\x01"), (b"\x01", None))

    def test_passes_through_empty_data_when_allow_empty_data_is_true(self):
        # True allows the empty string through even as the last protocol in the chain
        self.interface.add_protocol(Protocol, [True], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[-1], self.interface.read_protocols[0])
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), (b"", None))
        self.assertEqual(self.interface.read_protocols[0].read_data(b"", "extra"), (b"", "extra"))

    def test_returns_stop_on_empty_data_for_the_last_protocol_when_allow_empty_data_is_none(self):
        self.interface.add_protocol(Protocol, [None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), ("STOP", None))
        self.interface.add_protocol(Protocol, [None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), (b"", None))
        self.assertEqual(self.interface.read_protocols[1].read_data(b""), ("STOP", None))

    def test_passes_through_empty_data_when_allow_empty_data_is_none_and_there_is_no_interface(self):
        self.assertEqual(Protocol(None).read_data(b""), (b"", None))


class TestProtocolReset(unittest.TestCase):
    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        self.interface = TestProtocolReset.MyInterface()
        self.interface.add_protocol(Protocol, [None], "READ_WRITE")
        self.protocol = self.interface.read_protocols[0]

    def capture_data(self):
        self.protocol.read_protocol_input_base(b"\x01")
        self.protocol.read_protocol_output_base(b"\x02")
        self.protocol.write_protocol_input_base(b"\x03")
        self.protocol.write_protocol_output_base(b"\x04")
        self.protocol.extra = {"key": "value"}

    def assert_cleared(self):
        read = self.protocol.read_details()
        self.assertEqual(read["read_data_input"], b"")
        self.assertIsNone(read["read_data_input_time"])
        self.assertEqual(read["read_data_output"], b"")
        self.assertIsNone(read["read_data_output_time"])
        write = self.protocol.write_details()
        self.assertEqual(write["write_data_input"], b"")
        self.assertIsNone(write["write_data_input_time"])
        self.assertEqual(write["write_data_output"], b"")
        self.assertIsNone(write["write_data_output_time"])
        self.assertIsNone(self.protocol.extra)

    def test_initializes_the_details_data_to_empty_strings(self):
        self.assert_cleared()

    def test_clears_the_captured_details_data_and_extra(self):
        self.capture_data()
        read = self.protocol.read_details()
        self.assertEqual(read["read_data_input"], b"\x01")
        self.assertIsNotNone(read["read_data_input_time"])
        self.assertEqual(read["read_data_output"], b"\x02")
        self.assertIsNotNone(read["read_data_output_time"])
        write = self.protocol.write_details()
        self.assertEqual(write["write_data_input"], b"\x03")
        self.assertIsNotNone(write["write_data_input_time"])
        self.assertEqual(write["write_data_output"], b"\x04")
        self.assertIsNotNone(write["write_data_output_time"])
        self.assertEqual(self.protocol.extra, {"key": "value"})

        self.protocol.reset()
        self.assert_cleared()

    def test_is_called_by_connect_reset(self):
        self.capture_data()
        self.protocol.connect_reset()
        self.assert_cleared()

    def test_is_called_by_disconnect_reset(self):
        self.capture_data()
        self.protocol.disconnect_reset()
        self.assert_cleared()

    def test_does_not_capture_data_when_save_raw_data_is_false(self):
        self.interface.save_raw_data = False
        self.capture_data()
        self.protocol.extra = None
        self.assert_cleared()
