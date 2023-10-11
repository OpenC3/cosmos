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
from openc3.api.cmd_api import *
from openc3.interfaces.interface import Interface
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.microservices.interface_microservice import InterfaceCmdHandlerThread
from openc3.top_level import HazardousError


class MyInterface(Interface):
    def connected(self):
        return True

    def read_interface(self):
        pass

    def write_interface(self, data, extra=None):
        pass


class TestCmdApi(unittest.TestCase):
    def setUp(self):
        redis = mock_redis(self)
        setup_system()

        self.process = True
        orig_xread = redis.xread

        def xread_side_effect(*args, **kwargs):
            result = None
            if self.process:
                try:
                    result = orig_xread(*args)
                except:
                    pass

            # # Create a slight delay to simulate the blocking call
            if result and len(result) == 0:
                time.sleep(0.01)
            return result

        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect

        # Create an Interface we can use in the InterfaceCmdHandlerThread
        # It has to have a valid list of target_names as that is what 'receive_commands'
        # in the Store uses to determine which topics to read
        self.interface = MyInterface()
        self.interface.name = "INST_INT"
        self.interface.target_names = ["INST"]
        self.interface.cmd_target_names = ["INST"]
        self.interface.tlm_target_names = ["INST"]
        InterfaceStatusModel.set(self.interface.as_json(), scope="DEFAULT")

        self.thread = InterfaceCmdHandlerThread(self.interface, None, scope="DEFAULT")
        self.thread.start()

    def tearDown(self) -> None:
        self.thread.stop()

    def test_cmd_complains_about_unknown_targets_commands_and_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            cmd("BLAH COLLECT with TYPE NORMAL")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            cmd("INST UNKNOWN with TYPE NORMAL")

    def test_cmd_processes_a_string(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            if "raw" in name:
                target_name, cmd_name, params = func(
                    "inst Collect with type 0, Duration 5"
                )
            else:
                target_name, cmd_name, params = func(
                    "inst Collect with type NORMAL, Duration 5"
                )
            self.assertEqual(target_name, "INST")
            self.assertEqual(cmd_name, "COLLECT")
            if "raw" in name:
                self.assertEqual(params, {"TYPE": 0, "DURATION": 5})
            else:
                self.assertEqual(params, {"TYPE": "NORMAL", "DURATION": 5})

    def test_cmd_complains_if_parameters_not_separated_by_commas(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "Missing comma"):
                func("INST COLLECT with TYPE NORMAL DURATION 5")

    def test_cmd_complains_if_parameters_dont_have_values(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "Missing value"):
                func("INST COLLECT with TYPE")

    def test_cmd_processes_parameters(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            if "raw" in name:
                target_name, cmd_name, params = func(
                    "inst", "Collect", {"TYPE": 0, "Duration": 5}
                )
            else:
                target_name, cmd_name, params = func(
                    "inst", "Collect", {"TYPE": "NORMAL", "Duration": 5}
                )
            self.assertEqual(target_name, "INST")
            self.assertEqual(cmd_name, "COLLECT")
            if "raw" in name:
                self.assertEqual(params, {"TYPE": 0, "DURATION": 5})
            else:
                self.assertEqual(params, {"TYPE": "NORMAL", "DURATION": 5})

    def test_cmd_processes_commands_without_parameters(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            target_name, cmd_name, params = func("INST", "ABORT")
            self.assertEqual(target_name, "INST")
            self.assertEqual(cmd_name, "ABORT")
            self.assertEqual(params, {})

    def test_cmd_complains_about_too_many_parameters(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
                func("INST", "COLLECT", "TYPE", "DURATION")

    def test_cmd_warns_about_required_parameters(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "Required"):
                func("INST COLLECT with DURATION 5")

    def test_cmd_warns_about_out_of_range_parameters(self):
        for name in [
            "cmd",
            "cmd_no_hazardous_check",
            "cmd_raw",
            "cmd_raw_no_hazardous_check",
        ]:
            func = globals()[name]
            if "raw" in name:
                with self.assertRaisesRegex(RuntimeError, "not in valid range"):
                    func("INST COLLECT with TYPE 0, DURATION 1000")
            else:
                with self.assertRaisesRegex(RuntimeError, "not in valid range"):
                    func("INST COLLECT with TYPE NORMAL, DURATION 1000")
        for name in [
            "cmd_no_range_check",
            "cmd_no_checks",
            "cmd_raw_no_range_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            try:
                if "raw" in name:
                    func("INST COLLECT with TYPE 0, DURATION 1000")
                else:
                    func("INST COLLECT with TYPE NORMAL, DURATION 1000")
            except RuntimeError:
                self.fail(f"{name} raised RuntimeError unexpectedly!")

    def test_cmd_warns_about_hazardous_parameters(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_raw",
            "cmd_raw_no_range_check",
        ]:
            func = globals()[name]
            if "raw" in name:
                with self.assertRaisesRegex(HazardousError, "Hazardous"):
                    func("INST COLLECT with TYPE 1")
            else:
                with self.assertRaisesRegex(HazardousError, "Hazardous"):
                    func("INST COLLECT with TYPE SPECIAL")
        for name in [
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            try:
                if "raw" in name:
                    func("INST COLLECT with TYPE 1")
                else:
                    func("INST COLLECT with TYPE SPECIAL")
            except HazardousError:
                self.fail(f"{name} raised HazardousError unexpectedly!")

    def test_cmd_warns_about_hazardous_commands(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_raw",
            "cmd_raw_no_range_check",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(HazardousError, "Hazardous"):
                func("INST CLEAR")
        for name in [
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            try:
                func("INST CLEAR")
            except HazardousError:
                self.fail(f"{name} raised HazardousError unexpectedly!")

    def test_times_out_if_the_interface_does_not_process_the_command(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "Must be numeric"):
                func("INST", "ABORT", timeout="YES")
            self.process = False
            with self.assertRaisesRegex(
                RuntimeError, "Timeout of 5s waiting for cmd ack"
            ):
                func("INST", "ABORT")

    def test_cmd_log_message_output(self):
        for name in [
            "cmd",
            "cmd_no_range_check",
            "cmd_no_hazardous_check",
            "cmd_no_checks",
            "cmd_raw",
            "cmd_raw_no_range_check",
            "cmd_raw_no_hazardous_check",
            "cmd_raw_no_checks",
        ]:
            func = globals()[name]

            for stdout in capture_io():
                if "raw" in name:
                    func("INST COLLECT with CCSDSVER 0, TYPE 0")
                else:
                    func("INST COLLECT with CCSDSVER 0, TYPE NORMAL")
                self.assertIn(
                    "INST COLLECT",
                    stdout.getvalue(),
                )
                # Check that the ignored parameters do not appear
                self.assertNotIn(
                    "CCSDSVER",
                    stdout.getvalue(),
                )
                # Check that the regular parameters do appear
                self.assertIn(
                    "TYPE",
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func(
                    "INST",
                    "MEMLOAD",
                    {"DATA": b"\xAA\xBB\xCC\xDD\xEE\xFF"},
                    log_message=True,
                )
                self.assertIn(
                    "INST MEMLOAD",
                    stdout.getvalue(),
                )
                # Check that the binary data was encoded
                self.assertIn(
                    "\\\\xaa\\\\xbb\\\\xcc\\\\xdd\\\\xee\\\\xff",
                    stdout.getvalue(),
                )

            with self.assertRaisesRegex(RuntimeError, "Must be True or False"):
                func("INST", "ABORT", log_message="YES")

            for stdout in capture_io():
                func("INST ABORT", log_message=True)
                self.assertIn(
                    "INST ABORT",
                    stdout.getvalue(),
                )
                # Check that the method name appears in the output
                self.assertIn(
                    name,
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func("INST ABORT", log_message=False)
                self.assertNotIn(
                    "INST ABORT",
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func("INST SETPARAMS")  # This has DISABLE_MESSAGES applied
                self.assertNotIn(
                    "INST SETPARAMS",
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func("INST SETPARAMS", log_message=True)  # Force log message
                self.assertIn(
                    "INST SETPARAMS",
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func("INST ARYCMD with ARRAY [1, 2, 3, 4]")
                self.assertIn(
                    "INST ARYCMD with ARRAY [1, 2, 3, 4]",
                    stdout.getvalue(),
                )

            # Check that array parameters are logged corre
            for stdout in capture_io():
                func(
                    "INST ASCIICMD with STRING 'NOOP'"
                )  # This has DISABLE_MESSAGES applied
                self.assertNotIn(
                    "INST ASCIICMD",
                    stdout.getvalue(),
                )

            for stdout in capture_io():
                func(
                    "INST ASCIICMD with STRING 'NOOP'", log_message=True
                )  # Force log message
                self.assertIn(
                    "INST ASCIICMD",
                    stdout.getvalue(),
                )
