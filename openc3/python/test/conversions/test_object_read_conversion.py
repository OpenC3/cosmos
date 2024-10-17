# Copyright 2024 OpenC3, Inc.
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
from openc3.conversions.object_read_conversion import ObjectReadConversion


class TestObjectReadConversion(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_takes_cmd_tlm_target_name_packet_name(self):
        orc = ObjectReadConversion("TLM", "inst", "HEALTH_STATUS")
        self.assertEqual(orc.cmd_or_tlm, "TLM")
        self.assertEqual(orc.target_name, "INST")
        self.assertEqual(orc.packet_name, "HEALTH_STATUS")
        self.assertEqual(orc.converted_type, "OBJECT")
        self.assertEqual(orc.converted_bit_size, 0)

    def test_complains_about_invalid_cmd_tlm(self):
        with self.assertRaisesRegex(AttributeError, "Unknown type:OTHER"):
            ObjectReadConversion("OTHER", "TGT", "PKT")

    def test_fills_the_cmd_packet_and_returns_a_hash_of_the_converted_values(self):
        orc = ObjectReadConversion("CMD", "INST", "ABORT")
        pkt = System.commands.packet("INST", "ABORT")
        pkt.write("PKTID", 5)
        result = orc.call(pkt.buffer, pkt, pkt.buffer)
        self.assertTrue(isinstance(result, dict))
        self.assertEqual(result["CCSDSVER"], 0)
        self.assertEqual(result["PKTID"], 5)

    def test_fills_the_tlm_packet_and_returns_a_hash_of_the_converted_values(self):
        orc = ObjectReadConversion("TLM", "INST", "PARAMS")
        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.write("VALUE0", 1)
        pkt.write("VALUE2", 1)
        pkt.write("VALUE4", 1)
        result = orc.call(pkt.buffer, pkt, pkt.buffer)
        self.assertTrue(isinstance(result, dict))
        self.assertEqual(result["CCSDSVER"], 0)
        self.assertEqual(result["VALUE0"], "BAD")
        self.assertEqual(result["VALUE1"], "GOOD")
        self.assertEqual(result["VALUE2"], "BAD")
        self.assertEqual(result["VALUE3"], "GOOD")
        self.assertEqual(result["VALUE4"], "BAD")

    def test_returns_the_parameters(self):
        orc = ObjectReadConversion("TLM", "INST", "PARAMS")
        self.assertEqual(f"{orc}", "ObjectReadConversion TLM INST PARAMS")

    def test_returns_a_read_config_snippet(self):
        orc = ObjectReadConversion("TLM", "INST", "PARAMS").to_config("READ").strip()
        self.assertEqual(orc, "READ_CONVERSION openc3/conversions/object_read_conversion.py TLM INST PARAMS")

    def test_creates_a_reproducable_format(self):
        orc = ObjectReadConversion("TLM", "INST", "PARAMS")
        json = orc.as_json()
        self.assertEqual(json["class"], "ObjectReadConversion")
        self.assertEqual(json["converted_type"], "OBJECT")
        self.assertEqual(json["converted_bit_size"], 0)
        self.assertEqual(json["params"], ["TLM", "INST", "PARAMS"])
        new_orc = ObjectReadConversion(*json["params"])
        self.assertEqual(orc.converted_type, new_orc.converted_type)
        self.assertEqual(orc.converted_bit_size, new_orc.converted_bit_size)
        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.write("VALUE0", 1)
        pkt.write("VALUE2", 1)
        pkt.write("VALUE4", 1)
        self.assertEqual(orc.call(pkt.buffer, pkt, pkt.buffer), new_orc.call(pkt.buffer, pkt, pkt.buffer))
