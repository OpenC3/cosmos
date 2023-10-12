# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.processors.statistics_processor import StatisticsProcessor
from openc3.packets.packet import Packet


class TestStatisticsProcessor(unittest.TestCase):
    def test_takes_an_item_name_samples_to_average_and_value_type(self):
        p = StatisticsProcessor("TEST", "5", "RAW")
        self.assertEqual(p.value_type, "RAW")
        self.assertEqual(p.item_name, "TEST")
        self.assertEqual(p.samples_to_average, 5)

    def test_generates_statistics(self):
        p = StatisticsProcessor("TEST", "5", "RAW")
        packet = Packet("tgt", "pkt")
        packet.append_item("TEST", 8, "UINT")
        packet.buffer = b"\x01"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 1)
        self.assertEqual(p.results["MIN"], 1)
        self.assertAlmostEqual(p.results["MEAN"], 1.0)
        self.assertAlmostEqual(p.results["STDDEV"], 0.0)
        packet.buffer = b"\x02"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 2)
        self.assertEqual(p.results["MIN"], 1)
        self.assertAlmostEqual(p.results["MEAN"], 1.5)
        self.assertAlmostEqual(p.results["STDDEV"], 0.7071, 4)
        packet.buffer = b"\x00"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 2)
        self.assertEqual(p.results["MIN"], 0)
        self.assertAlmostEqual(p.results["MEAN"], 1.0)
        self.assertAlmostEqual(p.results["STDDEV"], 1.0)
        p.reset()
        self.assertEqual(p.results["MAX"], None)
        self.assertEqual(p.results["MIN"], None)
        self.assertEqual(p.results["MEAN"], None)
        self.assertEqual(p.results["STDDEV"], None)

    def test_handles_None_and_infinity(self):
        p = StatisticsProcessor("TEST", "5")
        packet = Packet("tgt", "pkt")
        packet.append_item("TEST", 32, "FLOAT")
        packet.write("TEST", 1)
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 1.0)
        self.assertEqual(p.results["MIN"], 1.0)
        self.assertAlmostEqual(p.results["MEAN"], 1.0)
        self.assertAlmostEqual(p.results["STDDEV"], 0.0)
        packet.write("TEST", float("nan"))
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 1.0)
        self.assertEqual(p.results["MIN"], 1.0)
        self.assertAlmostEqual(p.results["MEAN"], 1.0)
        self.assertAlmostEqual(p.results["STDDEV"], 0.0)
        packet.write("TEST", 2)
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 2.0)
        self.assertEqual(p.results["MIN"], 1.0)
        self.assertAlmostEqual(p.results["MEAN"], 1.5)
        self.assertAlmostEqual(p.results["STDDEV"], 0.7071, 4)
        packet.write("TEST", float("inf"))
        p.call(packet, packet.buffer)
        self.assertEqual(p.results["MAX"], 2.0)
        self.assertEqual(p.results["MIN"], 1.0)
        self.assertAlmostEqual(p.results["MEAN"], 1.5)
        self.assertAlmostEqual(p.results["STDDEV"], 0.7071, 4)
        p.reset()
        self.assertEqual(p.results["MAX"], None)
        self.assertEqual(p.results["MIN"], None)
        self.assertEqual(p.results["MEAN"], None)
        self.assertEqual(p.results["STDDEV"], None)
