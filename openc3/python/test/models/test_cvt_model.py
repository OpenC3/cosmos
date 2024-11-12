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

import time
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.conversions.generic_conversion import GenericConversion


class TestCvtModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        CvtModel.packet_cache = {}
        CvtModel.override_cache = {}

    def update_temp1(self, rxtime=None):
        json_hash = {}
        json_hash["TEMP1"] = 1
        json_hash["TEMP1__C"] = 2
        json_hash["TEMP1__F"] = "2.00"
        json_hash["TEMP1__U"] = "2.00 C"
        json_hash["TEMP1__L"] = "GREEN"
        if rxtime is None:
            rxtime = time.time()
        json_hash["RECEIVED_TIMESECONDS"] = rxtime
        CvtModel.set(json_hash, target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        hash = CvtModel.get(target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        self.assertEqual(json_hash, hash)

    def check_temp1(self):
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            1,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            2,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "2.00",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "2.00 C",
        )

    def test_sets_multiple_values_in_the_cvt(self):
        self.update_temp1()
        self.check_temp1()

    def test_decoms_and_sets(self):
        packet = Packet("TGT", "PKT", "BIG_ENDIAN", "packet", b"\x01\x02\x00\x01\x02\x03\x04")
        packet.append_item("ary", 8, "UINT", 16)
        i = packet.get_item("ARY")
        i.read_conversion = GenericConversion("value * 2")
        i.format_string = "0x%x"
        i.units = "V"
        packet.append_item("block", 40, "BLOCK")

        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(
            json_hash,
            packet.target_name,
            packet.packet_name,
            scope="DEFAULT",
        )

        self.assertEqual(CvtModel.get_item("TGT", "PKT", "ARY", type="RAW", scope="DEFAULT"), [1, 2])
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "ARY", type="CONVERTED", scope="DEFAULT"),
            [2, 4],
        )
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "ARY", type="FORMATTED", scope="DEFAULT"),
            "['0x2', '0x4']",
        )
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "ARY", type="WITH_UNITS", scope="DEFAULT"),
            "['0x2 V', '0x4 V']",
        )
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "BLOCK", type="RAW", scope="DEFAULT"),
            b"\x00\x01\x02\x03\x04",
        )

    def test_deletes_a_target_packet_from_the_cvt(self):
        self.update_temp1()
        self.assertIn(b"HEALTH_STATUS", Store.hkeys("DEFAULT__tlm__INST"))
        CvtModel.delete(target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        self.assertNotIn(b"HEALTH_STATUS", Store.hkeys("DEFAULT__tlm__INST"))

    def test_raises_for_an_unknown_type(self):
        self.update_temp1()
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'OTHER'"):
            CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="OTHER", scope="DEFAULT")

    def test_temporarily_sets_a_single_value_in_the_cvt(self):
        self.update_temp1()

        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="RAW", scope="DEFAULT")
        # Verify the :RAW value changed
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            0,
        )
        # Verify none of the other values change
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            2,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "2.00",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "2.00 C",
        )

        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="CONVERTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            0,
        )
        # Even thought we set 0 (Integer) we should get back a string "0"
        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="FORMATTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        # Even thought we set 0 (Integer) we should get back a string "0"
        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="WITH_UNITS", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
        )

        # Simulate TEMP1 being updated by a new packet
        self.update_temp1()
        # Verify we're all back to normal
        self.check_temp1()

    def test_temporarily_sets_all_values_in_the_cvt(self):
        self.update_temp1()

        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type="ALL", scope="DEFAULT")
        # Verify all values changed
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
        )

        # Simulate TEMP1 being updated by a new packet
        self.update_temp1()
        # Verify we're all back to normal
        self.check_temp1()

    def test_get_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'OTHER'"):
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="OTHER", scope="DEFAULT")

    def test_falls_down_to_the_next_type_value_if_the_requested_type_doesnt_exist(self):
        json_hash = {}
        # TEMP2 is RAW, CONVERTED, FORMATTED only
        json_hash["TEMP2"] = 3  # Values must be JSON encoded
        json_hash["TEMP2__C"] = 4
        json_hash["TEMP2__F"] = "4.00"
        # TEMP3 is RAW, CONVERTED only
        json_hash["TEMP3"] = 5  # Values must be JSON encoded
        json_hash["TEMP3__C"] = 6
        # TEMP3 is RAW only
        json_hash["TEMP4"] = 7  # Values must be JSON encoded
        CvtModel.set(json_hash, target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")

        # Verify TEMP2
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type="RAW", scope="DEFAULT"),
            3,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type="CONVERTED", scope="DEFAULT"),
            4,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type="FORMATTED", scope="DEFAULT"),
            "4.00",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type="WITH_UNITS", scope="DEFAULT"),
            "4.00",
        )  # Same as FORMATTED
        # Verify TEMP3
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type="RAW", scope="DEFAULT"),
            5,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type="CONVERTED", scope="DEFAULT"),
            6,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type="FORMATTED", scope="DEFAULT"),
            "6",
        )  # Same as CONVERTED but String
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type="WITH_UNITS", scope="DEFAULT"),
            "6",
        )  # Same as CONVERTED but String
        # Verify TEMP4
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type="RAW", scope="DEFAULT"),
            7,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type="CONVERTED", scope="DEFAULT"),
            7,
        )  # Same as RAW
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type="FORMATTED", scope="DEFAULT"),
            "7",
        )  # Same as RAW but String
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type="WITH_UNITS", scope="DEFAULT"),
            "7",
        )  # Same as RAW but String

    def test_gettlm_returns_an_empty_array_with_no_values(self):
        self.assertEqual(CvtModel.get_tlm_values([]), ([]))

    def test_gettlm_raises_on_invalid_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'NOPE BLAH' does not exist"):
            CvtModel.get_tlm_values([["NOPE", "BLAH", "TEMP1", "RAW"]])

    def test_gettlm_raises_on_invalid_items(self):
        self.update_temp1()
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS NOPE' does not exist"):
            CvtModel.get_tlm_values([["INST", "HEALTH_STATUS", "NOPE", "RAW"]])

    def test_gettlm_raises_on_invalid_types(self):
        self.update_temp1()
        with self.assertRaisesRegex(ValueError, "Unknown value type 'NOPE'"):
            CvtModel.get_tlm_values([["INST", "HEALTH_STATUS", "TEMP1", "NOPE"]])

    def test_gets_different_value_types_from_the_cvt(self):
        self.update_temp1()
        values = [
            ["INST", "HEALTH_STATUS", "TEMP1", "RAW"],
            ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED"],
            ["INST", "HEALTH_STATUS", "TEMP1", "FORMATTED"],
            ["INST", "HEALTH_STATUS", "TEMP1", "WITH_UNITS"],
        ]
        result = CvtModel.get_tlm_values(values)
        self.assertEqual(result[0][0], 1)
        self.assertEqual(result[0][1], "GREEN")
        self.assertEqual(result[1][0], 2)
        self.assertEqual(result[1][1], "GREEN")
        self.assertEqual(result[2][0], "2.00")
        self.assertEqual(result[2][1], "GREEN")
        self.assertEqual(result[3][0], "2.00 C")
        self.assertEqual(result[3][1], "GREEN")

    def test_marks_values_stale(self):
        self.update_temp1(rxtime=(time.time() - 10))
        values = [["INST", "HEALTH_STATUS", "TEMP1", "RAW"]]
        result = CvtModel.get_tlm_values(values, stale_time=9)
        self.assertEqual(result[0][0], 1)
        self.assertEqual(result[0][1], "STALE")
        result = CvtModel.get_tlm_values(values, stale_time=11)
        self.assertEqual(result[0][0], 1)
        self.assertEqual(result[0][1], "GREEN")

    def test_returns_overridden_values(self):
        self.update_temp1()
        json_hash = {}
        json_hash["DATA"] = "\x00\x01\x02"
        json_hash["RECEIVED_TIMESECONDS"] = time.time()
        CvtModel.set(json_hash, target_name="INST", packet_name="DATA", scope="DEFAULT")
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="RAW", scope="DEFAULT")
        values = [
            ["INST", "HEALTH_STATUS", "TEMP1", "RAW"],
            ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED"],
            ["INST", "DATA", "DATA", "RAW"],
        ]
        result = CvtModel.get_tlm_values(values)
        self.assertEqual(result[0][0], 0)
        self.assertEqual(result[1][0], 2)
        self.assertEqual(result[1][1], "GREEN")
        self.assertEqual(result[2][0], "\x00\x01\x02")
        self.assertIsNone(result[2][1])

    def test_override_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'OTHER'"):
            CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="OTHER", scope="DEFAULT")

    def test_overrides_a_value_in_the_cvt(self):
        self.update_temp1()
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            1,
        )
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="RAW", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            2,
        )
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="CONVERTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "2.00",
        )
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="FORMATTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "2.00 C",
        )
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="WITH_UNITS", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
        )
        # Simulate TEMP1 being updated by a new packet
        self.update_temp1()
        # Verify we're still over-ridden
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            0,
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="ALL", scope="DEFAULT")

    def test_overrides_all_value_in_the_cvt(self):
        self.update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, scope="DEFAULT")  # default is ALL
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="ALL", scope="DEFAULT")

    def test_normalize_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'OTHER'"):
            CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="OTHER", scope="DEFAULT")

    def test_does_nothing_if_no_value_overriden(self):
        self.update_temp1()
        cache_copy = CvtModel.override_cache.copy()
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT")
        self.assertEqual(cache_copy, CvtModel.override_cache)
        self.check_temp1()

    def test_normalizes_an_override_value_type_in_the_cvt(self):
        self.update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="ALL", scope="DEFAULT")
        # This is an implementation detail but it matters that we clear it once all overrides are clear
        self.assertIsNotNone(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS"))

        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            1,
        )
        # The rest are still overridden
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            0,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
        )

        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "2.00 C",
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            2,
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "2.00",
        )
        # Once the last override is gone the key should be cleared
        self.assertIsNone(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS"))

    def test_normalizes_every_value_type_in_the_cvt(self):
        self.update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 10, type="ALL", scope="DEFAULT")
        # This is an implementation detail but it matters that we clear it once all overrides are clear
        self.assertIsNotNone(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS"))
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"),
            10,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"),
            10,
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "10",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "10",
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="ALL", scope="DEFAULT")
        # Once the last override is gone the key should be cleared
        self.assertIsNone(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS"))
        self.check_temp1()

    def test_returns_all_overrides_the_cvt(self):
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="SYSTEM", name="SYSTEM", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="EMPTY", name="EMPTY", scope="DEFAULT")
        model.create()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="RAW", scope="DEFAULT")
        # Override an individual type
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP2", 1, type="FORMATTED", scope="DEFAULT")
        # Since we're overriding all the previous one will also be overridden
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP2", 2, type="ALL", scope="DEFAULT")
        CvtModel.override("INST", "ADCS", "POSX", 3, type="ALL", scope="DEFAULT")
        CvtModel.override(
            "SYSTEM",
            "META",
            "OPERATOR_NAME",
            "JASON",
            type="CONVERTED",
            scope="DEFAULT",
        )
        overrides = CvtModel.overrides()
        self.assertEqual(len(overrides), 10)
        self.assertEqual(
            overrides[0],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP1",
                    "value_type": "RAW",
                    "value": 0,
                }
            ),
        )
        # FORMATTED is first because we initially did an override to 1
        self.assertEqual(
            overrides[1],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP2",
                    "value_type": "FORMATTED",
                    "value": "2",
                }
            ),
        )
        self.assertEqual(
            overrides[2],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP2",
                    "value_type": "RAW",
                    "value": 2,
                }
            ),
        )
        self.assertEqual(
            overrides[3],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP2",
                    "value_type": "CONVERTED",
                    "value": 2,
                }
            ),
        )
        self.assertEqual(
            overrides[4],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP2",
                    "value_type": "WITH_UNITS",
                    "value": "2",
                }
            ),
        )
        self.assertEqual(
            overrides[5],
            (
                {
                    "target_name": "INST",
                    "packet_name": "ADCS",
                    "item_name": "POSX",
                    "value_type": "RAW",
                    "value": 3,
                }
            ),
        )
        self.assertEqual(
            overrides[6],
            (
                {
                    "target_name": "INST",
                    "packet_name": "ADCS",
                    "item_name": "POSX",
                    "value_type": "CONVERTED",
                    "value": 3,
                }
            ),
        )
        self.assertEqual(
            overrides[7],
            (
                {
                    "target_name": "INST",
                    "packet_name": "ADCS",
                    "item_name": "POSX",
                    "value_type": "FORMATTED",
                    "value": "3",
                }
            ),
        )
        self.assertEqual(
            overrides[8],
            (
                {
                    "target_name": "INST",
                    "packet_name": "ADCS",
                    "item_name": "POSX",
                    "value_type": "WITH_UNITS",
                    "value": "3",
                }
            ),
        )
        self.assertEqual(
            overrides[9],
            (
                {
                    "target_name": "SYSTEM",
                    "packet_name": "META",
                    "item_name": "OPERATOR_NAME",
                    "value_type": "CONVERTED",
                    "value": "JASON",
                }
            ),
        )
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="ALL", scope="DEFAULT")
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP2", type="ALL", scope="DEFAULT")
        CvtModel.normalize("INST", "ADCS", "POSX", type="ALL", scope="DEFAULT")
        CvtModel.normalize("SYSTEM", "META", "OPERATOR_NAME", type="ALL", scope="DEFAULT")
