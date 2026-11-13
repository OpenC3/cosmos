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

import json
import struct
import unittest
from unittest.mock import MagicMock, patch

from openc3.microservices.interface_decom_common import handle_inject_tlm
from openc3.packets.packet import Packet
from test.test_helper import mock_redis


class TestInterfaceDecomCommonInjectTlm(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # Packet from https://github.com/OpenC3/cosmos/issues/4185
        self.packet = Packet("FTGT", "PKT", "BIG_ENDIAN")
        self.packet.append_item("HDR", 8, "UINT")
        self.packet.append_item("LEN", 8, "UINT")
        data = self.packet.append_item("DATA", 32, "FLOAT", 0)
        data.variable_bit_size = {"length_item_name": "LEN", "length_value_bit_offset": 0, "length_bits_per_count": 32}
        self.packet.append_item("TRAILER", 8, "UINT")
        self.packet.buffer = b"\x00" * self.packet.defined_length
        system = MagicMock()
        system.telemetry.packet.return_value = self.packet
        for target, value in (
            ("System", system),
            ("TargetModel.increment_telemetry_count", MagicMock(return_value=1)),
            ("TelemetryTopic.write_packet", MagicMock()),
        ):
            patcher = patch(f"openc3.microservices.interface_decom_common.{target}", value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def inject(self, item_hash):
        handle_inject_tlm(
            json.dumps({"target_name": "FTGT", "packet_name": "PKT", "item_hash": item_hash, "type": "CONVERTED"}),
            "DEFAULT",
        )

    def test_writes_a_variable_sized_array_when_the_length_item_is_given_before_it(self):
        for values in ([-2.5, 5.0, 3.5], [1.5, 3.0, 4.5, 6.0, 7.5], [-2.5, 5.0, 3.5]):
            self.inject({"HDR": 0xA5, "LEN": len(values), "DATA": values, "TRAILER": 0x5A})
            self.assertEqual(
                self.packet.buffer, bytes([0xA5, len(values)]) + struct.pack(f">{len(values)}f", *values) + b"\x5a"
            )
            self.assertEqual(self.packet.read("LEN"), len(values))
            self.assertEqual(self.packet.read("DATA"), values)
            self.assertEqual(self.packet.read("TRAILER"), 0x5A)

    def test_writes_a_length_item_when_its_variable_sized_item_is_not_given(self):
        self.inject({"HDR": 0xA5, "DATA": [1.5], "TRAILER": 0x5A})
        self.inject({"len": 0})
        self.assertEqual(self.packet.read("LEN"), 0)
