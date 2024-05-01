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
from unittest.mock import *
from test.test_helper import *
from openc3.script.api_shared import *

cancel = False
count = True
received_count = 0


class Proxy:
    def tlm(target_name, packet_name, item_name, type="CONVERTED", scope="DEFAULT"):
        global count
        global received_count

        if scope != "DEFAULT":
            raise RuntimeError(f"Packet '{target_name} {packet_name}' does not exist")
        match item_name:
            case "TEMP1":
                match type:
                    case "RAW":
                        return 1
                    case "CONVERTED":
                        return 10
                    case "FORMATTED":
                        return "10.000"
                    case "WITH_UNITS":
                        return "10.000 C"
            case "TEMP2":
                match type:
                    case "RAW":
                        return 1.5
                    case "CONVERTED":
                        return 10.5
            case "CCSDSSHF":
                return "FALSE"
            case "BLOCKTEST":
                return b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"
            case "ARY":
                return [2, 3, 4]
            case "RECEIVED_COUNT":
                if count:
                    received_count += 1
                    print(f"RECEIVED_COUNT:{received_count}")
                    return received_count
                else:
                    return None
            case _:
                return None


# sleep in a script - returns true if canceled mid sleep
def my_openc3_script_sleep(sleep_time=None):
    global cancel
    return cancel


@patch("openc3.script.API_SERVER", Proxy)
@patch("openc3.script.api_shared.openc3_script_sleep", my_openc3_script_sleep)
class TestApiShared(unittest.TestCase):
    def setUp(self):
        global received_count
        global cancel
        global count
        received_count = 0
        cancel = False
        count = True

        mock_redis(self)
        setup_system()

    def test_check_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError, r"ERROR: Invalid number of arguments \(2\) passed to check"
        ):
            check("INST", "HEALTH_STATUS")

    def test_check_raises_when_checking_against_binary(self):
        with self.assertRaisesRegex(
            RuntimeError, "ERROR: Invalid comparison to non-ascii value"
        ):
            check("INST HEALTH_STATUS TEMP1 == \xFF")

    def test_check_prints_the_value_with_no_comparision(self):
        for stdout in capture_io():
            check("INST", "HEALTH_STATUS", "TEMP1")
            self.assertIn("CHECK: INST HEALTH_STATUS TEMP1 == 10", stdout.getvalue())
            check("INST HEALTH_STATUS TEMP1", type="RAW")
            self.assertIn("CHECK: INST HEALTH_STATUS TEMP1 == 1", stdout.getvalue())

    def test_check_checks_a_telemetry_item_against_a_value(self):
        for stdout in capture_io():
            check("INST", "HEALTH_STATUS", "TEMP1", "> 1")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10",
                stdout.getvalue(),
            )
            check("INST HEALTH_STATUS TEMP1 == 1", type="RAW")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10",
        ):
            check("INST HEALTH_STATUS TEMP1 > 100")

    def test_check_logs_instead_of_raises_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            check("INST HEALTH_STATUS TEMP1 > 100")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10",
                stdout.getvalue(),
            )
        openc3.script.DISCONNECT = False

    def test_check_warns_when_checking_a_state_against_a_constant(self):
        for stdout in capture_io():
            check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            NameError,
            "Uninitialized constant FALSE. Did you mean 'FALSE' as a string?",
        ):
            check("INST HEALTH_STATUS CCSDSSHF == FALSE")

    def test_checks_against_the_specified_type(self):
        for stdout in capture_io():
            check_raw("INST HEALTH_STATUS TEMP1 == 1")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == 1 success", stdout.getvalue()
            )
            check_formatted("INST HEALTH_STATUS TEMP1 == '10.000'")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == '10.000' success", stdout.getvalue()
            )
            check_with_units("INST HEALTH_STATUS TEMP1 == '10.000 C'")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == '10.000 C' success",
                stdout.getvalue(),
            )

    def test_checks_that_the_exception_is_raised_in_our_apis(self):
        for stdout in capture_io():
            check_exception(
                "check", "INST HEALTH_STATUS TEMP1 == 9", type="RAW", scope="DEFAULT"
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == 9 failed", stdout.getvalue()
            )
            check_exception(
                "check", "INST HEALTH_STATUS TEMP1 == 9", type="RAW", scope="OTHER"
            )
            self.assertIn(
                "Packet 'INST HEALTH_STATUS' does not exist", stdout.getvalue()
            )

    def test_raises_if_the_exception_is_not_raised(self):
        with self.assertRaisesRegex(
            CheckError,
            r"check\(INST HEALTH_STATUS TEMP1 == 10\) should have raised an exception but did not",
        ):
            check_exception("check", "INST HEALTH_STATUS TEMP1 == 10")

    def test_check_tolerance_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError,
            r"ERROR: Invalid number of arguments \(4\) passed to check_tolerance",
        ):
            check_tolerance("INST", "HEALTH_STATUS", 1.55, 0.1, type="RAW")

    def test_check_tolerance_raises_with_formatted_or_with_units(self):
        with self.assertRaisesRegex(
            RuntimeError, r"Invalid type 'FORMATTED' for check_tolerance"
        ):
            check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type="FORMATTED")
        with self.assertRaisesRegex(
            RuntimeError, r"Invalid type 'WITH_UNITS' for check_tolerance"
        ):
            check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type="WITH_UNITS")

    def test_checks_that_a_value_is_within_a_tolerance(self):
        for stdout in capture_io():
            check_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, type="RAW")
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65 with value == 1.5",
                stdout.getvalue(),
            )
            check_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01)
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            "CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5",
        ):
            check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1)

    def test_check_tolerance_logs_instead_of_raises_exception_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1)
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5",
                stdout.getvalue(),
            )
        for stdout in capture_io():
            check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1)
            self.assertIn(
                "INST HEALTH_STATUS ARY[0] failed to be within range 2.9 to 3.1 with value == 2",
                stdout.getvalue(),
            )
        openc3.script.DISCONNECT = False

    def test_checks_that_an_array_value_is_within_a_single_tolerance(self):
        for stdout in capture_io():
            check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1)
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2",
        ):
            check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1)
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[1\] was within range 2.9 to 3.1 with value == 3",
        ):
            check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1)
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[2\] failed to be within range 2.9 to 3.1 with value == 4",
        ):
            check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1)

    def test_checks_that_multiple_array_values_are_within_tolerance(self):
        for stdout in capture_io():
            check_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1)
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2",
        ):
            check_tolerance("INST HEALTH_STATUS ARY", [3, 3, 4], 0.1)
        with self.assertRaisesRegex(
            RuntimeError, r"ERROR: Invalid array size for expected_value"
        ):
            check_tolerance("INST HEALTH_STATUS ARY", [1, 2, 3, 4], 0.1)

    def test_checks_that_an_array_value_is_within_multiple_tolerances(self):
        for stdout in capture_io():
            check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2])
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2",
        ):
            check_tolerance("INST HEALTH_STATUS ARY", 3, [0.1, 0.1, 2])
        with self.assertRaisesRegex(
            RuntimeError, r"ERROR: Invalid array size for tolerance"
        ):
            check_tolerance("INST HEALTH_STATUS ARY", 3, [0.1, 0.1, 2, 3])

    def test_checks_that_an_expression_is_true(self):
        for stdout in capture_io():
            check_expression("True == True")
            self.assertIn("CHECK: True == True is TRUE", stdout.getvalue())
        with self.assertRaisesRegex(CheckError, "CHECK: True == False is FALSE"):
            check_expression("True == False")

    def test_check_expression_logs_instead_of_raises_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            check_expression("True == False")
            self.assertIn("CHECK: True == False is FALSE", stdout.getvalue())
        openc3.script.DISCONNECT = False

    def test_checks_a_logical_expression(self):
        for stdout in capture_io():
            check_expression("'STRING' == 'STRING'")
            self.assertIn("CHECK: 'STRING' == 'STRING' is TRUE", stdout.getvalue())
        with self.assertRaisesRegex(CheckError, "CHECK: 1 == 2 is FALSE"):
            check_expression("1 == 2")
        with self.assertRaisesRegex(
            NameError,
            "Uninitialized constant STRING. Did you mean 'STRING' as a string?",
        ):
            check_expression("'STRING' == STRING")

    def test_waits_for_an_indefinite_time(self):
        for stdout in capture_io():
            result = wait()
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "WAIT: Indefinite for actual time of 0.000 seconds", stdout.getvalue()
            )

    def test_waits_for_a_relative_time(self):
        for stdout in capture_io():
            result = wait(0.2)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "WAIT: 0.2 seconds with actual time of 0.000", stdout.getvalue()
            )

    def test_raises_on_a_non_numeric_time(self):
        with self.assertRaisesRegex(RuntimeError, "Non-numeric wait time specified"):
            wait("LONG")

    def test_waits_for_a_tgt_pkt_item(self):
        for stdout in capture_io():
            result = wait("INST HEALTH_STATUS TEMP1 > 0", 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting 0.0",
                stdout.getvalue(),
            )

            result = wait(
                "INST HEALTH_STATUS TEMP1 < 0", 0.1, 0.1
            )  # Last param is polling rate
            self.assertFalse(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP1 < 0 failed with value == 10 after waiting 0.1",
                stdout.getvalue(),
            )

            result = wait("INST", "HEALTH_STATUS", "TEMP1", "> 0", 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting 0.0",
                stdout.getvalue(),
            )

            result = wait(
                "INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1
            )  # Last param is polling rate
            self.assertFalse(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP1 == 0 failed with value == 10 after waiting 0.1",
                stdout.getvalue(),
            )

        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            wait("INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1, 0.1)

    def test_wait_tolerance_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError,
            r"ERROR: Invalid number of arguments \(3\) passed to wait_tolerance",
        ):
            wait_tolerance("INST", "HEALTH_STATUS", "TEMP2", type="RAW")
        with self.assertRaisesRegex(
            RuntimeError, "ERROR: Telemetry Item must be specified"
        ):
            wait_tolerance("INST", "HEALTH_STATUS", 1.55, 0.1, type="RAW")

    def test_wait_tolerance_raises_with_formatted_or_with_units(self):
        with self.assertRaisesRegex(
            RuntimeError, "Invalid type 'FORMATTED' for wait_tolerance"
        ):
            wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type="FORMATTED")
        with self.assertRaisesRegex(
            RuntimeError, "Invalid type 'WITH_UNITS' for wait_tolerance"
        ):
            wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type="WITH_UNITS")

    def test_waits_for_a_value_to_be_within_a_tolerance(self):
        for stdout in capture_io():
            result = wait_tolerance(
                "INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type="RAW"
            )
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65 with value == 1.5 after waiting 0.0",
                stdout.getvalue(),
            )
            result = wait_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5 after waiting 0.0",
                stdout.getvalue(),
            )
            result = wait_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)
            self.assertFalse(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5 after waiting 0.1",
                stdout.getvalue(),
            )

    def test_waits_that_an_array_value_is_within_a_single_tolerance(self):
        for stdout in capture_io():
            result = wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4",
                stdout.getvalue(),
            )
            result = wait_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
            self.assertFalse(result)
            self.assertIn(
                "INST HEALTH_STATUS ARY[0] failed to be within range 2.9 to 3.1 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "INST HEALTH_STATUS ARY[2] failed to be within range 2.9 to 3.1 with value == 4",
                stdout.getvalue(),
            )

    def test_waits_that_multiple_array_values_are_within_tolerance(self):
        for stdout in capture_io():
            result = wait_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4",
                stdout.getvalue(),
            )

            result = wait_tolerance("INST HEALTH_STATUS ARY", [2, 3, 4], 0.1, 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4",
                stdout.getvalue(),
            )

    def test_waits_that_an_array_value_is_within_multiple_tolerances(self):
        for stdout in capture_io():
            result = wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4",
                stdout.getvalue(),
            )

            result = wait_tolerance("INST HEALTH_STATUS ARY", 3, [1, 0.1, 2], 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "WAIT: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4",
                stdout.getvalue(),
            )

    def test_waits_for_an_expression(self):
        for stdout in capture_io():
            result = wait_expression("True == True", 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: True == True is TRUE after waiting 0.0",
                stdout.getvalue(),
            )
            result = wait_expression("True == False", 0.1)
            self.assertFalse(result)
            self.assertIn(
                "WAIT: True == False is FALSE after waiting 0.1", stdout.getvalue()
            )

    def test_waits_for_a_logical_expression(self):
        for stdout in capture_io():
            result = wait_expression("'STRING' == 'STRING'", 5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: 'STRING' == 'STRING' is TRUE after waiting 0.0",
                stdout.getvalue(),
            )
            result = wait_expression("1 == 2", 0.1)
            self.assertFalse(result)
            self.assertIn("WAIT: 1 == 2 is FALSE after waiting", stdout.getvalue())
        with self.assertRaisesRegex(
            NameError,
            "Uninitialized constant STRING. Did you mean 'STRING' as a string?",
        ):
            wait_expression("'STRING' == STRING", 5)

    def test_wait_check_raises_with_invalid_params(self):
        with self.assertRaisesRegex(
            RuntimeError,
            r"ERROR: Invalid number of arguments \(1\) passed to wait_check",
        ):
            wait_check("INST HEALTH_STATUS TEMP1")

    def test_checks_a_telemetry_item_against_a_value(self):
        for stdout in capture_io():
            result = wait_check(
                "INST", "HEALTH_STATUS", "TEMP1", "> 1", 0.01, 0.1
            )  # Last param is polling rate
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10",
                stdout.getvalue(),
            )
            result = wait_check("INST HEALTH_STATUS TEMP1 == 1", 0.01, 0.1, type="RAW")
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            "CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10 after waiting 0.01",
        ):
            wait_check("INST HEALTH_STATUS TEMP1 > 100", 0.01)

    def test_wait_check_logs_instead_of_raises_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            result = wait_check("INST HEALTH_STATUS TEMP1 > 100", 0.01)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10",
                stdout.getvalue(),
            )
        openc3.script.DISCONNECT = False

    def test_fails_against_binary_data(self):
        data = "\xFF" * 10
        with self.assertRaisesRegex(
            RuntimeError, "ERROR: Invalid comparison to non-ascii value"
        ):
            wait_check(f"INST HEALTH_STATUS BLOCKTEST == {data}", 0.01)
        data = b"\xFF" * 10
        result = wait_check(f"INST HEALTH_STATUS BLOCKTEST == {data}", 0.01)
        self.assertTrue(isinstance(result, float))
        data = "\xFF" * 10
        with self.assertRaisesRegex(
            RuntimeError, "ERROR: Invalid comparison to non-ascii value"
        ):
            wait_check(f"INST HEALTH_STATUS BLOCKTEST == '{data}'", 0.01)
        data = b"\xFF" * 10
        with self.assertRaises(SyntaxError):
            wait_check(f"INST HEALTH_STATUS BLOCKTEST == '{data}'", 0.01)

    def test_warns_when_checking_a_state_against_a_constant(self):
        for stdout in capture_io():
            result = wait_check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'", 0.01)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            NameError,
            "Uninitialized constant FALSE. Did you mean 'FALSE' as a string?",
        ):
            wait_check("INST HEALTH_STATUS CCSDSSHF == FALSE", 0.01)

    def test_wait_check_tolerance_raises_with_formatted_or_with_units(self):
        with self.assertRaisesRegex(
            RuntimeError, r"Invalid type 'FORMATTED' for wait_check_tolerance"
        ):
            wait_check_tolerance(
                "INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type="FORMATTED"
            )
        with self.assertRaisesRegex(
            RuntimeError, r"Invalid type 'WITH_UNITS' for wait_check_tolerance"
        ):
            wait_check_tolerance(
                "INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type="WITH_UNITS"
            )

    def test_wait_checks_that_a_value_is_within_a_tolerance(self):
        for stdout in capture_io():
            result = wait_check_tolerance(
                "INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type="RAW"
            )
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65 with value == 1.5",
                stdout.getvalue(),
            )
            result = wait_check_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5",
        ):
            wait_check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)

    def test_wait_checks_that_an_array_value_is_within_a_single_tolerance(self):
        for stdout in capture_io():
            result = wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4",
                stdout.getvalue(),
            )
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2",
        ):
            wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[1\] was within range 2.9 to 3.1 with value == 3",
        ):
            wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
        with self.assertRaisesRegex(
            CheckError,
            r"CHECK: INST HEALTH_STATUS ARY\[2\] failed to be within range 2.9 to 3.1 with value == 4",
        ):
            wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)

    def test_wait_check_tolerance_logs_instead_of_raises_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            result = wait_check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5",
                stdout.getvalue(),
            )
        for stdout in capture_io():
            result = wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] failed to be within range 2.9 to 3.1 with value == 2",
                stdout.getvalue(),
            )
        openc3.script.DISCONNECT = False

    def test_wait_checks_that_multiple_array_values_are_within_tolerance(self):
        for stdout in capture_io():
            result = wait_check_tolerance(
                "INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5
            )
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4",
                stdout.getvalue(),
            )

    def test_wait_checks_that_an_array_value_is_within_multiple_tolerances(self):
        for stdout in capture_io():
            result = wait_check_tolerance(
                "INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5
            )
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3",
                stdout.getvalue(),
            )
            self.assertIn(
                "CHECK: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4",
                stdout.getvalue(),
            )

    def test_waits_and_checks_that_an_expression_is_true(self):
        for stdout in capture_io():
            result = wait_check_expression("True == True", 5)
            self.assertTrue(isinstance(result, float))
            self.assertIn("CHECK: True == True is TRUE", stdout.getvalue())
        with self.assertRaisesRegex(CheckError, "CHECK: True == False is FALSE"):
            wait_check_expression("True == False", 0.1)

    def test_wait_check_expression_logs_instead_of_raises_when_disconnected(self):
        openc3.script.DISCONNECT = True
        for stdout in capture_io():
            result = wait_check_expression("True == False", 5)
            self.assertTrue(isinstance(result, float))
            self.assertIn("CHECK: True == False is FALSE", stdout.getvalue())
        openc3.script.DISCONNECT = False

    def test_waits_and_checks_a_logical_expression(self):
        for stdout in capture_io():
            result = wait_check_expression("'STRING' == 'STRING'", 5)
            self.assertTrue(isinstance(result, float))
            self.assertIn("CHECK: 'STRING' == 'STRING' is TRUE", stdout.getvalue())
        with self.assertRaisesRegex(CheckError, "CHECK: 1 == 2 is FALSE"):
            wait_check_expression("1 == 2", 0.1)
        with self.assertRaisesRegex(
            NameError,
            "Uninitialized constant STRING. Did you mean 'STRING' as a string?",
        ):
            wait_check_expression("'STRING' == STRING", 0.1)

    def test_wait_packet_prints_warning_if_packet_not_received(self):
        global count
        count = False
        for stdout in capture_io():
            result = wait_packet("INST", "HEALTH_STATUS", 1, 0.5)
            self.assertFalse(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS expected to be received 1 times but only received 0 times",
                stdout.getvalue(),
            )

    def test_wait_packet_prints_success_if_the_packet_is_received(self):
        global cancel
        global count
        count = True
        for stdout in capture_io():
            cancel = True
            result = wait_packet("INST", "HEALTH_STATUS", 5, 0.5)
            self.assertFalse(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS expected to be received 5 times",
                stdout.getvalue(),
            )
            cancel = False
            result = wait_packet("INST", "HEALTH_STATUS", 5, 0.5)
            self.assertTrue(result)
            self.assertIn(
                "WAIT: INST HEALTH_STATUS received 5 times after waiting",
                stdout.getvalue(),
            )

    def test_wait_check_packet_raises_a_check_error_if_packet_not_received(self):
        global count
        count = False
        with self.assertRaisesRegex(
            CheckError,
            "CHECK: INST HEALTH_STATUS expected to be received 1 times but only received 0 times",
        ):
            wait_check_packet("INST", "HEALTH_STATUS", 1, 0.5)

    def test_wait_check_packet_logs_instead_of_raises_if_disconnected(self):
        openc3.script.DISCONNECT = True
        global count
        count = False
        for stdout in capture_io():
            result = wait_check_packet("INST", "HEALTH_STATUS", 1, 0.5)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS expected to be received 1 times but only received 0 times",
                stdout.getvalue(),
            )
        openc3.script.DISCONNECT = False

    def test_wait_check_packet_prints_success_if_the_packet_is_received(self):
        global cancel
        global count
        count = True
        for stdout in capture_io():
            cancel = True
            with self.assertRaisesRegex(
                CheckError,
                "CHECK: INST HEALTH_STATUS expected to be received 5 times",
            ):
                wait_check_packet("INST", "HEALTH_STATUS", 5, 0.0)
            cancel = False
            result = wait_check_packet("INST", "HEALTH_STATUS", 5, 0.5)
            self.assertTrue(isinstance(result, float))
            self.assertIn(
                "CHECK: INST HEALTH_STATUS received 5 times after waiting",
                stdout.getvalue(),
            )

    def test_does_nothing_if_runningscript_is_not_defined(self):
        for stdout in capture_io():
            with disable_instrumentation():
                print("HI")
            self.assertIn("HI", stdout.getvalue())

    def test_sets_runningscript_instance_use_instrumentation(self):
        openc3.script.RUNNING_SCRIPT = Mock()
        for stdout in capture_io():
            self.assertTrue(openc3.script.RUNNING_SCRIPT.instance.use_instrumentation)
            with disable_instrumentation():
                self.assertFalse(
                    openc3.script.RUNNING_SCRIPT.instance.use_instrumentation
                )
                print("HI")
            self.assertTrue(openc3.script.RUNNING_SCRIPT.instance.use_instrumentation)
            self.assertIn("HI", stdout.getvalue())

    def test_gets_and_sets_runningscript_line_delay(self):
        openc3.script.RUNNING_SCRIPT = Mock()
        set_line_delay(10)
        self.assertEqual(openc3.script.RUNNING_SCRIPT.line_delay, 10)
        self.assertEqual(get_line_delay(), 10)

    def test_gets_and_sets_runningscript_max_output_characters(self):
        openc3.script.RUNNING_SCRIPT = Mock()
        set_max_output(100)
        self.assertEqual(openc3.script.RUNNING_SCRIPT.max_output_characters, 100)
        self.assertEqual(get_max_output(), 100)


# class Start, loadUtility, requireUtility(unittest.TestCase):
#     def test_loads_a_script(self):
#         File.open("tester.rb", 'w') do |file|
#           file.puts "# Nothing"

#         start("tester.rb")
#         load_utility("tester.rb")
#         result = require_utility("tester")
#         self.assertTrue(result)()
#         result = require_utility("tester")
#         self.assertFalse(result)

#         File.delete('tester.rb')

#         { load_utility('tester.rb') }.to raise_error(LoadError)
#         { start('tester.rb') }.to raise_error(LoadError)
#         # Can't try tester.rb because it's already been loaded and cached
#         { require_utility('does_not_exist.rb') }.to raise_error(LoadError)
