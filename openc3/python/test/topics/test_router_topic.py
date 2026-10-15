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

import unittest
from unittest.mock import patch

from openc3.packets.packet import Packet
from openc3.topics.router_topic import RouterTopic
from test.test_helper import mock_redis


class TestRouterTopicRouteCommand(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        p = patch("openc3.topics.router_topic.Topic.write_topic")
        self.write_topic = p.start()
        self.addCleanup(p.stop)

    def test_routes_an_identified_command_to_its_target(self):
        packet = Packet("INST", "ABORT")
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST", "INST2"], scope="DEFAULT")
        self.write_topic.assert_called_once_with(
            "{DEFAULT__CMD}TARGET__INST",
            {"target_name": "INST", "cmd_name": "ABORT", "cmd_buffer": b"\x01\x02"},
            "*",
            100,
        )

    def test_routes_an_unidentified_command_to_the_only_target_naming_that_target(self):
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST"], scope="DEFAULT")
        self.write_topic.assert_called_once_with(
            "{DEFAULT__CMD}TARGET__INST",
            {"target_name": "INST", "cmd_name": "UNKNOWN", "cmd_buffer": b"\x01\x02"},
            "*",
            100,
        )

    def test_raises_if_an_unidentified_command_has_more_than_one_possible_target(self):
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        with self.assertRaisesRegex(RuntimeError, "No route for command"):
            RouterTopic.route_command(packet, ["INST", "INST2"], scope="DEFAULT")
