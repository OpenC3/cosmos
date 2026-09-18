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
