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
import time
import unittest
from unittest.mock import *

from openc3.conversions.generic_conversion import GenericConversion
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.utilities.store import Store
from test.test_helper import *


def patch_caches(test_case):
    """Give the test empty CvtModel caches and restore the originals afterwards"""
    for name in ("packet_cache", "override_cache"):
        patcher = patch.object(CvtModel, name, {})
        patcher.start()
        test_case.addCleanup(patcher.stop)


class TestCvtModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        patch_caches(self)

    def update_temp1(self, rxtime=None):
        json_hash = {}
        json_hash["TEMP1"] = 1
        json_hash["TEMP1__C"] = 2
        json_hash["TEMP1__F"] = "2.00 C"
        json_hash["TEMP1__L"] = "GREEN"
        if rxtime is None:
            rxtime = time.time()
        json_hash["RECEIVED_TIMESECONDS"] = rxtime
        CvtModel.set(json_hash, target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        model = CvtModel.get(target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        self.assertEqual(json_hash, model)

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
            "2.00 C",
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
            "['0x2 V', '0x4 V']",
        )
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "ARY", type="WITH_UNITS", scope="DEFAULT"),
            "['0x2 V', '0x4 V']",
        )
        self.assertEqual(
            CvtModel.get_item("TGT", "PKT", "BLOCK", type="RAW", scope="DEFAULT"),
            b"\x00\x01\x02\x03\x04",
        )

    def test_build_json_from_packet_passes_include_limits_states(self):
        packet = Packet("TGT", "PKT", "BIG_ENDIAN", "packet", b"\x01\x02")
        item = packet.append_item("val", 16, "UINT")
        item.limits.state = "RED_HIGH"

        json_hash = CvtModel.build_json_from_packet(packet)
        self.assertEqual(json_hash["VAL__L"], "RED_HIGH")

        json_hash = CvtModel.build_json_from_packet(packet, include_limits_states=False)
        self.assertNotIn("VAL__L", json_hash)
        self.assertEqual(json_hash["VAL"], 0x0102)

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
            "2.00 C",
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
        with self.assertRaisesRegex(RuntimeError, "Packet 'NOPE BLAH' has no current values in CVT"):
            CvtModel.get_tlm_values([["NOPE", "BLAH", "TEMP1", "RAW"]])

    def test_gettlm_raises_on_invalid_items(self):
        self.update_temp1()
        with self.assertRaisesRegex(RuntimeError, r"Item 'INST HEALTH_STATUS NOPE' does not exist \(get_tlm_values\)"):
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
        self.assertEqual(result[2][0], "2.00 C")
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
            "2.00 C",
        )
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type="FORMATTED", scope="DEFAULT")
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED", scope="DEFAULT"),
            "0",
        )
        self.assertEqual(
            CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS", scope="DEFAULT"),
            "0",
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
            "2.00 C",
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
        self.assertEqual(len(overrides), 8)
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
                    "packet_name": "ADCS",
                    "item_name": "POSX",
                    "value_type": "RAW",
                    "value": 3,
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
                    "value_type": "CONVERTED",
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
                    "value_type": "FORMATTED",
                    "value": "3",
                }
            ),
        )
        self.assertEqual(
            overrides[7],
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

    def test_determine_latest_packet_for_item_works_if_not_received(self):
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()
        names = TargetModel.names(scope="DEFAULT")
        self.assertIn("INST", names)
        Store.set("DEFAULT__INST__item_to_packet_map", json.dumps({"PACKET_ID": ["PACKET1"]}))
        Store.hset("DEFAULT__tlm__INST", "PACKET1", json.dumps({"PACKET_TIMESECONDS": None}))
        packet_name = CvtModel.determine_latest_packet_for_item("INST", "PACKET_ID", scope="DEFAULT")
        self.assertNotEqual(packet_name, None)


# INST is installed on db_shard 1 while SYSTEM stays on db_shard 0. The current
# values and overrides of a target must live on its db_shard.
class TestCvtModelMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system(db_shards={"INST": 1})
        patch_caches(self)
        self.shard0 = shard_redis(0)
        self.shard1 = shard_redis(1)

    def test_set_and_get_use_the_target_db_shard(self):
        CvtModel.set({"TEMP1": 1}, target_name="INST", packet_name="HEALTH_STATUS", scope="DEFAULT")
        CvtModel.set({"TEMP2": 2}, target_name="INST", packet_name="ADCS", queued=True, scope="DEFAULT")
        CvtModel.set_json('{"TEMP3": 3}', {"TEMP3": 3}, target_name="INST", packet_name="PARAMS", scope="DEFAULT")
        CvtModel.set({"COUNT": 4}, target_name="SYSTEM", packet_name="LIMITS_CHANGE", scope="DEFAULT")
        self.assertEqual(json.loads(self.shard1.hget("DEFAULT__tlm__INST", "HEALTH_STATUS")), {"TEMP1": 1})
        self.assertEqual(json.loads(self.shard1.hget("DEFAULT__tlm__INST", "ADCS")), {"TEMP2": 2})
        self.assertEqual(json.loads(self.shard1.hget("DEFAULT__tlm__INST", "PARAMS")), {"TEMP3": 3})
        self.assertEqual(json.loads(self.shard0.hget("DEFAULT__tlm__SYSTEM", "LIMITS_CHANGE")), {"COUNT": 4})
        self.assertFalse(self.shard0.exists("DEFAULT__tlm__INST"))

        # Bypass the packet cache to read back from the store
        CvtModel.packet_cache.clear()
        self.assertEqual(CvtModel.get("INST", "HEALTH_STATUS", scope="DEFAULT"), {"TEMP1": 1})
        self.assertEqual(CvtModel.get("SYSTEM", "LIMITS_CHANGE", scope="DEFAULT"), {"COUNT": 4})

        CvtModel.delete("INST", "HEALTH_STATUS", scope="DEFAULT")
        self.assertIsNone(self.shard1.hget("DEFAULT__tlm__INST", "HEALTH_STATUS"))

    def test_set_item_and_get_item_use_the_target_db_shard(self):
        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 5, type="ALL", scope="DEFAULT")
        self.assertEqual(json.loads(self.shard1.hget("DEFAULT__tlm__INST", "HEALTH_STATUS"))["TEMP1__C"], 5)
        CvtModel.packet_cache.clear()
        self.assertEqual(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"), 5)

    def test_overrides_use_the_target_db_shard(self):
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 10, type="CONVERTED", scope="DEFAULT")
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP2", 20, type="CONVERTED", scope="DEFAULT")
        self.assertEqual(
            json.loads(self.shard1.hget("DEFAULT__override__INST", "HEALTH_STATUS")),
            {"TEMP1__C": 10, "TEMP2__C": 20},
        )
        self.assertFalse(self.shard0.exists("DEFAULT__override__INST"))

        CvtModel.override_cache.clear()
        self.assertEqual(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT"), 10)
        CvtModel.override_cache.clear()
        values = CvtModel.get_tlm_values([["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED"]], scope="DEFAULT")
        self.assertEqual(values[0][0], 10)
        overrides = CvtModel.overrides(scope="DEFAULT")
        self.assertEqual(sorted(override["item_name"] for override in overrides), ["TEMP1", "TEMP2"])

        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED", scope="DEFAULT")
        self.assertEqual(json.loads(self.shard1.hget("DEFAULT__override__INST", "HEALTH_STATUS")), {"TEMP2__C": 20})
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP2", type="CONVERTED", scope="DEFAULT")
        self.assertFalse(self.shard1.exists("DEFAULT__override__INST"))

    def test_get_tlm_values_reads_each_target_from_its_db_shard(self):
        now = time.time()
        self.shard1.hset("DEFAULT__tlm__INST", "HEALTH_STATUS", json.dumps({"TEMP1": 1, "RECEIVED_TIMESECONDS": now}))
        self.shard0.hset(
            "DEFAULT__tlm__SYSTEM", "LIMITS_CHANGE", json.dumps({"TARGET_NAME": "INST", "RECEIVED_TIMESECONDS": now})
        )
        values = CvtModel.get_tlm_values(
            [["INST", "HEALTH_STATUS", "TEMP1", "RAW"], ["SYSTEM", "LIMITS_CHANGE", "TARGET_NAME", "RAW"]],
            scope="DEFAULT",
        )
        self.assertEqual(values, [[1, None], ["INST", None]])
