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
from openc3.script.commands import *
from openc3.top_level import HazardousError
from openc3.models.target_model import TargetModel

gArgs = []
gKwargs = {}
gTime = time.time()


def my_prompt_for_hazardous(target_name, cmd_name, hazardous_description):
    return True


class Proxy:
    def cmd(*args, **kwargs):
        global gArgs
        global gKwargs
        gArgs = args
        gKwargs = kwargs
        for arg in args:
            if "ABORT" in arg:
                return "INST", "ABORT", {}, {}
            elif "CLEAR" in arg:
                error = HazardousError()
                error.target_name = "INST"
                error.cmd_name = "CLEAR"
                raise error
            elif "SET_PASSWORD" in arg:
                return "INST", "SET_PASSWORD", {"USERNAME": "user", "PASSWORD": "pass"}, {"obfuscated_items": ["PASSWORD"]}
            elif "HAZARDOUS_SET_PASSWORD" in arg:
                error = HazardousError()
                error.target_name = "INST"
                error.cmd_name = "SET_PASSWORD"
                raise error

    def cmd_raw(*args, **kwargs):
        global gArgs
        global gKwargs
        gArgs = args
        gKwargs = kwargs
        for arg in args:
            if "ABORT" in arg:
                return "INST", "ABORT", {}, {}

    def cmd_no_hazardous_check(*args, **kwargs):
        global gArgs
        global gKwargs
        gArgs = args
        gKwargs = kwargs
        return "INST", "CLEAR", {}, {}

    def cmd_no_checks(*args, **kwargs):
        global gArgs
        global gKwargs
        gArgs = args
        gKwargs = kwargs
        return "INST", "CLEAR", {}, {}

    # Duplicate the return in cmd_api.py
    def get_cmd(target_name, cmd_name, scope):
        return TargetModel.packet(target_name, cmd_name, type="CMD", scope=scope)

    # Duplicate the return in cmd_api.py
    def get_cmd_time(target_name=None, command_name=None, scope=OPENC3_SCOPE):
        global gTime
        return (
            target_name,
            command_name,
            int(gTime),
            int((gTime - int(gTime)) * 1_000_000),
        )


@patch("openc3.script.API_SERVER", Proxy)
@patch("openc3.script.prompt_for_hazardous", my_prompt_for_hazardous)
class TestCommands(unittest.TestCase):
    def setUp(self):
        global gArgs
        global gKwargs
        gArgs = []
        gKwargs = {}

        mock_redis(self)
        setup_system()
        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        openc3.script.DISCONNECT = False

    def test_sends_a_cmd(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd("INST ABORT")
            self.assertIn(
                'cmd("INST ABORT")',
                stdout.getvalue(),
            )
        self.assertEqual(gArgs, ("INST ABORT",))

    def test_sends_a_cmd_raw(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd_raw("INST ABORT")
            self.assertIn(
                'cmd_raw("INST ABORT")',
                stdout.getvalue(),
            )
        self.assertEqual(gArgs, ("INST ABORT",))

    def test_sends_a_cmd_no_checks(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd_no_checks("INST CLEAR")
            self.assertIn(
                'cmd("INST CLEAR")',
                stdout.getvalue(),
            )
        self.assertEqual(gArgs, ("INST CLEAR",))

    def test_logs_only_in_disconnect(self):
        global gArgs
        global gKwargs
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            cmd("INST ABORT")
            self.assertIn(
                'cmd("INST ABORT")',
                stdout.getvalue(),
            )
            self.assertEqual(gArgs, [])

            cmd("INST", "ABORT")
            self.assertIn(
                'cmd("INST ABORT")',
                stdout.getvalue(),
            )
            self.assertEqual(gArgs, [])

            cmd("INST", "COLLECT", {"TYPE": "SPECIAL"})
            self.assertIn(
                'cmd("INST COLLECT with TYPE SPECIAL")',
                stdout.getvalue(),
            )
            self.assertEqual(gArgs, [])

        with self.assertRaisesRegex(RuntimeError, "ERROR: Invalid number of arguments"):
            cmd("INST", "COLLECT", "TYPE", "SPECIAL")

        with self.assertRaisesRegex(
            RuntimeError, "Packet item 'INST COLLECT NOPE' does not exist"
        ):
            cmd("INST", "COLLECT", {"NOPE": "NOPE"})

    def test_sends_a_hazardous_cmd(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd("INST CLEAR")
            self.assertIn(
                'cmd("INST CLEAR")',
                stdout.getvalue(),
            )
        self.assertEqual(gArgs, ("INST CLEAR",))

    def test_get_cmd_time(self):
        global gTime
        gTime = time.time()
        cmd_time = get_cmd_time("INST", "CLEAR")
        self.assertEqual(cmd_time[0], "INST")
        self.assertEqual(cmd_time[1], "CLEAR")
        self.assertEqual("%.3f" % cmd_time[2].timestamp(), "%.3f" % gTime)

    def test_handles_obfuscation(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd("INST SET_PASSWORD with USERNAME user PASSWORD pass")
            self.assertIn(
                'cmd("INST SET_PASSWORD with USERNAME user, PASSWORD *****")',
                stdout.getvalue(),
            )
    
    def test_sends_a_hazardous_obfuscated_cmd(self):
        global gArgs
        global gKwargs
        for stdout in capture_io():
            cmd("INST HAZARDOUS_SET_PASSWORD with USERNAME user PASSWORD pass")
            self.assertIn(
                'cmd("INST SET_PASSWORD with USERNAME user, PASSWORD *****")',
                stdout.getvalue(),
            )