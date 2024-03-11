# Copyright 2024 OpenC3, Inc.
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
import struct
import unittest
import threading
from unittest.mock import *
from test.test_helper import *
from openc3.api.cmd_api import *
from openc3.interfaces.interface import Interface
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.microservices.interface_microservice import InterfaceCmdHandlerThread
from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.top_level import HazardousError


class MyInterface(Interface):
    interface_data = ""

    def connected(self):
        return True

    def read_interface(self):
        pass

    def write_interface(self, data, extra=None):
        MyInterface.interface_data = data


class TestCmdApi(unittest.TestCase):
    def setUp(self):
        redis = mock_redis(self)
        setup_system()

        self.process = True
        orig_xread = redis.xread

        # Override xread to ignore the block and count keywords
        def xread_side_effect(*args, **kwargs):
            result = None
            if self.process:
                try:
                    result = orig_xread(*args)
                except RuntimeError:
                    pass

            # # Create a slight delay to simulate the blocking call
            if result and len(result) == 0:
                time.sleep(0.01)
            return result

        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect

        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

        # Create an Interface we can use in the InterfaceCmdHandlerThread
        # It has to have a valid list of target_names as that is what 'receive_commands'
        # in the Store uses to determine which topics to read
        self.interface = MyInterface()
        self.interface.name = "INST_INT"
        self.interface.target_names = ["INST"]
        self.interface.cmd_target_names = ["INST"]
        self.interface.tlm_target_names = ["INST"]
        model = InterfaceModel(name="INST_INT", scope="DEFAULT")
        model.create()
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

    def test_cmd_warns_about_disabled_commands(self):
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
            with self.assertRaisesRegex(DisabledError, "INST DISABLED is Disabled"):
                func("INST DISABLED")

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

    def test_enable_cmd_complains_about_unknown_commands(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            enable_cmd("INST", "BLAH")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            enable_cmd("INST   BLAH")

    def test_enable_cmd_complains_about_missing_command(self):
        with self.assertRaisesRegex(
            RuntimeError, "Target name and command name required"
        ):
            enable_cmd("INST")

    def test_disable_cmd_complains_about_unknown_command(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            disable_cmd("INST", "BLAH")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            disable_cmd("INST   BLAH")

    def test_disable_cmd_complains_about_missing_command(self):
        with self.assertRaisesRegex(
            RuntimeError, "Target name and command name required"
        ):
            disable_cmd("INST")

    def test_enable_disable_cmd(self):
        cmd("INST ABORT")
        disable_cmd("INST ABORT")
        with self.assertRaisesRegex(DisabledError, "INST ABORT is Disabled"):
            cmd("INST ABORT")
        enable_cmd("INST ABORT")
        cmd("INST ABORT")

    def test_get_cmd_buffer_complains_about_unknown_commands(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            get_cmd_buffer("INST", "BLAH")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            get_cmd_buffer("INST   BLAH")

    def test_get_cmd_buffer_returns_none_if_the_command_has_not_yet_been_sent(self):
        self.assertIsNone(get_cmd_buffer("INST", "ABORT"))
        self.assertIsNone(get_cmd_buffer("INST    ABORT"))

    def test_get_cmd_buffer_returns_a_command_packet_buffer(self):
        cmd("INST ABORT")
        output = get_cmd_buffer("inst", "Abort")
        self.assertEqual(struct.unpack(">H", output["buffer"][6:8])[0], 2)
        output = get_cmd_buffer("inst Abort")
        self.assertEqual(struct.unpack(">H", output["buffer"][6:8])[0], 2)
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        output = get_cmd_buffer("INST", "COLLECT")
        self.assertEqual(struct.unpack(">H", output["buffer"][6:8])[0], 1)
        output = get_cmd_buffer("INST  COLLECT")
        self.assertEqual(struct.unpack(">H", output["buffer"][6:8])[0], 1)

    def test_send_raw_raises_on_unknown_interfaces(self):
        with self.assertRaisesRegex(
            RuntimeError, "Interface 'BLAH_INT' does not exist"
        ):
            send_raw("BLAH_INT", b"\x00\x01\x02\x03")

    def test_send_raw_sends_raw_data_to_an_interface(self):
        send_raw("inst_int", b"\x00\x01\x02\x03")
        time.sleep(0.01)
        self.assertEqual(MyInterface.interface_data, b"\x00\x01\x02\x03")

    def test_get_all_commands_complains_with_a_unknown_target(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            get_all_cmds("BLAH")

    def test_get_all_commands_returns_an_array_of_commands_as_hashes(self):
        result = get_all_cmds("inst")
        self.assertEqual(type(result), list)
        for command in result:
            self.assertEqual(type(command), dict)
            self.assertEqual(command["target_name"], ("INST"))
            self.assertIn("target_name", command.keys())
            self.assertIn("packet_name", command.keys())
            self.assertIn("description", command.keys())
            self.assertIn("endianness", command.keys())
            self.assertIn("items", command.keys())

    def test_get_all_command_names_returns_empty_array_with_a_unknown_target(self):
        self.assertEqual(get_all_cmd_names("BLAH"), [])

    def test_get_all_command_names_returns_an_array_of_command_names(self):
        result = get_all_cmd_names("inst")
        self.assertEqual(type(result), list)
        self.assertEqual(type(result[0]), str)

    def test_get_parameter_returns_parameter_hash_for_state_parameter(self):
        result = get_param("inst", "Collect", "Type")
        self.assertEqual(result["name"], "TYPE")
        self.assertEqual(list(result["states"].keys()), ["NORMAL", "SPECIAL"])
        self.assertEqual({"value": 0}, result["states"]["NORMAL"])
        self.assertEqual({"value": 1, "hazardous": ""}, result["states"]["SPECIAL"])
        result = get_param("inst Collect Type")
        self.assertEqual(result["name"], "TYPE")
        self.assertEqual(list(result["states"].keys()), ["NORMAL", "SPECIAL"])
        self.assertEqual({"value": 0}, result["states"]["NORMAL"])
        self.assertEqual({"value": 1, "hazardous": ""}, result["states"]["SPECIAL"])

    def test_get_parameter_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError, "Target name, command name and parameter name required"
        ):
            get_param("INST COLLECT")

    def test_get_parameter_returns_parameter_hash_for_array_parameter(self):
        result = get_param("INST", "ARYCMD", "ARRAY")
        self.assertEqual(result["name"], "ARRAY")
        self.assertEqual(result["bit_size"], 64)
        self.assertEqual(result["array_size"], 640)
        self.assertEqual(result["data_type"], "FLOAT")

    def test_get_command_returns_hash_for_the_command_and_parameters(self):
        result = get_cmd("inst", "Collect")
        self.assertEqual(type(result), dict)
        self.assertEqual(result["target_name"], "INST")
        self.assertEqual(result["packet_name"], "COLLECT")
        for parameter in result["items"]:
            self.assertEqual(type(parameter), dict)
            self.assertIn("name", parameter.keys())
            self.assertIn("bit_offset", parameter.keys())
            self.assertIn("bit_size", parameter.keys())
            self.assertIn("data_type", parameter.keys())
            self.assertIn("description", parameter.keys())
            self.assertIn("endianness", parameter.keys())
            self.assertIn("overflow", parameter.keys())
            # Non-Reserved items have default, min, max
            if parameter["name"] not in Packet.RESERVED_ITEM_NAMES:
                self.assertIn("default", parameter.keys())
                self.assertIn("minimum", parameter.keys())
                self.assertIn("maximum", parameter.keys())

                # Check a few of the parameters
                if parameter["name"] == "TYPE":
                    self.assertEqual(parameter["default"], 0)
                    self.assertEqual(parameter["data_type"], "UINT")
                    self.assertEqual(
                        parameter["states"],
                        (
                            {
                                "NORMAL": {"value": 0},
                                "SPECIAL": {"value": 1, "hazardous": ""},
                            }
                        ),
                    )
                    self.assertEqual(parameter["description"], "Collect type")
                    self.assertTrue(parameter["required"])
                    self.assertIsNone(parameter.get("units"))
                if parameter["name"] == "TEMP":
                    self.assertEqual(parameter["default"], 0.0)
                    self.assertEqual(parameter["data_type"], "FLOAT")
                    self.assertIsNone(parameter.get("states"))
                    self.assertEqual(parameter["description"], "Collect temperature")
                    self.assertEqual(parameter["units_full"], "Celsius")
                    self.assertEqual(parameter["units"], "C")
                    self.assertFalse(parameter["required"])

        result = get_cmd("inst   Collect")
        self.assertEqual(type(result), dict)
        self.assertEqual(result["target_name"], "INST")
        self.assertEqual(result["packet_name"], "COLLECT")

    def test_get_cmd_hazardous_returns_whether_the_command_with_parameters_is_hazardous(
        self,
    ):
        self.assertFalse(get_cmd_hazardous("inst collect with type NORMAL"))
        self.assertTrue(get_cmd_hazardous("INST COLLECT with TYPE SPECIAL"))

        self.assertFalse(get_cmd_hazardous("INST", "COLLECT", {"TYPE": "NORMAL"}))
        self.assertTrue(get_cmd_hazardous("INST", "COLLECT", {"TYPE": "SPECIAL"}))
        self.assertFalse(get_cmd_hazardous("INST", "COLLECT", {"TYPE": 0}))
        self.assertTrue(get_cmd_hazardous("INST", "COLLECT", {"TYPE": 1}))

    def test_get_cmd_hazardous_returns_whether_the_command_is_hazardous(self):
        self.assertTrue(get_cmd_hazardous("INST CLEAR"))
        self.assertTrue(get_cmd_hazardous("INST", "CLEAR"))

    def test_get_cmd_hazardous_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError, "Both Target Name and Command Name must be given"
        ):
            get_cmd_hazardous("INST")

    def test_get_cmd_hazardous_raises_with_the_wrong_number_of_arguments(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            get_cmd_hazardous("INST", "COLLECT", "TYPE", "SPECIAL")

    def test_get_cmd_value_returns_command_values(self):
        now = time.time()
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        time.sleep(0.01)
        self.assertEqual(get_cmd_value("inst collect type"), "NORMAL")
        self.assertEqual(get_cmd_value("inst collect type", type="RAW"), 0)
        self.assertEqual(get_cmd_value("INST COLLECT DURATION"), 5.0)
        self.assertAlmostEqual(
            get_cmd_value("INST COLLECT RECEIVED_TIMESECONDS"), now, 1
        )
        self.assertAlmostEqual(get_cmd_value("INST COLLECT PACKET_TIMESECONDS"), now, 1)
        self.assertEqual(get_cmd_value("INST COLLECT RECEIVED_COUNT"), 1)

        cmd("INST COLLECT with TYPE NORMAL, DURATION 7")
        time.sleep(0.01)
        self.assertEqual(get_cmd_value("INST COLLECT RECEIVED_COUNT"), 2)
        self.assertEqual(get_cmd_value("INST COLLECT DURATION"), 7.0)

    def test_get_cmd_value_returns_command_values_old_style(self):
        now = time.time()
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        time.sleep(0.01)
        self.assertEqual(get_cmd_value("inst", "collect", "type"), "NORMAL")
        self.assertEqual(get_cmd_value("INST", "COLLECT", "DURATION"), 5.0)
        self.assertAlmostEqual(
            get_cmd_value("INST", "COLLECT", "RECEIVED_TIMESECONDS"), now, 1
        )
        self.assertAlmostEqual(
            get_cmd_value("INST", "COLLECT", "PACKET_TIMESECONDS"), now, 1
        )
        self.assertEqual(get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT"), 1)

        cmd("INST COLLECT with TYPE NORMAL, DURATION 7")
        time.sleep(0.01)
        self.assertEqual(get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT"), 2)
        self.assertEqual(get_cmd_value("INST", "COLLECT", "DURATION"), 7.0)

    def test_get_cmd_time_returns_command_times(self):
        now = time.time()
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        time.sleep(0.01)
        result = get_cmd_time("inst", "collect")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertAlmostEqual(result[2], int(now), delta=1)

        result = get_cmd_time("INST")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertAlmostEqual(result[2], int(now), delta=1)

        result = get_cmd_time()
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertAlmostEqual(result[2], int(now), delta=1)

        now = time.time()
        cmd("INST ABORT")
        time.sleep(0.01)
        result = get_cmd_time("INST")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("ABORT"))  # New latest is ABORT
        self.assertAlmostEqual(result[2], int(now), delta=1)

        result = get_cmd_time()
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("ABORT"))
        self.assertAlmostEqual(result[2], int(now), delta=1)

    def test_get_cmd_time_returns_0_if_no_times_are_set(self):
        self.assertEqual(get_cmd_time("INST", "ABORT"), ("INST", "ABORT", 0, 0))
        self.assertEqual(get_cmd_time("INST"), (None, None, 0, 0))
        self.assertEqual(get_cmd_time(), (None, None, 0, 0))

    def test_get_cmd_cnt_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH ABORT' does not exist"):
            get_cmd_cnt("BLAH", "ABORT")

    def test_get_cmd_cnt_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_cmd_cnt("INST BLAH")

    def test_get_cmd_cnt_returns_the_transmit_count(self):
        start = get_cmd_cnt("inst", "collect")
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        # Send unrelated commands to ensure specific command count
        cmd("INST ABORT")
        cmd_no_hazardous_check("INST CLEAR")
        time.sleep(0.01)

        count = get_cmd_cnt("INST", "COLLECT")
        self.assertEqual(count, start + 1)
        count = get_cmd_cnt("INST   COLLECT")
        self.assertEqual(count, start + 1)

    def test_get_cmd_cnts_returns_transmit_count_for_commands(self):
        cmd("INST ABORT")
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        time.sleep(0.01)
        cnts = get_cmd_cnts([["inst", "abort"], ["INST", "COLLECT"]])
        self.assertEqual(cnts, ([1, 1]))
        cmd("INST ABORT")
        cmd("INST ABORT")
        cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        time.sleep(0.01)
        cnts = get_cmd_cnts([["INST", "ABORT"], ["INST", "COLLECT"]])
        self.assertEqual(cnts, ([3, 2]))


class BuildCommand(unittest.TestCase):
    @patch("openc3.microservices.microservice.System")
    @patch("openc3.microservices.decom_microservice.LimitsEventTopic")
    def setUp(self, mock_let, mock_system):
        redis = mock_redis(self)
        setup_system()
        mock_s3(self)

        orig_xread = redis.xread

        # Override xread to ignore the block and count keywords
        def xread_side_effect(*args, **kwargs):
            return orig_xread(*args)

        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect

        model = MicroserviceModel(
            name="DEFAULT__DECOM__INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
        )
        model.create()
        self.dm = DecomMicroservice("DEFAULT__DECOM__INST_INT")
        self.dm_thread = threading.Thread(target=self.dm.run)
        self.dm_thread.start()
        time.sleep(0.001)

    def tearDown(self):
        self.dm.shutdown()
        time.sleep(0.001)

    def test_complains_about_unknown_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Timeout of 5s waiting for cmd ack. Does target 'BLAH' exist?"
        ):
            build_cmd("BLAH COLLECT")

    def test_complains_about_unknown_commands(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            build_cmd("INST", "BLAH")

    def test_build_command_processes_a_string(self):
        cmd = build_cmd("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(cmd["target_name"], "INST")
        self.assertEqual(cmd["packet_name"], "COLLECT")
        self.assertEqual(
            cmd["buffer"],
            b"\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00@\xA0\x00\x00\xAB\x00\x00\x00\x00",
        )

    def test_complains_if_parameters_are_not_separated_by_commas(self):
        with self.assertRaisesRegex(RuntimeError, "Missing comma"):
            build_cmd("INST COLLECT with TYPE NORMAL DURATION 5")

    def test_complains_if_parameters_dont_have_values(self):
        with self.assertRaisesRegex(RuntimeError, "Missing value"):
            build_cmd("INST COLLECT with TYPE")

    def test_processes_parameters(self):
        cmd = build_cmd("inst", "Collect", {"TYPE": "NORMAL", "Duration": 5})
        self.assertEqual(cmd["target_name"], "INST")
        self.assertEqual(cmd["packet_name"], "COLLECT")
        self.assertEqual(
            cmd["buffer"],
            b"\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00@\xA0\x00\x00\xAB\x00\x00\x00\x00",
        )

    def test_processes_commands_without_parameters(self):
        cmd = build_cmd("INST", "ABORT")
        self.assertEqual(cmd["target_name"], "INST")
        self.assertEqual(cmd["packet_name"], "ABORT")
        self.assertEqual(cmd["buffer"], b"\x13\xE7\xC0\x00\x00\x00\x00\x02")  # Pkt ID 2

        cmd = build_cmd("INST CLEAR")
        self.assertEqual(cmd["target_name"], "INST")
        self.assertEqual(cmd["packet_name"], "CLEAR")
        self.assertEqual(cmd["buffer"], b"\x13\xE7\xC0\x00\x00\x00\x00\x03")  # Pkt ID 3

    def test_complains_about_too_many_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            build_cmd("INST", "COLLECT", "TYPE", "DURATION")

    def test_warns_about_required_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Required"):
            build_cmd("INST COLLECT with DURATION 5")

    def test_warns_about_out_of_range_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "not in valid range"):
            build_cmd("INST COLLECT with TYPE NORMAL, DURATION 1000")
        cmd = build_cmd(
            "INST COLLECT with TYPE NORMAL, DURATION 1000", range_check=False
        )
        self.assertEqual(cmd["target_name"], "INST")
        self.assertEqual(cmd["packet_name"], "COLLECT")
