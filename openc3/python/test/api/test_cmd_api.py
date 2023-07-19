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


# @patch("redis.Redis", return_value=fakeredis.FakeStrictRedis(version=7))
class TestCmdApi(unittest.TestCase):
    def setUp(self):
        redis = fakeredis.FakeStrictRedis(version=7)

        orig_xadd = redis.xadd
        self.xadd_id = ""

        def xadd_side_effect(*args, **kwargs):
            self.xadd_id = orig_xadd(*args, **kwargs)
            return self.xadd_id

        def xread_side_effect(*args, **kwargs):
            return [
                ["topic", [[self.xadd_id, {"id": self.xadd_id, "result": "SUCCESS"}]]]
            ]

        redis.xadd = Mock()
        redis.xadd.side_effect = xadd_side_effect
        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect
        patcher = patch("redis.Redis", return_value=redis)
        self.mock_redis = patcher.start()
        self.addCleanup(patcher.stop)

        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        packet = Packet("INST", "COLLECT")
        Store.hset(f"DEFAULT__openc3cmd__INST", "COLLECT", json.dumps(packet.as_json()))

    def test_cmd(self):
        target_name, cmd_name, params = cmd("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name, "INST")
        self.assertEqual(cmd_name, "COLLECT")
        self.assertEqual(params, {"TYPE": "NORMAL", "DURATION": 5})
