# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

import unittest
import unittest.mock
from test.test_helper import BucketMock, mock_redis, setup_system, capture_io
from unittest.mock import patch
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.models.microservice_model import MicroserviceModel
from openc3.utilities.store import Store


class TestTargetModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_the_specified_model(self):
        model = TargetModel(folder_name="TEST", name="TEST2", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="SPEC", name="SPEC", scope="DEFAULT")
        model.create()
        target = TargetModel.get(name="TEST2", scope="DEFAULT")
        self.assertEqual(target["name"], "TEST2")

    def test_returns_all_model_names(self):
        model = TargetModel(folder_name="TEST", name="TEST", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="SPEC", name="SPEC", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="OTHER", name="OTHER", scope="OTHER")
        model.create()
        names = TargetModel.names(scope="DEFAULT")
        self.assertIn("TEST", names)
        self.assertIn("SPEC", names)
        names = TargetModel.names(scope="OTHER")
        self.assertIn("OTHER", names)

    def test_returns_all_the_parsed_targets(self):
        model = TargetModel(folder_name="TEST", name="TEST", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="SPEC", name="SPEC", scope="DEFAULT")
        model.create()
        all_targs = TargetModel.all(scope="DEFAULT")
        self.assertIn("TEST", all_targs.keys())
        self.assertIn("SPEC", all_targs.keys())


class TestTargetModelPackets(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="EMPTY", name="EMPTY", scope="DEFAULT")
        model.create()

    def test_set_packet(self):
        pkts = TargetModel.packets("INST", type="TLM", scope="DEFAULT")
        TargetModel.set_packet("INST", "ADCS", pkts[1], type="TLM", scope="DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER for INST ADCS"):
            TargetModel.set_packet("INST", "ADCS", pkts[0], type="OTHER", scope="DEFAULT")
        for stdout in capture_io():
            with self.assertRaises(TypeError):
                TargetModel.set_packet("INST", "HEALTH_STATUS", set("data"), type="TLM", scope="DEFAULT")
            self.assertIn(
                "Invalid text present in INST HEALTH_STATUS tlm packet",
                stdout.getvalue(),
            )

    def test_calls_limits_groups(self):
        lgs = TargetModel.limits_groups(scope="DEFAULT")
        self.assertIsInstance(lgs, dict)

    def test_gets_item_to_packet_map_from_cache(self):
        itpm = TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        self.assertIsInstance(itpm, dict)
        self.assertIsInstance(itpm["CCSDSVER"], list)
        self.assertEqual(itpm["CCSDSVER"], ["HEALTH_STATUS", "ADCS", "PARAMS", "IMAGE", "MECH", "HIDDEN"])
        # Copy cache
        cache = dict(TargetModel.item_map_cache)
        TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        # Verify the cache time doesn't change
        self.assertEqual(cache["INST"][0], (cache["INST"][0]))

    def test_gets_item_to_packet_map_on_an_invalid_cache(self):
        TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        # Copy cache
        cache = dict(TargetModel.item_map_cache)
        timeout = TargetModel.ITEM_MAP_CACHE_TIMEOUT
        TargetModel.ITEM_MAP_CACHE_TIMEOUT = 0
        TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        # Verify cached time was updated
        self.assertLess(cache["INST"][0], TargetModel.item_map_cache["INST"][0])
        TargetModel.ITEM_MAP_CACHE_TIMEOUT = timeout

    def test_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER for INST"):
            TargetModel.packets("INST", type="OTHER", scope="DEFAULT")

    def test_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, "Target 'NOPE' does not exist"):
            TargetModel.packets("NOPE", type="TLM", scope="DEFAULT")

    def test_returns_all_telemetry_packets(self):
        pkts = TargetModel.packets("INST", type="TLM", scope="DEFAULT")
        # Verify result is Array of packet Hashes
        self.assertIsInstance(pkts, list)
        names = []
        for pkt in pkts:
            self.assertIsInstance(pkt, dict)
            self.assertEqual(pkt["target_name"], "INST")
            names.append(pkt["packet_name"])
        names.sort()
        self.assertEqual(["ADCS", "HEALTH_STATUS", "HIDDEN", "IMAGE", "MECH", "PARAMS"], names)

    def test_returns_empty_array_for_no_telemetry_packets(self):
        pkts = TargetModel.packets("EMPTY", type="TLM", scope="DEFAULT")
        # Verify result is Array of packet Hashes
        self.assertIsInstance(pkts, list)
        self.assertEqual(len(pkts), 0)

    def test_returns_packet_hash_if_the_command_exists(self):
        pkts = TargetModel.packets("INST", type="CMD", scope="DEFAULT")
        self.assertIsInstance(pkts, list)
        names = []
        for pkt in pkts:
            self.assertIsInstance(pkt, dict)
            self.assertEqual(pkt["target_name"], "INST")
            self.assertIsInstance(pkt["items"], list)
            names.append(pkt["packet_name"])
        self.assertIn("ABORT", names)
        self.assertIn("COLLECT", names)
        self.assertIn("CLEAR", names)

    def test_returns_empty_array_for_no_command_packets(self):
        pkts = TargetModel.packets("EMPTY", type="CMD", scope="DEFAULT")
        # Verify result is Array of packet Hashes
        self.assertIsInstance(pkts, list)
        self.assertEqual(len(pkts), 0)


class TestTargetModelPacket(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

    def test_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER"):
            TargetModel.packet("INST", "HEALTH_STATUS", type="OTHER", scope="DEFAULT")

    def test_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet("BLAH", "HEALTH_STATUS", type="TLM", scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            TargetModel.packet("INST", "BLAH", type="TLM", scope="DEFAULT")

    def test_returns_packet_hash_if_the_telemetry_exists(self):
        pkt = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(pkt["target_name"], "INST")
        self.assertEqual(pkt["packet_name"], "HEALTH_STATUS")

    def test_returns_packet_hash_if_the_command_exists(self):
        pkt = TargetModel.packet("INST", "ABORT", type="CMD", scope="DEFAULT")
        self.assertEqual(pkt["target_name"], "INST")
        self.assertEqual(pkt["packet_name"], "ABORT")


class TestTargetModelPacketItem(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

    def test_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER"):
            TargetModel.packet_item("INST", "HEALTH_STATUS", "CCSDSVER", type="OTHER", scope="DEFAULT")

    def test_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet_item("BLAH", "HEALTH_STATUS", "CCSDSVER", scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            TargetModel.packet_item("INST", "BLAH", "CCSDSVER", scope="DEFAULT")

    def test_raises_for_a_non_existent_item(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            TargetModel.packet_item("INST", "HEALTH_STATUS", "BLAH", scope="DEFAULT")

    def test_returns_item_hash_if_the_telemetry_item_exists(self):
        item = TargetModel.packet_item("INST", "HEALTH_STATUS", "CCSDSVER", scope="DEFAULT")
        self.assertEqual(item["name"], "CCSDSVER")
        self.assertEqual(item["bit_offset"], 0)

    def test_returns_item_hash_if_the_command_item_exists(self):
        item = TargetModel.packet_item("INST", "ABORT", "CCSDSVER", type="CMD", scope="DEFAULT")
        self.assertEqual(item["name"], "CCSDSVER")
        self.assertEqual(item["bit_offset"], 0)


class TestTargetModelPacketItems(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

    def test_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER"):
            TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER"], type="OTHER", scope="DEFAULT")

    def test_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet_items("BLAH", "HEALTH_STATUS", ["CCSDSVER"], scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            TargetModel.packet_items("INST", "BLAH", ["CCSDSVER"], scope="DEFAULT")

    def test_raises_for_a_non_existent_item(self):
        with self.assertRaisesRegex(RuntimeError, "Item\\(s\\) 'INST HEALTH_STATUS BLAH' does not exist"):
            TargetModel.packet_items("INST", "HEALTH_STATUS", ["BLAH"], scope="DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "Item\\(s\\) 'INST HEALTH_STATUS BLAH' does not exist"):
            TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER", "BLAH"], scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError,
            "Item\\(s\\) 'INST HEALTH_STATUS (BLAH|NOPE)', 'INST HEALTH_STATUS (BLAH|NOPE)' does not exist",
        ):
            TargetModel.packet_items("INST", "HEALTH_STATUS", ["BLAH", "NOPE"], scope="DEFAULT")

    def test_returns_item_hash_array_if_the_telemetry_items_exists(self):
        items = TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER", "CCSDSTYPE"], scope="DEFAULT")
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["name"], "CCSDSVER")
        self.assertEqual(items[0]["bit_offset"], 0)
        self.assertEqual(items[1]["name"], "CCSDSTYPE")

    def test_returns_item_hash_array_if_the_command_items_exists(self):
        items = TargetModel.packet_items("INST", "ABORT", ["CCSDSVER", "CCSDSTYPE"], type="CMD", scope="DEFAULT")
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["name"], "CCSDSVER")
        self.assertEqual(items[0]["bit_offset"], 0)
        self.assertEqual(items[1]["name"], "CCSDSTYPE")


class TestTargetModelDynamic(unittest.TestCase):
    def setUp(self):
        self.scope = "DEFAULT"
        self.target = "INST"
        mock_redis(self)
        setup_system()
        self.model = TargetModel(folder_name=self.target, name="INST", scope=self.scope)
        self.model.create()
        self.mock_s3 = BucketMock.getClient()
        self.mock_s3.clear()
        self.patcher = patch("openc3.models.target_model.Bucket", BucketMock)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    def test_adds_new_commands(self):
        packet = Packet("INST", "NEW_CMD")
        cmd_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__COMMANDLOG__INST", scope=self.scope)
        cmd_log_model.create()
        decom_cmd_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__DECOMCMDLOG__INST", scope=self.scope)
        decom_cmd_log_model.create()

        pkts = Store.hgetall(f"{self.scope}__openc3cmd__{self.target}")
        self.assertNotIn(b"NEW_CMD", pkts.keys())
        self.assertIn(b"ABORT", pkts.keys())

        self.model.dynamic_update([packet], "COMMAND")
        self.assertIn("DEFAULT/targets_modified/INST/cmd_tlm/dynamic_tlm.txt", self.mock_s3.files())

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall(f"{self.scope}__openc3cmd__{self.target}")
        self.assertIn(b"NEW_CMD", pkts.keys())
        self.assertIn(b"ABORT", pkts.keys())
        model = MicroserviceModel.get_model(name="DEFAULT__COMMANDLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__COMMAND__{INST}__NEW_CMD", model.topics)
        model = MicroserviceModel.get_model(name="DEFAULT__DECOMCMDLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__DECOMCMD__{INST}__NEW_CMD", model.topics)

    def test_adds_new_telemetry(self):
        packet = Packet("INST", "NEW_TLM")
        pkt_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__PACKETLOG__INST", scope=self.scope)
        pkt_log_model.create()
        decom_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__DECOMLOG__INST", scope=self.scope)
        decom_log_model.create()
        decom_model = MicroserviceModel(folder_name="INST", name="DEFAULT__DECOM__INST", scope=self.scope)
        decom_model.create()

        pkts = Store.hgetall(f"{self.scope}__openc3tlm__{self.target}")
        self.assertNotIn(b"NEW_TLM", pkts.keys())
        self.assertIn(b"HEALTH_STATUS", pkts.keys())

        self.model.dynamic_update([packet], "TELEMETRY")
        self.assertIn("DEFAULT/targets_modified/INST/cmd_tlm/dynamic_tlm.txt", self.mock_s3.files())

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall(f"{self.scope}__openc3tlm__{self.target}")
        self.assertIn(b"NEW_TLM", pkts.keys())
        self.assertIn(b"HEALTH_STATUS", pkts.keys())
        model = MicroserviceModel.get_model(name="DEFAULT__PACKETLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__TELEMETRY__{INST}__NEW_TLM", model.topics)
        model = MicroserviceModel.get_model(name="DEFAULT__DECOMLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__DECOM__{INST}__NEW_TLM", model.topics)
        model = MicroserviceModel.get_model(name="DEFAULT__DECOM__INST", scope=self.scope)
        self.assertIn("DEFAULT__TELEMETRY__{INST}__NEW_TLM", model.topics)
