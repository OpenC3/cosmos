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
from openc3.api.tlm_api import *
from openc3.utilities.store import Store
from openc3.packets.packet import Packet


class TestTlmApi(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

        self.model = TargetModel(name="INST", scope="DEFAULT")
        self.model.create()
        hs = Packet("INST", "HEALTH_STATUS")
        Store.hset(
            "DEFAULT__openc3tlm__INST", "HEALTH_STATUS", json.dumps(hs.as_json())
        )

    def test_tlm_complains_about_unknown_targets_commands_and_parameters(self):
        with self.assertRaises(RuntimeError) as error:
            tlm("BLAH HEALTH_STATUS COLLECTS")
            self.assertTrue("does not exist") in error.exception
        with self.assertRaises(RuntimeError) as error:
            tlm("INST HEALTH_STATUS BLAH")
            self.assertTrue("does not exist") in error.exception
        with self.assertRaises(RuntimeError) as error:
            tlm("BLAH", "HEALTH_STATUS", "COLLECTS")
            self.assertTrue("does not exist") in error.exception
        with self.assertRaises(RuntimeError) as error:
            tlm("INST", "UNKNOWN", "COLLECTS")
            self.assertTrue("does not exist") in error.exception
        with self.assertRaises(RuntimeError) as error:
            tlm("INST", "HEALTH_STATUS", "BLAH")
            self.assertTrue("does not exist") in error.exception

    # def test_tlm_processes_a_string(self):
    #     print(self.redis)
    #     self.assertEqual(tlm("INST HEALTH_STATUS COLLECTS"), -100.0)
