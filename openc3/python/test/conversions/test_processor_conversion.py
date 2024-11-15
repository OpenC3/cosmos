# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
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
from openc3.conversions.processor_conversion import ProcessorConversion
from openc3.processors.processor import Processor
from openc3.packets.packet import Packet


class TestProcessorConversion(unittest.TestCase):
    def test_takes_processor_name_result_name_converted_type_and_converted_bit_size(
        self,
    ):
        c = ProcessorConversion("TEST", "RESULT", "FLOAT", "64", "128")
        self.assertEqual(c.processor_name, "TEST")
        self.assertEqual(c.result_name, "RESULT")
        self.assertEqual(c.converted_type, "FLOAT")
        self.assertEqual(c.converted_bit_size, 64)
        self.assertEqual(c.converted_array_size, 128)

    def test_retrieves_the_result_from_the_processor(self):
        c = ProcessorConversion("TEST", "RESULT", "FLOAT", "64")
        packet = Packet("tgt", "pkt")
        packet.append_item("ITEM1", 64, "FLOAT")
        proc = Processor()
        proc.results = {"RESULT": 6.0}
        packet.processors["TEST"] = proc
        self.assertEqual(c.call(1, packet, None), 6.0)
        proc.results = {"RESULT": 0}
        packet.processors["TEST"] = proc
        self.assertEqual(c.call(2, packet, None), 0)
        proc.results = {}
        packet.processors["TEST"] = proc
        # TODO: We could maybe rescue this but I don't want to hide typos
        with self.assertRaisesRegex(KeyError, "RESULT"):
            self.assertEqual(c.call(2, packet, None), 0)

    def test_returns_the_equation(self):
        self.assertEqual(
            str(ProcessorConversion("TEST1", "TEST2", "FLOAT", "64", "128")),
            "ProcessorConversion TEST1 TEST2",
        )

    def test_as_json_creates_a_reproducible_format(self):
        pc = ProcessorConversion('TEST1', 'TEST2', 'FLOAT', '64', '128')
        json = pc.as_json()
        self.assertEqual(json['class'], "ProcessorConversion")
        self.assertEqual(json['converted_type'], "FLOAT")
        self.assertEqual(json['converted_bit_size'], 64)
        self.assertEqual(json['converted_array_size'], 128)
        self.assertEqual(json['params'], ['TEST1', 'TEST2', "FLOAT", 64, 128])
        new_pc = ProcessorConversion(*json['params'])
        packet = Packet("tgt", "pkt")
        packet.append_item('ITEM1', 64, "FLOAT")
        proc = Processor()
        proc.results = {"TEST2": 6.0}
        packet.processors['TEST1'] = proc
        self.assertEqual(pc.call(1, packet, None), new_pc.call(1, packet, None))
