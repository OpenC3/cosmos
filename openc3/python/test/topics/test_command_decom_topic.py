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

import datetime
import json
import unittest
from unittest.mock import MagicMock, patch

from openc3.conversions.polynomial_conversion import PolynomialConversion
from openc3.packets.packet import Packet
from openc3.topics.command_decom_topic import CommandDecomTopic
from test.test_helper import mock_redis


class TestCommandDecomTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.captured = {}

        def fake_write_topic(topic, msg_hash):
            self.captured["topic"] = topic
            self.captured["msg_hash"] = msg_hash

        self.store_instance = MagicMock()
        self.store_instance.write_topic.side_effect = fake_write_topic

        instance_patch = patch(
            "openc3.topics.command_decom_topic.EphemeralStoreQueued.instance",
            return_value=self.store_instance,
        )
        instance_patch.start()
        self.addCleanup(instance_patch.stop)

        shard_patch = patch(
            "openc3.topics.command_decom_topic.Store.db_shard_for_target",
            return_value=0,
        )
        shard_patch.start()
        self.addCleanup(shard_patch.stop)

    # VALUE has a write conversion which doubles the given value so the buffer
    # never holds what the user actually commanded.
    # STATE only has states and thus reads back correctly from the buffer.
    # BOTH has states and a write conversion and must still read back the state name.
    def _make_packet(self):
        packet = Packet("TARGET", "CMD")
        item = packet.append_item("VALUE", 16, "UINT")
        item.write_conversion = PolynomialConversion(0, 2)
        item = packet.append_item("STATE", 8, "UINT")
        item.states = {"FALSE": 0, "TRUE": 1}
        item = packet.append_item("BOTH", 8, "UINT")
        item.states = {"OFF": 0, "ON": 1}
        item.write_conversion = PolynomialConversion(0, 1)
        packet.packet_time = datetime.datetime.now()
        packet.received_time = datetime.datetime.now()
        packet.received_count = 1
        packet.stored = False
        packet.write("VALUE", 5)
        packet.write("STATE", "TRUE")
        packet.write("BOTH", "ON")
        return packet

    def _json_data(self, packet):
        CommandDecomTopic.write_packet(packet, scope="DEFAULT")
        return json.loads(self.captured["msg_hash"]["json_data"])

    def test_writes_to_correct_topic(self):
        CommandDecomTopic.write_packet(self._make_packet(), scope="DEFAULT")
        self.assertEqual(self.captured["topic"], "DEFAULT__DECOMCMD__{TARGET}__CMD")
        msg_hash = self.captured["msg_hash"]
        self.assertEqual(msg_hash["target_name"], "TARGET")
        self.assertEqual(msg_hash["packet_name"], "CMD")
        self.assertEqual(msg_hash["received_count"], 1)

    def test_logs_given_value_for_write_conversion_items(self):
        packet = self._make_packet()
        packet.given_values = {"VALUE": 5, "STATE": "TRUE"}
        hash = self._json_data(packet)
        self.assertEqual(hash["VALUE"], 10)  # raw value in the buffer
        self.assertEqual(hash["VALUE__C"], 5)  # value the user commanded

    def test_matches_given_values_regardless_of_key_case(self):
        packet = self._make_packet()
        packet.given_values = {"value": 5}
        hash = self._json_data(packet)
        self.assertEqual(hash["VALUE__C"], 5)

    def test_reads_converted_value_when_item_not_given(self):
        packet = self._make_packet()
        packet.given_values = {"STATE": "TRUE"}
        hash = self._json_data(packet)
        self.assertEqual(hash["VALUE__C"], 10)

    def test_reads_converted_value_when_no_given_values(self):
        packet = self._make_packet()
        self.assertIsNone(packet.given_values)
        hash = self._json_data(packet)
        self.assertEqual(hash["VALUE__C"], 10)

    def test_reads_converted_state_rather_than_given_value(self):
        # The user can give either the state name or the state value so always
        # read the state name back out of the buffer
        packet = self._make_packet()
        packet.given_values = {"STATE": 1}
        hash = self._json_data(packet)
        self.assertEqual(hash["STATE"], 1)
        self.assertEqual(hash["STATE__C"], "TRUE")

    def test_reads_state_name_for_items_with_states_and_write_conversion(self):
        # States take precedence over the write conversion so the logged value is
        # always the normalized state name rather than whatever the user gave
        packet = self._make_packet()
        packet.given_values = {"BOTH": 1}
        hash = self._json_data(packet)
        self.assertEqual(hash["BOTH"], 1)
        self.assertEqual(hash["BOTH__C"], "ON")

    def test_ignores_given_values_for_raw_commands(self):
        # Raw commands skip the write conversion so the given value is the raw value
        packet = self._make_packet()
        packet.raw = True
        packet.write("VALUE", 10, "RAW")
        # Deliberately different from the buffer to prove the buffer wins
        packet.given_values = {"VALUE": 99}
        hash = self._json_data(packet)
        self.assertEqual(hash["VALUE"], 10)
        self.assertEqual(hash["VALUE__C"], 10)
