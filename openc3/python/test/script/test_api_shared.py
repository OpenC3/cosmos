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

import unittest
from unittest.mock import patch
from test.test_helper import *
import fakeredis
from openc3.script.api_shared import *


@patch("redis.Redis", return_value=fakeredis.FakeStrictRedis(version=7))
class TestApiShared(unittest.TestCase):
    pass
    # @patch("openc3.script.telemetry.tlm_raw")
    # @patch("openc3.script.telemetry.tlm")
    # def test_check_telemetry_item_against_value(self, tlm, tlm_raw, Redis):
    #     for stdout in capture_io():
    #         tlm.return_value = 10
    #         check("INST", "HEALTH_STATUS", "TEMP1", "> 1")
    #         self.assertRegex(
    #             stdout.getvalue(),
    #             r"CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10",
    #         )

    #         tlm_raw.return_value = 1
    #         check("INST HEALTH_STATUS TEMP1 == 1", type="RAW")
    #         self.assertRegex(
    #             stdout.getvalue(),
    #             r"CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1",
    #         )

    #     self.assertRaisesRegex(
    #         CheckError,
    #         r"CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10",
    #         check,
    #         "INST HEALTH_STATUS TEMP1 > 100",
    #     )

    # @patch("openc3.script.telemetry.tlm")
    # def test_check_warns_when_checking_a_state_against_a_constant(self, tlm, Redis):
    #     tlm.return_value = "FALSE"
    #     for stdout in capture_io():
    #         check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'")
    #         self.assertRegex(
    #             stdout.getvalue(),
    #             r"CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'",
    #         )

    #     self.assertRaisesRegex(
    #         NameError,
    #         r"Uninitialized constant FALSE. Did you mean 'FALSE' as a string",
    #         check,
    #         "INST HEALTH_STATUS CCSDSSHF == FALSE",
    #     )
