#!/usr/bin/env python3

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

import json
import unittest
from unittest.mock import *
from test.test_helper import *
import fakeredis
from openc3.api.cmd_api import *
from openc3.utilities.store import Store


class TestCmdApi(unittest.TestCase):
    def setUp(self):
        self.redis = fakeredis.FakeStrictRedis(version=7)

        orig_xadd = self.redis.xadd
        self.xadd_id = ""

        def xadd_side_effect(*args, **kwargs):
            self.xadd_id = orig_xadd(*args, **kwargs)
            return self.xadd_id

        def xread_side_effect(*args, **kwargs):
            return [
                ["topic", [[self.xadd_id, {"id": self.xadd_id, "result": "SUCCESS"}]]]
            ]

        self.redis.xadd = Mock()
        self.redis.xadd.side_effect = xadd_side_effect
        self.redis.xread = Mock()
        self.redis.xread.side_effect = xread_side_effect
        patcher = patch("redis.Redis", return_value=self.redis)
        self.mock_redis = patcher.start()
        self.addCleanup(patcher.stop)

        self.model = TargetModel(name="INST", scope="DEFAULT")
        self.model.create()
        packet = Packet("INST", "COLLECT")
        Store.hset(f"DEFAULT__openc3cmd__INST", "COLLECT", json.dumps(packet.as_json()))
        packet = Packet("INST", "ABORT")
        Store.hset(f"DEFAULT__openc3cmd__INST", "ABORT", json.dumps(packet.as_json()))

    def tearDown(self):
        self.redis.flushall()
        self.model.destroy()

    def test_cmd_processes_a_string(self):
        target_name, cmd_name, params = cmd("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name, "INST")
        self.assertEqual(cmd_name, "COLLECT")
        self.assertEqual(params, {"TYPE": "NORMAL", "DURATION": 5})

    def test_cmd_complains_if_parameters_not_separated_by_commas(self):
        with self.assertRaises(RuntimeError) as error:
            cmd("INST COLLECT with TYPE NORMAL DURATION 5")
            self.assertTrue("Missing comma" in error.exception)

    def test_cmd_complains_if_parameters_dont_have_values(self):
        with self.assertRaises(RuntimeError) as error:
            cmd("INST COLLECT with TYPE")
            self.assertTrue("Missing value" in error.exception)

    def test_cmd_processes_parameters(self):
        target_name, cmd_name, params = cmd(
            "inst", "Collect", {"TYPE": "NORMAL", "Duration": 5}
        )
        self.assertEqual(target_name, "INST")
        self.assertEqual(cmd_name, "COLLECT")
        self.assertEqual(params, {"TYPE": "NORMAL", "DURATION": 5})

    def test_cmd_processes_commands_without_parameters(self):
        target_name, cmd_name, params = cmd("INST", "ABORT")
        self.assertEqual(target_name, "INST")
        self.assertEqual(cmd_name, "ABORT")
        self.assertEqual(params, {})

    def test_cmd_complains_about_too_many_parameters(self):
        with self.assertRaises(RuntimeError) as error:
            cmd("INST", "COLLECT", "TYPE", "DURATION")
            self.assertTrue("Invalid number of arguments" in error.exception)

    # def test_cmd_warns_about_required_parameters(self):
    #     with self.assertRaises(RuntimeError) as error:
    #         cmd("INST COLLECT with DURATION 5")
    #         self.assertTrue("Required" in error.exception)

    # def test_cmd_warns_about_out_of_range_parameters(self):
    #     with self.assertRaises(RuntimeError) as error:
    #         cmd("INST COLLECT with TYPE NORMAL, DURATION 1000")
    #         self.assertTrue("not in valid range" in error.exception)

    # def test_cmd_warns_about_hazardous_parameters(self):
    #     with self.assertRaises(RuntimeError) as error:
    #         cmd("INST COLLECT with TYPE SPECIAL")
    #         self.assertTrue("Hazardous" in error.exception)

    # def test_cmd_warns_about_hazardous_commands(self):
    #     with self.assertRaises(RuntimeError) as error:
    #         cmd("INST CLEAR")
    #         self.assertTrue("Hazardous" in error.exception)
