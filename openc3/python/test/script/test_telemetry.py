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

import time
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.script.telemetry import *


gPkts = []
gSleep = 0
gTotalSleep = 0


# sleep in a script - returns true if canceled mid sleep
def my_openc3_script_sleep(sleep_time=None):
    global gSleep
    global gTotalSleep
    gSleep = sleep_time
    gTotalSleep += gSleep
    time.sleep(sleep_time)


class Proxy:
    def get_packets(*args, **kwargs):
        global gPkts
        return "ID", gPkts

    def inject_tlm(
        target_name, packet_name, item_hash=None, type="CONVERTED", scope=OPENC3_SCOPE
    ):
        pass

    def set_tlm(*args, type="CONVERTED", scope=OPENC3_SCOPE):
        pass

    def override_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
        pass

    def normalize_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
        pass


@patch("openc3.script.API_SERVER", Proxy)
@patch("openc3.script.telemetry.openc3_script_sleep", my_openc3_script_sleep)
class TestTelemetry(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_get_packets(self):
        global gPkts
        gPkts = ["pkt1", "pkt2"]
        id, packets = get_packets("id")
        self.assertEqual(id, "ID")
        self.assertEqual(packets, ["pkt1", "pkt2"])

    def test_get_packets_with_block(self):
        global gPkts
        global gSleep
        gPkts = []
        id, packets = get_packets("id", block=0.5, block_delay=0.2)
        self.assertEqual(gSleep, 0.2)
        self.assertAlmostEqual(gTotalSleep, 0.6)
        self.assertEqual(id, "ID")
        self.assertEqual(packets, [])

    def test_inject_tlm(self):
        for stdout in capture_io():
            inject_tlm("TARGET", "PACKET", {"PARAM": "VALUE"})
            self.assertIn(
                'inject_tlm("TARGET", "PACKET", {\'PARAM\': \'VALUE\'}, type="CONVERTED")',
                stdout.getvalue(),
            )

    def test_set_tlm(self):
        for stdout in capture_io():
            set_tlm("TARGET", "PACKET", "ITEM", 10)
            self.assertIn(
                'set_tlm("TARGET", "PACKET", "ITEM", 10, type="CONVERTED")',
                stdout.getvalue(),
            )
            set_tlm("TARGET", "PACKET", "ITEM", "10")
            self.assertIn(
                'set_tlm("TARGET", "PACKET", "ITEM", "10", type="CONVERTED")',
                stdout.getvalue(),
            )
            set_tlm("TARGET PACKET ITEM = 10")
            self.assertIn(
                'set_tlm("TARGET PACKET ITEM = 10", type="CONVERTED")',
                stdout.getvalue(),
            )
            set_tlm("TARGET PACKET ITEM = '10'")
            self.assertIn(
                'set_tlm("TARGET PACKET ITEM = \'10\'", type="CONVERTED")',
                stdout.getvalue(),
            )

    def test_override_tlm(self):
        for stdout in capture_io():
            override_tlm("TARGET", "PACKET", "ITEM", 10)
            self.assertIn(
                'override_tlm("TARGET", "PACKET", "ITEM", 10, type="ALL")',
                stdout.getvalue(),
            )
            override_tlm("TARGET", "PACKET", "ITEM", "10", type="RAW")
            self.assertIn(
                'override_tlm("TARGET", "PACKET", "ITEM", "10", type="RAW")',
                stdout.getvalue(),
            )
            override_tlm("TARGET PACKET ITEM = 10")
            self.assertIn(
                'override_tlm("TARGET PACKET ITEM = 10", type="ALL")',
                stdout.getvalue(),
            )
            override_tlm("TARGET PACKET ITEM = '10'", type="WITH_UNITS")
            self.assertIn(
                'override_tlm("TARGET PACKET ITEM = \'10\'", type="WITH_UNITS")',
                stdout.getvalue(),
            )

    def test_normalize_tlm(self):
        for stdout in capture_io():
            normalize_tlm("TARGET", "PACKET", "ITEM", 10)
            self.assertIn(
                'normalize_tlm("TARGET", "PACKET", "ITEM", 10, type="ALL")',
                stdout.getvalue(),
            )
            normalize_tlm("TARGET", "PACKET", "ITEM", "10", type="RAW")
            self.assertIn(
                'normalize_tlm("TARGET", "PACKET", "ITEM", "10", type="RAW")',
                stdout.getvalue(),
            )
            normalize_tlm("TARGET PACKET ITEM = 10")
            self.assertIn(
                'normalize_tlm("TARGET PACKET ITEM = 10", type="ALL")',
                stdout.getvalue(),
            )
            normalize_tlm("TARGET PACKET ITEM = '10'", type="WITH_UNITS")
            self.assertIn(
                'normalize_tlm("TARGET PACKET ITEM = \'10\'", type="WITH_UNITS")',
                stdout.getvalue(),
            )
