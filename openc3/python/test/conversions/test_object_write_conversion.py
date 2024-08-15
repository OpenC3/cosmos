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
from openc3.conversions.object_write_conversion import ObjectWriteConversion


class TestObjectWriteConversion(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_takes_cmd_tlm_target_name_packet_name(self):
        owc = ObjectWriteConversion("TLM", "inst", "HEALTH_STATUS")
        self.assertEqual(owc.cmd_or_tlm, "TLM")
        self.assertEqual(owc.target_name, "INST")
        self.assertEqual(owc.packet_name, "HEALTH_STATUS")
        self.assertEqual(owc.converted_type, "OBJECT")
        self.assertEqual(owc.converted_bit_size, 0)

    def test_complains_about_invalid_cmd_tlm(self):
        with self.assertRaisesRegex(AttributeError, f"Unknown type:OTHER"):
            ObjectWriteConversion("OTHER", "TGT", "PKT")

    def test_writes_the_cmd_packet_and_returns_a_raw_block(self):
        values = {}
        values["PKTID"] = 5
        values["CCSDSSEQCNT"] = 10

        # Make the same writes to a stand alone packet
        pkt = System.commands.packet("INST", "ABORT")
        pkt.write("PKTID", 5)
        pkt.write("CCSDSSEQCNT", 10)

        owc = ObjectWriteConversion("CMD", "INST", "ABORT")
        result = owc.call(values, pkt, pkt.buffer)
        self.assertTrue(isinstance(result, bytearray))
        self.assertEqual(result, pkt.buffer)

    def test_fills_the_tlm_packet_and_returns_a_hash_of_the_converted_values(self):
        values = {}
        values["CCSDSSEQCNT"] = 11
        values["VALUE0"] = 1
        values["VALUE2"] = 1
        values["VALUE4"] = 1

        # Make the same writes to a stand alone packet
        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.write("CCSDSSEQCNT", 11)
        pkt.write("VALUE0", 1)
        pkt.write("VALUE2", 1)
        pkt.write("VALUE4", 1)

        owc = ObjectWriteConversion("TLM", "INST", "PARAMS")
        result = owc.call(values, pkt, pkt.buffer)
        self.assertTrue(isinstance(result, bytearray))
        self.assertEqual(result, pkt.buffer)

    def test_returns_the_parameters(self):
        owc = ObjectWriteConversion("TLM", "INST", "PARAMS")
        self.assertEqual(f"{owc}", "ObjectWriteConversion TLM INST PARAMS")

    def test_returns_a_read_config_snippet(self):
        owc = ObjectWriteConversion("TLM", "INST", "PARAMS").to_config("WRITE").strip()
        self.assertEqual(owc, "WRITE_CONVERSION openc3/conversions/object_write_conversion.py TLM INST PARAMS")

    def test_creates_a_reproducable_format(self):
        owc = ObjectWriteConversion("TLM", "INST", "PARAMS")
        json = owc.as_json()
        self.assertEqual(json["class"], "ObjectWriteConversion")
        self.assertEqual(json["converted_type"], "OBJECT")
        self.assertEqual(json["converted_bit_size"], 0)
        self.assertEqual(json["cmd_or_tlm"], "TLM")
        self.assertEqual(json["target_name"], "INST")
        self.assertEqual(json["packet_name"], "PARAMS")
