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
from unittest.mock import *

from openc3.packets.packet import Packet
from openc3.processors.watermark_processor import WatermarkProcessor
from test.test_helper import *


class TestWatermarkProcessor(unittest.TestCase):
    def test_takes_an_item_name_and_value_type(self):
        p = WatermarkProcessor("TEST", "RAW")
        self.assertEqual(p.value_type, "RAW")
        self.assertEqual(p.item_name, "TEST")

    def test_generates_a_high_and_low_water_mark(self):
        p = WatermarkProcessor("TEST", "RAW")
        packet = Packet("tgt", "pkt")
        packet.append_item("TEST", 8, "UINT")
        packet.buffer = b"\x01"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["HIGH_WATER"], 1)
        self.assertEqual(p.results["LOW_WATER"], 1)
        packet.buffer = b"\x02"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["HIGH_WATER"], 2)
        self.assertEqual(p.results["LOW_WATER"], 1)
        packet.buffer = b"\x00"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["HIGH_WATER"], 2)
        self.assertEqual(p.results["LOW_WATER"], 0)
        p.reset()
        self.assertEqual(p.results["HIGH_WATER"], None)
        self.assertEqual(p.results["LOW_WATER"], None)
