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

# Verifies each topic class reads and writes the db_shard it should. Every db_shard
# has its own FakeValkey (mock_redis_db_shards) so data on the wrong db_shard is lost.

import datetime
import json
import threading
import time
import unittest
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from openc3.packets.packet import Packet
from openc3.topics.command_decom_topic import CommandDecomTopic
from openc3.topics.command_topic import CommandTopic
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.topics.router_topic import RouterTopic
from openc3.topics.system_events_topic import SystemEventsTopic
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.topics.topic import Topic
from openc3.utilities.store import EphemeralStore, Store
from test.test_helper import mock_redis_db_shards, set_target_db_shard


class StopReceivingError(Exception):
    """Raised to break out of the receive_commands and receive_telemetry loops"""


def shard(db_shard):
    return EphemeralStore.instance(db_shard=db_shard)


def set_model_db_shard(type, name, db_shard, scope="DEFAULT"):
    """Interfaces and routers are found by their model json on db_shard 0"""
    Store.instance(db_shard=0).hset(f"{scope}__openc3_{type}", name, json.dumps({"name": name, "db_shard": db_shard}))


def messages(topic, db_shard):
    return [msg_hash for _, msg_hash in shard(db_shard).xrange(topic)]


class DbShardTestCase(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        set_target_db_shard("INST", 0)
        set_target_db_shard("INST2", 1)
        set_model_db_shard("interfaces", "INST_INT", 2)
        set_model_db_shard("routers", "ROUTER_INT", 2)

    def stop_reading_after(self, received, expected, max_reads=10):
        """The read after expected messages are received raises so the acks for the
        received messages are written first. Stop after max_reads in case a message
        is never received."""
        original = Topic.read_topics
        reads = [0]

        def read_topics(*args, **kwargs):
            reads[0] += 1
            if len(received) >= expected or reads[0] > max_reads:
                raise StopReceivingError()
            return original(*args, **kwargs)

        patcher = patch.object(Topic, "read_topics", side_effect=read_topics)
        patcher.start()
        self.addCleanup(patcher.stop)

    @contextmanager
    def respond(self, cmd_topic, ack_topic, db_shard, ack=None, count=1):
        """Act as the microservice: read count commands from cmd_topic on db_shard and
        ack each one on the same db_shard. A command written to any other db_shard is
        never seen so the caller times out. Yields the list of commands read."""
        if ack is None:
            ack = {"result": "SUCCESS"}
        commands = []

        def run():
            id = b"0-0"
            start = time.time()
            while len(commands) < count and (time.time() - start) < 5:
                for _stream, entries in shard(db_shard).xread({cmd_topic: id}, block=100) or []:
                    for msg_id, msg_hash in entries:
                        commands.append(msg_hash)
                        shard(db_shard).write_topic(ack_topic, {**ack, "id": msg_id})
                        id = msg_id

        thread = threading.Thread(target=run)
        thread.start()
        try:
            yield commands
        finally:
            thread.join()


class TestInterfaceTopicDbShard(DbShardTestCase):
    CMD_TOPIC = "{DEFAULT__CMD}INTERFACE__INST_INT"
    ACK_TOPIC = "{DEFAULT__ACKCMD}INTERFACE__INST_INT"

    def receive(self, interface, db_shard, received, result):
        def method(topic, _msg_id, msg_hash, _redis):
            received.append((topic, msg_hash))
            return result(topic)

        with self.assertRaises(StopReceivingError):
            InterfaceTopic.receive_commands(method, interface, scope="DEFAULT", db_shard=db_shard)

    def test_reads_each_targets_commands_from_its_db_shard_and_acks_them_there(self):
        interface = SimpleNamespace(name="INST_INT", cmd_target_names=["INST", "INST2"])
        shard(0).update_topic_offsets(["{DEFAULT__CMD}TARGET__INST"])
        shard(1).update_topic_offsets(["{DEFAULT__CMD}TARGET__INST2"])
        shard(2).update_topic_offsets([self.CMD_TOPIC, "OPENC3__SYSTEM__EVENTS"])
        Topic.write_topic("{DEFAULT__CMD}TARGET__INST", {"cmd_name": "INST_CMD"}, db_shard=0)
        Topic.write_topic("{DEFAULT__CMD}TARGET__INST2", {"cmd_name": "INST2_CMD"}, db_shard=1)
        Topic.write_topic(self.CMD_TOPIC, {"connect": "true"}, db_shard=2)
        Topic.write_topic("OPENC3__SYSTEM__EVENTS", {"event": "{}"}, db_shard=2)
        # The interface reads its own topic from its db_shard only
        Topic.write_topic(self.CMD_TOPIC, {"connect": "wrong db_shard"}, db_shard=0)

        received = []
        self.stop_reading_after(received, 4)
        self.receive(interface, 2, received, lambda topic: None if topic == "OPENC3__SYSTEM__EVENTS" else "SUCCESS")

        self.assertCountEqual(
            received,
            [
                ("{DEFAULT__CMD}TARGET__INST", {b"cmd_name": b"INST_CMD"}),
                ("{DEFAULT__CMD}TARGET__INST2", {b"cmd_name": b"INST2_CMD"}),
                (self.CMD_TOPIC, {b"connect": b"true"}),
                ("OPENC3__SYSTEM__EVENTS", {b"event": b"{}"}),
            ],
        )
        self.assertEqual([msg[b"result"] for msg in messages("{DEFAULT__ACKCMD}TARGET__INST", 0)], [b"SUCCESS"])
        self.assertEqual([msg[b"result"] for msg in messages("{DEFAULT__ACKCMD}TARGET__INST2", 1)], [b"SUCCESS"])
        self.assertEqual([msg[b"result"] for msg in messages(self.ACK_TOPIC, 2)], [b"SUCCESS"])
        self.assertEqual(shard(2).exists("{DEFAULT__ACKCMD}TARGET__INST", "{DEFAULT__ACKCMD}TARGET__INST2"), 0)
        self.assertEqual(shard(0).exists(self.ACK_TOPIC), 0)

    def test_reads_and_acks_everything_on_one_db_shard_when_its_all_on_that_db_shard(self):
        set_model_db_shard("interfaces", "INST_INT", 1)
        interface = SimpleNamespace(name="INST_INT", cmd_target_names=["INST2"])
        shard(1).update_topic_offsets(["{DEFAULT__CMD}TARGET__INST2", self.CMD_TOPIC, "OPENC3__SYSTEM__EVENTS"])
        Topic.write_topic("{DEFAULT__CMD}TARGET__INST2", {"cmd_name": "INST2_CMD"}, db_shard=1)
        Topic.write_topic(self.CMD_TOPIC, {"connect": "true"}, db_shard=1)

        received = []
        self.stop_reading_after(received, 2)
        self.receive(interface, 1, received, lambda _topic: "SUCCESS")

        self.assertCountEqual([topic for topic, _ in received], ["{DEFAULT__CMD}TARGET__INST2", self.CMD_TOPIC])
        self.assertEqual(len(messages("{DEFAULT__ACKCMD}TARGET__INST2", 1)), 1)
        self.assertEqual(len(messages(self.ACK_TOPIC, 1)), 1)
        self.assertEqual(shard(0).exists("{DEFAULT__ACKCMD}TARGET__INST2", self.ACK_TOPIC), 0)

    def test_writers_write_to_the_interfaces_db_shard(self):
        InterfaceTopic.connect_interface("INST_INT", scope="DEFAULT")
        InterfaceTopic.connect_interface("INST_INT", "localhost", 8080, scope="DEFAULT")
        InterfaceTopic.disconnect_interface("INST_INT", scope="DEFAULT")
        InterfaceTopic.start_raw_logging("INST_INT", scope="DEFAULT")
        InterfaceTopic.stop_raw_logging("INST_INT", scope="DEFAULT")
        InterfaceTopic.shutdown(SimpleNamespace(name="INST_INT"), scope="DEFAULT")
        InterfaceTopic.interface_cmd("INST_INT", "CMD", 1, scope="DEFAULT")
        InterfaceTopic.protocol_cmd("INST_INT", "CMD", 1, scope="DEFAULT")
        InterfaceTopic.interface_target_enable("INST_INT", "INST", scope="DEFAULT")
        InterfaceTopic.interface_target_disable("INST_INT", "INST", scope="DEFAULT")

        keys = [next(iter(msg)) for msg in messages(self.CMD_TOPIC, 2)]
        self.assertEqual(
            keys,
            [
                b"connect",
                b"connect",
                b"disconnect",
                b"log_stream",
                b"log_stream",
                b"shutdown",
                b"interface_cmd",
                b"protocol_cmd",
                b"target_control",
                b"target_control",
            ],
        )
        self.assertEqual(shard(0).exists(self.CMD_TOPIC), 0)

    def test_defaults_to_db_shard_0_for_an_unknown_interface(self):
        InterfaceTopic.connect_interface("OTHER_INT", scope="DEFAULT")
        self.assertEqual(len(messages("{DEFAULT__CMD}INTERFACE__OTHER_INT", 0)), 1)

    def test_waits_for_the_ack_on_the_interfaces_db_shard(self):
        with self.respond(self.CMD_TOPIC, self.ACK_TOPIC, 2, count=2) as commands:
            InterfaceTopic.write_raw("INST_INT", b"\x00", scope="DEFAULT", timeout=2)
            InterfaceTopic.inject_tlm("INST_INT", "INST", "HEALTH_STATUS", {"TEMP1": 1}, timeout=2, scope="DEFAULT")
        self.assertEqual([next(iter(msg)) for msg in commands], [b"raw", b"inject_tlm"])
        self.assertEqual(shard(0).exists(self.CMD_TOPIC, self.ACK_TOPIC), 0)

    def test_waits_for_interface_details_on_the_interfaces_db_shard(self):
        with self.respond(self.CMD_TOPIC, self.ACK_TOPIC, 2, {"result": '{"name":"INST_INT"}'}):
            details = InterfaceTopic.interface_details("INST_INT", scope="DEFAULT", timeout=2)
        self.assertEqual(details, {"name": "INST_INT"})
        self.assertEqual(shard(0).exists(self.CMD_TOPIC, self.ACK_TOPIC), 0)


class TestRouterTopicDbShard(DbShardTestCase):
    CMD_TOPIC = "{DEFAULT__CMD}ROUTER__ROUTER_INT"
    ACK_TOPIC = "{DEFAULT__ACKCMD}ROUTER__ROUTER_INT"

    def setUp(self):
        super().setUp()
        system = MagicMock()
        system.telemetry.packets.side_effect = lambda target_name: {
            "HEALTH_STATUS": Packet(target_name, "HEALTH_STATUS")
        }
        patcher = patch("openc3.topics.router_topic.System", system)
        patcher.start()
        self.addCleanup(patcher.stop)

    def receive(self, router, db_shard, received):
        generator = RouterTopic.receive_telemetry(router, scope="DEFAULT", db_shard=db_shard)
        with self.assertRaises(StopReceivingError):
            topic, _msg_id, msg_hash, _redis = next(generator)
            while True:
                received.append((topic, msg_hash))
                topic, _msg_id, msg_hash, _redis = generator.send("SUCCESS")

    def test_reads_each_targets_telemetry_from_its_db_shard_and_acks_router_commands_on_the_routers_db_shard(self):
        router = SimpleNamespace(name="ROUTER_INT", tlm_target_names=["INST", "INST2"])
        shard(0).update_topic_offsets(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
        shard(1).update_topic_offsets(["DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS"])
        shard(2).update_topic_offsets([self.CMD_TOPIC])
        Topic.write_topic("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", {"buffer": "INST"}, db_shard=0)
        Topic.write_topic("DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", {"buffer": "INST2"}, db_shard=1)
        Topic.write_topic(self.CMD_TOPIC, {"connect": "true"}, db_shard=2)
        Topic.write_topic(self.CMD_TOPIC, {"connect": "wrong db_shard"}, db_shard=0)

        received = []
        self.stop_reading_after(received, 3)
        self.receive(router, 2, received)

        self.assertCountEqual(
            received,
            [
                ("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", {b"buffer": b"INST"}),
                ("DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", {b"buffer": b"INST2"}),
                (self.CMD_TOPIC, {b"connect": b"true"}),
            ],
        )
        # Only router commands are acked
        self.assertEqual([msg[b"result"] for msg in messages(self.ACK_TOPIC, 2)], [b"SUCCESS"])
        self.assertEqual(shard(0).exists("DEFAULT__ACKTELEMETRY__{INST}__HEALTH_STATUS"), 0)
        self.assertEqual(shard(1).exists("DEFAULT__ACKTELEMETRY__{INST2}__HEALTH_STATUS"), 0)

    def test_reads_and_acks_everything_on_one_db_shard_when_its_all_on_that_db_shard(self):
        set_model_db_shard("routers", "ROUTER_INT", 1)
        router = SimpleNamespace(name="ROUTER_INT", tlm_target_names=["INST2"])
        shard(1).update_topic_offsets(["DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", self.CMD_TOPIC])
        Topic.write_topic("DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", {"buffer": "INST2"}, db_shard=1)
        Topic.write_topic(self.CMD_TOPIC, {"connect": "true"}, db_shard=1)

        received = []
        self.stop_reading_after(received, 2)
        self.receive(router, 1, received)

        self.assertCountEqual(
            [topic for topic, _ in received], ["DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", self.CMD_TOPIC]
        )
        self.assertEqual(len(messages(self.ACK_TOPIC, 1)), 1)

    def test_writers_write_to_the_routers_db_shard(self):
        RouterTopic.connect_router("ROUTER_INT", scope="DEFAULT")
        RouterTopic.connect_router("ROUTER_INT", "localhost", 8080, scope="DEFAULT")
        RouterTopic.disconnect_router("ROUTER_INT", scope="DEFAULT")
        RouterTopic.start_raw_logging("ROUTER_INT", scope="DEFAULT")
        RouterTopic.stop_raw_logging("ROUTER_INT", scope="DEFAULT")
        RouterTopic.shutdown(SimpleNamespace(name="ROUTER_INT"), scope="DEFAULT")
        RouterTopic.router_cmd("ROUTER_INT", "CMD", 1, scope="DEFAULT")
        RouterTopic.protocol_cmd("ROUTER_INT", "CMD", 1, scope="DEFAULT")
        RouterTopic.router_target_enable("ROUTER_INT", "INST", scope="DEFAULT")
        RouterTopic.router_target_disable("ROUTER_INT", "INST", scope="DEFAULT")

        keys = [next(iter(msg)) for msg in messages(self.CMD_TOPIC, 2)]
        self.assertEqual(
            keys,
            [
                b"connect",
                b"connect",
                b"disconnect",
                b"log_stream",
                b"log_stream",
                b"shutdown",
                b"router_cmd",
                b"protocol_cmd",
                b"target_control",
                b"target_control",
            ],
        )
        self.assertEqual(shard(0).exists(self.CMD_TOPIC), 0)

    def test_waits_for_router_details_on_the_routers_db_shard(self):
        with self.respond(self.CMD_TOPIC, self.ACK_TOPIC, 2, {"result": '{"name":"ROUTER_INT"}'}):
            details = RouterTopic.router_details("ROUTER_INT", scope="DEFAULT", timeout=2)
        self.assertEqual(details, {"name": "ROUTER_INT"})
        self.assertEqual(shard(0).exists(self.CMD_TOPIC, self.ACK_TOPIC), 0)


class TestDecomInterfaceTopicDbShard(DbShardTestCase):
    DECOM_TOPIC = "DEFAULT__DECOMINTERFACE__{INST2}"
    ACK_TOPIC = "{DEFAULT__ACKCMD}TARGET__INST2"

    def test_writes_to_and_waits_for_the_ack_on_the_targets_db_shard(self):
        # build_cmd and get_tlm_buffer return the buffer from the ack
        ack = {"result": "SUCCESS", "stored": "false", "buffer": '"AQ=="'}
        with self.respond(self.DECOM_TOPIC, self.ACK_TOPIC, 1, ack, count=3) as commands:
            DecomInterfaceTopic.build_cmd("INST2", "ABORT", {}, True, False, timeout=2, scope="DEFAULT")
            DecomInterfaceTopic.inject_tlm("INST2", "HEALTH_STATUS", {"TEMP1": 1}, timeout=2, scope="DEFAULT")
            result = DecomInterfaceTopic.get_tlm_buffer("INST2", "HEALTH_STATUS", timeout=2, scope="DEFAULT")
        self.assertEqual([next(iter(msg)) for msg in commands], [b"build_cmd", b"inject_tlm", b"get_tlm_buffer"])
        self.assertEqual(result["result"], "SUCCESS")
        self.assertEqual(shard(0).exists(self.DECOM_TOPIC, self.ACK_TOPIC), 0)


class TestCommandTopicDbShard(DbShardTestCase):
    def command(self):
        return {"target_name": "INST2", "cmd_name": "ABORT", "cmd_params": {}}

    def test_sends_a_command_and_waits_for_the_ack_on_the_targets_db_shard(self):
        with self.respond("{DEFAULT__CMD}TARGET__INST2", "{DEFAULT__ACKCMD}TARGET__INST2", 1) as commands:
            CommandTopic.send_command(self.command(), timeout=2, scope="DEFAULT")
        self.assertEqual([msg[b"cmd_name"] for msg in commands], [b"ABORT"])
        self.assertEqual(shard(0).exists("{DEFAULT__CMD}TARGET__INST2", "{DEFAULT__ACKCMD}TARGET__INST2"), 0)

    def test_sends_a_fire_and_forget_command_to_the_targets_db_shard(self):
        CommandTopic.send_command(self.command(), timeout=0, scope="DEFAULT")
        self.assertEqual(len(messages("{DEFAULT__CMD}TARGET__INST2", 1)), 1)
        self.assertEqual(shard(0).exists("{DEFAULT__CMD}TARGET__INST2"), 0)

    def test_writes_a_packet_to_the_targets_db_shard(self):
        packet = Packet("INST2", "ABORT")
        packet.received_time = datetime.datetime.now()
        CommandTopic.write_packet(packet, scope="DEFAULT")
        self.assertEqual(len(messages("DEFAULT__COMMAND__{INST2}__ABORT", 1)), 1)
        self.assertEqual(shard(0).exists("DEFAULT__COMMAND__{INST2}__ABORT"), 0)


class TestCommandDecomTopicDbShard(DbShardTestCase):
    def test_writes_and_reads_a_decommutated_command_on_the_targets_db_shard(self):
        packet = Packet("INST2", "ABORT")
        packet.append_item("VALUE", 8, "UINT")
        packet.write("VALUE", 5)
        packet.received_time = datetime.datetime.now()
        CommandDecomTopic.write_packet(packet, scope="DEFAULT")
        self.assertEqual(len(messages("DEFAULT__DECOMCMD__{INST2}__ABORT", 1)), 1)
        self.assertEqual(shard(0).exists("DEFAULT__DECOMCMD__{INST2}__ABORT"), 0)
        self.assertEqual(CommandDecomTopic.get_cmd_item("INST2", "ABORT", "VALUE", type="RAW", scope="DEFAULT"), 5)


class TestTelemetryTopicDbShard(DbShardTestCase):
    def test_writes_a_packet_to_the_targets_db_shard_queued_or_not(self):
        packet = Packet("INST2", "HEALTH_STATUS")
        packet.received_time = datetime.datetime.now()
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        TelemetryTopic.write_packet(packet, scope="DEFAULT", queued=True)
        self.assertEqual(len(messages("DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS", 1)), 2)
        self.assertEqual(shard(0).exists("DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS"), 0)


class TestTelemetryDecomTopicDbShard(DbShardTestCase):
    def test_writes_a_decommutated_packet_to_the_targets_db_shard(self):
        packet = Packet("INST2", "HEALTH_STATUS")
        packet.append_item("VALUE", 8, "UINT")
        packet.received_time = datetime.datetime.now()
        packet.stored = True  # Skip the CVT update
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        self.assertEqual(len(messages("DEFAULT__DECOM__{INST2}__HEALTH_STATUS", 1)), 1)
        self.assertEqual(shard(0).exists("DEFAULT__DECOM__{INST2}__HEALTH_STATUS"), 0)


class TestLimitsEventTopicDbShard(DbShardTestCase):
    def test_writes_events_to_every_db_shard_with_a_target_in_the_scope(self):
        set_target_db_shard("OTHER", 3, scope="OTHER")
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "INST2",
            "packet_name": "HEALTH_STATUS",
            "item_name": "TEMP1",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED",
            "time_nsec": 0,
            "message": "test",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(len(messages("DEFAULT__openc3_limits_events", 0)), 1)
        self.assertEqual(len(messages("DEFAULT__openc3_limits_events", 1)), 1)
        self.assertEqual(shard(3).exists("DEFAULT__openc3_limits_events"), 0)


class TestSystemEventsTopicDbShard(DbShardTestCase):
    def test_writes_events_to_every_db_shard_with_a_target_in_any_scope(self):
        set_target_db_shard("OTHER", 3, scope="OTHER")
        SystemEventsTopic.write("scope", {"name": "DEFAULT"})
        for db_shard in (0, 1, 3):
            self.assertEqual(len(messages("OPENC3__SYSTEM__EVENTS", db_shard)), 1)

    def test_writes_events_to_the_db_shard_of_an_interface_without_a_target_on_it(self):
        # INST_INT is on db_shard 2 and reads system events there
        SystemEventsTopic.write("scope", {"name": "DEFAULT"})
        self.assertEqual(len(messages("OPENC3__SYSTEM__EVENTS", 2)), 1)
