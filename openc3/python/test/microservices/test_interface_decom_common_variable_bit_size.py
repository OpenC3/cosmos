# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import unittest
from unittest.mock import MagicMock, patch

from openc3.microservices.interface_decom_common import handle_inject_tlm
from openc3.packets.packet import Packet


class TestInterfaceDecomCommonVariableBitSize(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TGT", "PKT", "BIG_ENDIAN")
        self.packet.append_item("HDR", 8, "UINT")
        self.packet.append_item("LEN", 8, "UINT")
        item = self.packet.append_item("DATA", 0, "STRING")
        item.variable_bit_size = {"length_item_name": "LEN", "length_bits_per_count": 8, "length_value_bit_offset": 0}
        self.packet.append_item("TRAILER", 8, "UINT")
        self.packet.buffer = bytearray(b"\x00" * self.packet.defined_length)
        system = MagicMock()
        system.telemetry.packet.return_value = self.packet
        target_model = MagicMock()
        target_model.increment_telemetry_count.return_value = 1
        for target, value in (
            ("System", system),
            ("TargetModel", target_model),
            ("TelemetryTopic", MagicMock()),
        ):
            patcher = patch(f"openc3.microservices.interface_decom_common.{target}", value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def inject(self, item_hash):
        handle_inject_tlm(
            json.dumps({"target_name": "TGT", "packet_name": "PKT", "item_hash": item_hash, "type": "CONVERTED"}),
            "DEFAULT",
        )

    def assert_packet(self, data):
        self.assertEqual(self.packet.read("HDR"), 0xA5)
        self.assertEqual(self.packet.read("LEN"), len(data))
        self.assertEqual(self.packet.read("DATA"), data)
        self.assertEqual(self.packet.read("TRAILER"), 0x5A)
        self.assertEqual(len(self.packet.buffer), 3 + len(data))

    def test_sets_the_length_item_from_the_variable_sized_item_across_repeated_injections(self):
        # Sequence from https://github.com/OpenC3/cosmos/issues/4183
        self.inject({"HDR": 0xA5, "LEN": 11, "DATA": "hello world", "TRAILER": 0x5A})
        self.assert_packet("hello world")
        self.inject({"HDR": 0xA5, "DATA": "hello world", "TRAILER": 0x5A})
        self.assert_packet("hello world")
        self.inject({"HDR": 0xA5, "LEN": 0, "DATA": "", "TRAILER": 0x5A})
        self.assert_packet("")
        self.inject({"HDR": 0xA5, "LEN": 0, "DATA": "hello world!", "TRAILER": 0x5A})
        self.assert_packet("hello world!")
        self.inject({"HDR": 0xA5, "LEN": 0, "DATA": "hello world!", "TRAILER": 0x5A})
        self.assert_packet("hello world!")
        self.inject({"HDR": 0xA5, "LEN": 0, "DATA": "", "TRAILER": 0x5A})
        self.assert_packet("")
        self.inject({"HDR": 0xA5, "LEN": 11, "DATA": "hello world", "TRAILER": 0x5A})
        self.assert_packet("hello world")

    def test_keeps_the_current_variable_sized_item_when_only_other_items_are_given(self):
        self.inject({"HDR": 0xA5, "DATA": "hello", "TRAILER": 0x5A})
        self.inject({"TRAILER": 0x5A})
        self.assert_packet("hello")

    def test_skips_the_length_item_regardless_of_case_and_hash_order(self):
        self.inject({"trailer": 0x5A, "len": 3, "hdr": 0xA5, "data": "hello"})
        self.assert_packet("hello")
