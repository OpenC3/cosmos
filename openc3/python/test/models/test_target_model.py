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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

import json
import unittest
import unittest.mock
from unittest.mock import patch

from openc3.models.microservice_model import MicroserviceModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.system.system import System
from openc3.utilities.store import Store
from test.test_helper import BucketMock, capture_io, mock_redis, setup_system, shard_redis


class TestTargetModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        TargetModel.item_map_cache = {}

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

    def test_stored_limits_mode_defaults_to_process(self):
        model = TargetModel(folder_name="TEST", name="TEST", scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "PROCESS")

    def test_stored_limits_mode_accepts_valid_modes(self):
        for mode in ("PROCESS", "LOG", "DISABLE"):
            model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode=mode, scope="DEFAULT")
            self.assertEqual(model.stored_limits_mode, mode)

    def test_stored_limits_mode_uppercases_input(self):
        model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode="log", scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "LOG")
        model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode="disable", scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "DISABLE")

    def test_stored_limits_mode_falls_back_to_process_for_invalid(self):
        model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode="INVALID", scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "PROCESS")
        model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode="", scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "PROCESS")

    def test_stored_limits_mode_handles_none(self):
        model = TargetModel(folder_name="TEST", name="TEST", stored_limits_mode=None, scope="DEFAULT")
        self.assertEqual(model.stored_limits_mode, "PROCESS")

    def test_stored_limits_mode_round_trips_through_redis(self):
        # Simulate what Ruby's as_json stores in Redis (Python TargetModel doesn't
        # override as_json, so we manually store the full JSON as Ruby would)
        import json

        json_data = {
            "name": "TEST",
            "folder_name": "TEST",
            "updated_at": None,
            "plugin": None,
            "stored_limits_mode": "DISABLE",
        }
        Store.hset("DEFAULT__openc3_targets", "TEST", json.dumps(json_data))
        retrieved = TargetModel.get_model(name="TEST", scope="DEFAULT")
        self.assertEqual(retrieved.stored_limits_mode, "DISABLE")


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
        raised = False
        for stdout in capture_io():
            try:
                TargetModel.set_packet("INST", "HEALTH_STATUS", set("data"), type="TLM", scope="DEFAULT")
            except TypeError:
                raised = True
            self.assertIn(
                "Invalid text present in INST HEALTH_STATUS tlm packet",
                stdout.getvalue(),
            )
        self.assertTrue(raised, "Expected TypeError was not raised")

    def test_calls_limits_groups(self):
        lgs = TargetModel.limits_groups(scope="DEFAULT")
        self.assertIsInstance(lgs, dict)

    def test_gets_item_to_packet_map_from_cache(self):
        itpm = TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        self.assertIsInstance(itpm, dict)
        self.assertIsInstance(itpm["CCSDSVER"], list)
        self.assertEqual(
            itpm["CCSDSVER"],
            ["HEALTH_STATUS", "ADCS", "PARAMS", "IMAGE", "MECH", "HIDDEN"],
        )
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
        with self.assertRaisesRegex(RuntimeError, r"Target 'NOPE' does not exist.*\(TargetModel\)"):
            TargetModel.packets("NOPE", type="TLM", scope="DEFAULT")

    def test_packet_names_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER for INST"):
            TargetModel.packet_names("INST", type="OTHER", scope="DEFAULT")

    def test_packet_names_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, r"Target 'NOPE' does not exist.*\(TargetModel\)"):
            TargetModel.packet_names("NOPE", type="TLM", scope="DEFAULT")

    def test_packet_names_returns_sorted_packet_names(self):
        names = TargetModel.packet_names("INST", type="TLM", scope="DEFAULT")
        self.assertEqual(names, sorted(names))
        pkts = TargetModel.packets("INST", type="TLM", scope="DEFAULT")
        self.assertEqual(names, sorted(pkt["packet_name"] for pkt in pkts))

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
        # Clear packet cache before each test
        TargetModel.packet_cache = {}

    def test_raises_for_an_unknown_type(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type OTHER"):
            TargetModel.packet("INST", "HEALTH_STATUS", type="OTHER", scope="DEFAULT")

    def test_raises_for_a_non_existent_target(self):
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet("BLAH", "HEALTH_STATUS", type="TLM", scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'INST BLAH' does not exist"):
            TargetModel.packet("INST", "BLAH", type="TLM", scope="DEFAULT")

    def test_returns_packet_hash_if_the_telemetry_exists(self):
        pkt = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(pkt["target_name"], "INST")
        self.assertEqual(pkt["packet_name"], "HEALTH_STATUS")

    def test_returns_packet_hash_if_the_command_exists(self):
        pkt = TargetModel.packet("INST", "ABORT", type="CMD", scope="DEFAULT")
        self.assertEqual(pkt["target_name"], "INST")
        self.assertEqual(pkt["packet_name"], "ABORT")

    def test_caches_packet_lookups(self):
        # First call should populate cache
        pkt1 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)

        # Second call should hit cache and return same result
        pkt2 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)

        # Both should be equal
        self.assertEqual(pkt1, pkt2)

    def test_expires_cache_after_timeout(self):
        import time as time_module

        # First call populates cache
        pkt1 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)

        # Save the original timeout and set it to 0 to force expiration
        original_timeout = TargetModel.PACKET_CACHE_TIMEOUT
        TargetModel.PACKET_CACHE_TIMEOUT = 0

        try:
            # Wait a tiny bit to ensure cache is expired
            time_module.sleep(0.001)

            # Next call should miss cache due to expiration
            pkt2 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")

            # Still only one entry but cache time should have been updated
            self.assertEqual(len(TargetModel.packet_cache), 1)
            self.assertEqual(pkt1, pkt2)
        finally:
            # Restore timeout
            TargetModel.PACKET_CACHE_TIMEOUT = original_timeout

    def test_invalidates_cache_on_set_packet(self):
        # First call populates cache
        pkt1 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)

        # set_packet should invalidate the cache entry
        TargetModel.set_packet("INST", "HEALTH_STATUS", pkt1, type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 0)

        # Next packet() call should re-populate cache
        pkt2 = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)
        self.assertEqual(pkt1, pkt2)

    def test_caches_different_packet_types_separately(self):
        # Get TLM packet
        tlm_pkt = TargetModel.packet("INST", "HEALTH_STATUS", type="TLM", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 1)

        # Get CMD packet
        cmd_pkt = TargetModel.packet("INST", "ABORT", type="CMD", scope="DEFAULT")
        self.assertEqual(len(TargetModel.packet_cache), 2)

        # Verify different packets
        self.assertEqual(tlm_pkt["packet_name"], "HEALTH_STATUS")
        self.assertEqual(cmd_pkt["packet_name"], "ABORT")


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
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet_item("BLAH", "HEALTH_STATUS", "CCSDSVER", scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'INST BLAH' does not exist"):
            TargetModel.packet_item("INST", "BLAH", "CCSDSVER", scope="DEFAULT")

    def test_raises_for_a_non_existent_item(self):
        with self.assertRaisesRegex(RuntimeError, r"Item 'INST HEALTH_STATUS BLAH' does not exist \(TargetModel\)"):
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
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'BLAH HEALTH_STATUS' does not exist"):
            TargetModel.packet_items("BLAH", "HEALTH_STATUS", ["CCSDSVER"], scope="DEFAULT")

    def test_raises_for_a_non_existent_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Packet definition 'INST BLAH' does not exist"):
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
        self.mock_s3 = BucketMock.get_client()
        self.mock_s3.clear()
        self.patcher = patch("openc3.models.target_model.Bucket", BucketMock)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    def test_adds_new_commands(self):
        packet = Packet("INST", "NEW_CMD")
        cmd_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__COMMANDLOG__INST", scope=self.scope)
        cmd_log_model.create()

        pkts = Store.hgetall(f"{self.scope}__openc3cmd__{self.target}")
        self.assertNotIn(b"NEW_CMD", pkts.keys())
        self.assertIn(b"ABORT", pkts.keys())

        self.model.dynamic_update([packet], "COMMAND")
        self.assertIn(
            "DEFAULT/targets_modified/INST/cmd_tlm/dynamic_tlm.txt",
            self.mock_s3.files(),
        )

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall(f"{self.scope}__openc3cmd__{self.target}")
        self.assertIn(b"NEW_CMD", pkts.keys())
        self.assertIn(b"ABORT", pkts.keys())
        model = MicroserviceModel.get_model(name="DEFAULT__COMMANDLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__COMMAND__{INST}__NEW_CMD", model.topics)

    def test_adds_new_telemetry(self):
        packet = Packet("INST", "NEW_TLM")
        pkt_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__PACKETLOG__INST", scope=self.scope)
        pkt_log_model.create()
        decom_model = MicroserviceModel(folder_name="INST", name="DEFAULT__DECOM__INST", scope=self.scope)
        decom_model.create()

        pkts = Store.hgetall(f"{self.scope}__openc3tlm__{self.target}")
        self.assertNotIn(b"NEW_TLM", pkts.keys())
        self.assertIn(b"HEALTH_STATUS", pkts.keys())

        self.model.dynamic_update([packet], "TELEMETRY")
        self.assertIn(
            "DEFAULT/targets_modified/INST/cmd_tlm/dynamic_tlm.txt",
            self.mock_s3.files(),
        )

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall(f"{self.scope}__openc3tlm__{self.target}")
        self.assertIn(b"NEW_TLM", pkts.keys())
        self.assertIn(b"HEALTH_STATUS", pkts.keys())
        model = MicroserviceModel.get_model(name="DEFAULT__PACKETLOG__INST", scope=self.scope)
        self.assertIn("DEFAULT__TELEMETRY__{INST}__NEW_TLM", model.topics)
        model = MicroserviceModel.get_model(name="DEFAULT__DECOM__INST", scope=self.scope)
        self.assertIn("DEFAULT__TELEMETRY__{INST}__NEW_TLM", model.topics)

    def test_merges_new_hidden_commands_into_the_hidden_list(self):
        cmd_log_model = MicroserviceModel(folder_name="INST", name="DEFAULT__COMMANDLOG__INST", scope=self.scope)
        cmd_log_model.create()
        self.assertEqual(TargetModel.hidden_packet_names("INST", type="CMD", scope=self.scope), ["DISABLED"])

        packet = Packet("INST", "NEW_CMD")
        packet.hidden = True
        self.model.dynamic_update([packet], "COMMAND")
        self.assertEqual(TargetModel.hidden_packet_names("INST", type="CMD", scope=self.scope), ["DISABLED", "NEW_CMD"])

        packet.hidden = False
        self.model.dynamic_update([packet], "COMMAND")
        self.assertEqual(TargetModel.hidden_packet_names("INST", type="CMD", scope=self.scope), ["DISABLED"])


# INST is installed on db_shard 1 while SYSTEM and EMPTY stay on db_shard 0.
# Everything specific to a target must be read from and written to its db_shard.
class TestTargetModelMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system(db_shards={"INST": 1})
        TargetModel.item_map_cache = {}
        self.shard0 = shard_redis(0)
        self.shard1 = shard_redis(1)

    def test_reads_packets_from_the_target_db_shard(self):
        # setup_system only put the INST packets on db_shard 1
        self.assertFalse(self.shard0.exists("DEFAULT__openc3tlm__INST"))
        self.assertEqual(TargetModel.packet("INST", "HEALTH_STATUS", scope="DEFAULT")["packet_name"], "HEALTH_STATUS")
        self.assertEqual(TargetModel.packet("INST", "ABORT", type="CMD", scope="DEFAULT")["packet_name"], "ABORT")
        self.assertIn(
            "HEALTH_STATUS", [packet["packet_name"] for packet in TargetModel.packets("INST", scope="DEFAULT")]
        )
        self.assertIn("HEALTH_STATUS", TargetModel.packet_names("INST", scope="DEFAULT"))
        self.assertIn("ABORT", TargetModel.packet_names("INST", type="CMD", scope="DEFAULT"))
        # SYSTEM is still read from db_shard 0
        self.assertIn("LIMITS_CHANGE", TargetModel.packet_names("SYSTEM", scope="DEFAULT"))

    def test_hidden_packet_names_stores_the_list_on_the_target_db_shard(self):
        self.assertEqual(TargetModel.hidden_packet_names("INST", type="CMD", scope="DEFAULT"), ["DISABLED"])
        self.assertEqual(json.loads(self.shard1.get("DEFAULT__openc3cmd__INST__hidden")), ["DISABLED"])
        self.assertIsNone(self.shard0.get("DEFAULT__openc3cmd__INST__hidden"))

    def test_set_packet_writes_to_the_target_db_shard(self):
        TargetModel.set_packet("INST", "NEW", {"packet_name": "NEW"}, scope="DEFAULT")
        self.assertIsNotNone(self.shard1.hget("DEFAULT__openc3tlm__INST", "NEW"))
        self.assertFalse(self.shard0.exists("DEFAULT__openc3tlm__INST"))

    def test_all_item_names_builds_the_list_on_the_target_db_shard(self):
        items = TargetModel.all_item_names("INST", scope="DEFAULT")
        self.assertIn(b"TEMP1", items)
        self.assertIn(b"TEMP1", self.shard1.zrange("DEFAULT__openc3tlm__INST__allitems", 0, -1))
        self.assertFalse(self.shard0.exists("DEFAULT__openc3tlm__INST__allitems"))

    def test_item_to_packet_map_is_stored_on_the_target_db_shard(self):
        item_map = TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")
        self.assertEqual(item_map["TEMP1"], ["HEALTH_STATUS"])
        self.assertIsNotNone(self.shard1.get("DEFAULT__INST__item_to_packet_map"))
        self.assertIsNone(self.shard0.get("DEFAULT__INST__item_to_packet_map"))

    def test_counts_are_kept_on_the_target_db_shard(self):
        TargetModel.increment_telemetry_count("INST", "HEALTH_STATUS", 3, scope="DEFAULT")
        TargetModel.increment_telemetry_count("SYSTEM", "LIMITS_CHANGE", 4, scope="DEFAULT")
        TargetModel.increment_command_count("INST", "ABORT", 5, scope="DEFAULT")
        TargetModel.increment_command_count("SYSTEM", "STARTLOGGING", 6, scope="DEFAULT")
        self.assertEqual(self.shard1.hget("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS"), b"3")
        self.assertEqual(self.shard0.hget("DEFAULT__TELEMETRYCNTS__{SYSTEM}", "LIMITS_CHANGE"), b"4")
        self.assertEqual(self.shard1.hget("DEFAULT__COMMANDCNTS__{INST}", "ABORT"), b"5")
        self.assertEqual(self.shard0.hget("DEFAULT__COMMANDCNTS__{SYSTEM}", "STARTLOGGING"), b"6")
        self.assertFalse(self.shard0.exists("DEFAULT__TELEMETRYCNTS__{INST}"))
        self.assertFalse(self.shard0.exists("DEFAULT__COMMANDCNTS__{INST}"))

        self.assertEqual(TargetModel.get_telemetry_count("INST", "HEALTH_STATUS", scope="DEFAULT"), 3)
        self.assertEqual(TargetModel.get_all_telemetry_counts("INST", scope="DEFAULT"), {b"HEALTH_STATUS": b"3"})
        self.assertEqual(TargetModel.get_command_count("INST", "ABORT", scope="DEFAULT"), 5)
        self.assertEqual(TargetModel.get_all_command_counts("INST", scope="DEFAULT"), {b"ABORT": b"5"})
        # The bulk lookups query each db_shard and keep the requested order
        self.assertEqual(
            TargetModel.get_telemetry_counts(
                [["SYSTEM", "LIMITS_CHANGE"], ["INST", "HEALTH_STATUS"], ["INST", "ADCS"]], scope="DEFAULT"
            ),
            [4, 3, 0],
        )
        self.assertEqual(
            TargetModel.get_command_counts([["INST", "ABORT"], ["SYSTEM", "STARTLOGGING"]], scope="DEFAULT"),
            [5, 6],
        )

    def test_update_store_writes_to_the_model_db_shard(self):
        self.shard1.flushall()
        model = TargetModel(name="INST", db_shard=1, scope="DEFAULT")
        model.update_store_telemetry({"INST": System.telemetry.packets("INST")})
        model.update_store_commands({"INST": System.commands.packets("INST")})
        model.update_store_item_map()
        for key in [
            "DEFAULT__openc3tlm__INST",
            "DEFAULT__openc3tlm__INST__hidden",
            "DEFAULT__openc3tlm__INST__allitems",
            "DEFAULT__tlm__INST",
            "DEFAULT__openc3cmd__INST",
            "DEFAULT__openc3cmd__INST__hidden",
            "DEFAULT__INST__item_to_packet_map",
        ]:
            self.assertTrue(self.shard1.exists(key), key)
            self.assertFalse(self.shard0.exists(key), key)

    @patch("openc3.models.target_model.Bucket", BucketMock)
    def test_dynamic_update_notifies_microservices_on_the_model_db_shard(self):
        for name in ["DEFAULT__PACKETLOG__INST", "DEFAULT__DECOM__INST"]:
            MicroserviceModel(folder_name="INST", name=name, db_shard=1, scope="DEFAULT").create()
        model = TargetModel(name="INST", db_shard=1, scope="DEFAULT")
        model.dynamic_update([Packet("INST", "NEW_TLM")], "TELEMETRY")
        self.assertIsNotNone(self.shard1.hget("DEFAULT__openc3tlm__INST", "NEW_TLM"))
        for topic in ["MICROSERVICE__DEFAULT__PACKETLOG__INST", "MICROSERVICE__DEFAULT__DECOM__INST"]:
            self.assertEqual(self.shard1.xlen(topic), 1)
            self.assertFalse(self.shard0.exists(topic))


# Tests for GitHub issue #2855:
# Stale tlmcnt Redis keys cause interface disconnect loops.
# When a plugin is upgraded and packets are removed, old Redis TELEMETRYCNTS keys
# remain. When the interface receives a packet and tries to sync counts, it calls
# System.telemetry.packet() for every key in Redis — including the stale ones —
# which raises RuntimeError and causes the interface to disconnect and reconnect.
class TestTargetModelStaleTlmCntKeys(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        # Reset class-level sync state between tests
        TargetModel.sync_packet_count_data = {}
        TargetModel.sync_packet_count_time = None
        TargetModel.sync_packet_count_delay_seconds = 1.0
        TargetModel.stale_packet_keys_warned = set()

    def test_init_tlm_packet_counts_skips_stale_redis_key(self):
        # Simulate a stale Redis key left over from a removed packet definition.
        # INST currently defines HEALTH_STATUS, ADCS, PARAMS, IMAGE, MECH, HIDDEN —
        # OLD_PACKET was removed when the plugin was upgraded but its Redis key remains.
        Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)
        Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS", 10)

        # init_tlm_packet_counts must skip the stale key rather than raising RuntimeError.
        # It resets the warned-keys set on each call (each interface restart is a new epoch),
        # so the warning fires once per restart — useful for operators diagnosing stale state.
        for stdout in capture_io():
            TargetModel.init_tlm_packet_counts(["INST"], scope="DEFAULT")
            self.assertIn("Stale tlmcnt Redis key detected for unknown packet INST OLD_PACKET", stdout.getvalue())

            # A second init (e.g. reconnect) resets the epoch and warns again
            stdout.truncate(0)
            stdout.seek(0)
            TargetModel.init_tlm_packet_counts(["INST"], scope="DEFAULT")
            self.assertIn("Stale tlmcnt Redis key detected for unknown packet INST OLD_PACKET", stdout.getvalue())

        # The known packet's count must still be updated correctly
        self.assertEqual(System.telemetry.packet("INST", "HEALTH_STATUS").received_count, 10)

    def test_sync_tlm_packet_counts_skips_stale_redis_key(self):
        # Simulate a stale Redis key left over from a removed packet definition.
        Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")

        # sync_packet_count_time=None forces the periodic Redis sync to run
        # immediately on the first call rather than waiting for the delay to expire.
        TargetModel.sync_packet_count_time = None

        for stdout in capture_io():
            # The stale key must be skipped; no RuntimeError raised
            TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope="DEFAULT")
            # A warning must be logged exactly once for the stale key
            self.assertIn("Stale tlmcnt Redis key detected for unknown packet INST OLD_PACKET", stdout.getvalue())

            # Calling again (forcing another sync) must NOT repeat the warning
            TargetModel.sync_packet_count_time = None
            stdout.truncate(0)
            stdout.seek(0)
            TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope="DEFAULT")
            self.assertNotIn("Stale tlmcnt Redis key", stdout.getvalue())

        # Known packet counts must still be updated correctly
        self.assertGreater(packet.received_count, 0)
