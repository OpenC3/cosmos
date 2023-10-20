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
from openc3.models.target_model import TargetModel


class Proxy:
    def tlm(target_name, packet_name, item_name, type, scope):
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
                return b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            case "ARY":
                return [2, 3, 4]
            case _:
                return None


@patch("openc3.script.API_SERVER", Proxy)
class TestApiShared(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        #     case 'RECEIVED_COUNT':
        #       if self.count:
        #         received_count += 1
        #         received_count
        #       else:
        #         None

        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

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
            f"CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5",
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


# class CheckToleranceRaw(unittest.TestCase):
#     def test_checks_that_a_value_is_within_a_tolerance(self):
#         for stdout in capture_io():
#           check_tolerance_raw("INST HEALTH_STATUS TEMP2", 1.55, 0.1)
#           self.assertIn('CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5', stdout.getvalue())

# class CheckExpression(unittest.TestCase):
#     def test_checks_that_an_expression_is_True(self):
#         for stdout in capture_io():
#           check_expression("True == True")
#           self.assertIn('CHECK: True == True is TRUE', stdout.getvalue())
#         { check_expression("True == False") }.to raise_error(/CHECK: True == False is FALSE/)

#     def test_logs_instead_of_raises_when_disconnected(self):
#         openc3.script.DISCONNECT = True
#         for stdout in capture_io():
#           check_expression("True == False")
#           self.assertIn('CHECK: True == False is FALSE', stdout.getvalue())
#         openc3.script.DISCONNECT = False

#     def test_checks_a_logical_expression(self):
#         for stdout in capture_io():
#           check_expression("'STRING' == 'STRING'")
#           self.assertIn('CHECK: 'STRING' == 'STRING' is TRUE', stdout.getvalue())
#         { check_expression("1 == 2") }.to raise_error(/CHECK: 1 == 2 is FALSE/)
#         with self.assertRaisesRegex(AttributeError, f"Uninitialized constant STRING. Did you mean 'STRING' as a string?"):
#              check_expression("'STRING' == STRING")

# class Wait(unittest.TestCase):
#     def test_waits_for_an_indefinite_time(self):
#         for stdout in capture_io():
#           wait()
#           self.assertIn('WAIT: Indefinite for actual time of .* seconds', stdout.getvalue())

#     def test_waits_for_a_relative_time(self):
#         for stdout in capture_io():
#           wait(5)
#           self.assertIn('WAIT: 5 seconds with actual time of .* seconds', stdout.getvalue())

#     def test_raises_on_a_non_numeric_time(self):
#         { wait('5') }.to raise_error("Non-numeric wait time specified")

#     def test_waits_for_a_tgt_pkt_item(self):
#         for stdout in capture_io():
#           wait("INST HEALTH_STATUS TEMP1 > 0", 5)
#           self.assertIn('WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting .* seconds', stdout.getvalue())

#           wait("INST HEALTH_STATUS TEMP1 < 0", 0.1, 0.1) # Last param is polling rate
#           self.assertIn('WAIT: INST HEALTH_STATUS TEMP1 < 0 failed with value == 10 after waiting .* seconds', stdout.getvalue())

#           wait("INST", "HEALTH_STATUS", "TEMP1", "> 0", 5)
#           self.assertIn('WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting .* seconds', stdout.getvalue())

#           wait("INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1) # Last param is polling rate
#           self.assertIn('WAIT: INST HEALTH_STATUS TEMP1 == 0 failed with value == 10 after waiting .* seconds', stdout.getvalue())

#         { wait("INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1, 0.1) }.to raise_error(/Invalid number of arguments/)


# class WaitTolerance(unittest.TestCase):
#     def test_raises_with_invalid_params(self):
#         { wait_tolerance("INST", "HEALTH_STATUS", "TEMP2", type= 'RAW') }.to raise_error(/ERROR: Invalid number of arguments \(3\) passed to wait_tolerance/)
#         { wait_tolerance("INST", "HEALTH_STATUS", 1.55, 0.1, type= 'RAW') }.to raise_error(/ERROR: Telemetry Item must be specified/)

#     def test_raises_with_=formatted_or_=with_units(self):
#         { wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type= 'FORMATTED') }.to raise_error("Invalid type 'FORMATTED' for wait_tolerance")
#         { wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type= 'WITH_UNITS') }.to raise_error("Invalid type 'WITH_UNITS' for wait_tolerance")

#     def test_waits_for_a_value_to_be_within_a_tolerance(self):
#         for stdout in capture_io():
#           wait_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type= 'RAW')
#           self.assertIn('WAIT: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5', stdout.getvalue())
#           wait_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5"], stdout.getvalue())
#           wait_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)
#           self.assertIn(["WAIT: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5"], stdout.getvalue())

#     def test_checks_that_an_array_value_is_within_a_single_tolerance(self):
#         for stdout in capture_io():
#           wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4"], stdout.getvalue())
#           wait_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
#           self.assertIn(["INST HEALTH_STATUS ARY[0] failed to be within range 2.9 to 3.1 with value == 2"], stdout.getvalue())
#           self.assertIn(["INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["INST HEALTH_STATUS ARY[2] failed to be within range 2.9 to 3.1 with value == 4"], stdout.getvalue())

#     def test_checks_that_multiple_array_values_are_within_tolerance(self):
#         for stdout in capture_io():
#           wait_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4"], stdout.getvalue())

#           wait_tolerance("INST HEALTH_STATUS ARY", [2, 3, 4], 0.1, 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4"], stdout.getvalue())

#     def test_checks_that_an_array_value_is_within_multiple_tolerances(self):
#         for stdout in capture_io():
#           wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4"], stdout.getvalue())

#           wait_tolerance("INST HEALTH_STATUS ARY", 3, [1, 0.1, 2], 5)
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["WAIT: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4"], stdout.getvalue())

# class WaitExpression(unittest.TestCase):
#       [True, False].each do |cancel|
#         context "with wait cancelled {cancel}" do
#     def test_waits_for_an_expression(self):
#             self.sleep_cancel = cancel
#             for stdout in capture_io():
#               wait_expression("True == True", 5)
#               self.assertIn('WAIT: True == True is TRUE after waiting .* seconds', stdout.getvalue())
#               wait_expression("True == False", 0.1)
#               self.assertIn('WAIT: True == False is FALSE after waiting .* seconds', stdout.getvalue())

#     def test_checks_a_logical_expression(self):
#         for stdout in capture_io():
#           wait_expression("'STRING' == 'STRING'", 5)
#           self.assertIn('WAIT: 'STRING' == 'STRING' is TRUE after waiting .* seconds', stdout.getvalue())
#           wait_expression("1 == 2", 0.1)
#           self.assertIn('WAIT: 1 == 2 is FALSE after waiting .* seconds', stdout.getvalue())
#         with self.assertRaisesRegex(AttributeError, f"Uninitialized constant STRING. Did you mean 'STRING' as a string?"):
#              wait_expression("'STRING' == STRING", 5)

# class WaitCheck(unittest.TestCase):
#     def test_raises_with_invalid_params(self):
#         { wait_check("INST HEALTH_STATUS TEMP1") }.to raise_error(/ERROR: Invalid number of arguments \(1\) passed to wait_check/)

#     def test_checks_a_telemetry_item_against_a_value(self):
#         for stdout in capture_io():
#           wait_check("INST", "HEALTH_STATUS", "TEMP1", "> 1", 0.01, 0.1) # Last param is polling rate
#           self.assertIn(['CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10'], stdout.getvalue())
#           wait_check("INST HEALTH_STATUS TEMP1 == 1", 0.01, 0.1, type= 'RAW')
#           self.assertIn(['CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1'], stdout.getvalue())
#         { wait_check("INST HEALTH_STATUS TEMP1 > 100", 0.01) }.to raise_error(/CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10/)

#       [True, False].each do |cancel|
#         context "with wait cancelled {cancel}" do
#     def test_handles_a_block(self):
#             self.sleep_cancel = cancel

#             for stdout in capture_io():
#               wait_check("INST HEALTH_STATUS TEMP1", 0.01) do |value|
#                 value == 10
#               self.assertIn(['CHECK: INST HEALTH_STATUS TEMP1 success with value == 10'], stdout.getvalue())

#             {
#               wait_check("INST HEALTH_STATUS TEMP1", 0.01) do |value|
#                 value == 1
#             }.to raise_error(/CHECK: INST HEALTH_STATUS TEMP1 failed with value == 10/)

#     def test_logs_instead_of_raises_when_disconnected(self):
#         openc3.script.DISCONNECT = True
#         for stdout in capture_io():
#           wait_check("INST HEALTH_STATUS TEMP1 > 100", 0.01)
#           self.assertIn(['CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10'], stdout.getvalue())
#         openc3.script.DISCONNECT = False

#     def test_fails_against_binary_data(self):
#         data = "\xFF" * 10
#         with self.assertRaisesRegex(AttributeError, f"ERROR: Invalid comparison to non-ascii value"):
#              wait_check("INST HEALTH_STATUS BLOCKTEST == '{data}'", 0.01)

#     def test_warns_when_checking_a_state_against_a_constant(self):
#         for stdout in capture_io():
#           wait_check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'", 0.01)
#           self.assertIn(["CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'"], stdout.getvalue())
#         with self.assertRaisesRegex(AttributeError, f"Uninitialized constant FALSE. Did you mean 'FALSE' as a string?"):
#              wait_check("INST HEALTH_STATUS CCSDSSHF == FALSE", 0.01)

# class WaitCheckTolerance(unittest.TestCase):
#     def test_raises_with_=formatted_or_=with_units(self):
#         { wait_check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type= 'FORMATTED') }.to raise_error("Invalid type 'FORMATTED' for wait_check_tolerance")
#         { wait_check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type= 'WITH_UNITS') }.to raise_error("Invalid type 'WITH_UNITS' for wait_check_tolerance")

#     def test_checks_that_a_value_is_within_a_tolerance(self):
#         for stdout in capture_io():
#           wait_check_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type= 'RAW')
#           self.assertIn('CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5', stdout.getvalue())
#           wait_check_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
#           self.assertIn('CHECK: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5', stdout.getvalue())
#         with self.assertRaisesRegex(AttributeError, f"CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5"):
#              wait_check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)

#     def test_checks_that_an_array_value_is_within_a_single_tolerance(self):
#         for stdout in capture_io():
#           wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4"], stdout.getvalue())
#         { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2/)
#         { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[1\] was within range 2.9 to 3.1 with value == 3/)
#         { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[2\] failed to be within range 2.9 to 3.1 with value == 4/)

#     def test_logs_instead_of_raises_when_disconnected(self):
#         openc3.script.DISCONNECT = True
#         for stdout in capture_io():
#           wait_check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)
#           self.assertIn('CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5', stdout.getvalue())
#         for stdout in capture_io():
#           wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
#           self.assertIn('CHECK: INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2', stdout.getvalue())
#         openc3.script.DISCONNECT = False

#     def test_checks_that_multiple_array_values_are_within_tolerance(self):
#         for stdout in capture_io():
#           wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5)
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4"], stdout.getvalue())

#     def test_checks_that_an_array_value_is_within_multiple_tolerances(self):
#         for stdout in capture_io():
#           wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5)
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3"], stdout.getvalue())
#           self.assertIn(["CHECK: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4"], stdout.getvalue())

# class WaitCheckExpression(unittest.TestCase):
#     def test_waits_and_checks_that_an_expression_is_True(self):
#         for stdout in capture_io():
#           wait_check_expression("True == True", 5)
#           self.assertIn('CHECK: True == True is TRUE', stdout.getvalue())
#         { wait_check_expression("True == False", 0.1) }.to raise_error(/CHECK: True == False is FALSE/)

#     def test_logs_instead_of_raises_when_disconnected(self):
#         openc3.script.DISCONNECT = True
#         for stdout in capture_io():
#           wait_check_expression("True == False", 5)
#           self.assertIn('CHECK: True == False is FALSE', stdout.getvalue())
#         openc3.script.DISCONNECT = False

#     def test_waits_and_checks_a_logical_expression(self):
#         for stdout in capture_io():
#           wait_check_expression("'STRING' == 'STRING'", 5)
#           self.assertIn('CHECK: 'STRING' == 'STRING' is TRUE', stdout.getvalue())
#         { wait_check_expression("1 == 2", 0.1) }.to raise_error(/CHECK: 1 == 2 is FALSE/)
#         with self.assertRaisesRegex(AttributeError, f"Uninitialized constant STRING. Did you mean 'STRING' as a string?"):
#              wait_check_expression("'STRING' == STRING", 0.1)

#     [True, False].each do |cancel|
#       context "with wait cancelled {cancel}" do

# class WaitPacket(unittest.TestCase):
#     def setUp(self):
#             self.sleep_cancel = cancel

#     def test_prints_warning_if_packet_not_received(self):
#             self.count = False
#             for stdout in capture_io():
#               wait_packet("INST", "HEALTH_STATUS", 1, 0.5)
#               self.assertIn('WAIT: INST HEALTH_STATUS expected to be received 1 times but only received 0 times', stdout.getvalue())

#     def test_prints_success_if_the_packet_is_received(self):
#             self.count = True
#             for stdout in capture_io():
#               wait_packet("INST", "HEALTH_STATUS", 5, 0.5)
#               if cancel:
#                 self.assertIn('WAIT: INST HEALTH_STATUS expected to be received 5 times', stdout.getvalue())
#               else:
#                 self.assertIn('WAIT: INST HEALTH_STATUS received 5 times after waiting', stdout.getvalue())

# class WaitCheckPacket(unittest.TestCase):
#     def setUp(self):
#             self.sleep_cancel = cancel

#     def test_raises_a_check_error_if_packet_not_received(self):
#             self.count = False
#             { wait_check_packet("INST", "HEALTH_STATUS", 1, 0.5) }.to raise_error(/CHECK: INST HEALTH_STATUS expected to be received 1 times but only received 0 times/)

#     def test_logs_instead_of_raises_if_disconnected(self):
#             openc3.script.DISCONNECT = True
#             self.count = False
#             for stdout in capture_io():
#               wait_check_packet("INST", "HEALTH_STATUS", 1, 0.5)
#               self.assertIn('CHECK: INST HEALTH_STATUS expected to be received 1 times but only received 0 times', stdout.getvalue())
#             openc3.script.DISCONNECT = False

#     def test_prints_success_if_the_packet_is_received(self):
#             self.count = True
#             for stdout in capture_io():
#               if cancel:
#                 { wait_check_packet("INST", "HEALTH_STATUS", 5, 0.5) }.to raise_error(/CHECK: INST HEALTH_STATUS expected to be received 5 times/)
#               else:
#                 wait_check_packet("INST", "HEALTH_STATUS", 5, 0.5)
#                 self.assertIn('CHECK: INST HEALTH_STATUS received 5 times after waiting', stdout.getvalue())

# class DisableInstrumentation(unittest.TestCase):
#     def test_does_nothing_if_runningscript_is_not_defined(self):
#         for stdout in capture_io():
#           disable_instrumentation do
#             puts "HI"
#           expect(stdout.getvalue()).to match("HI")

#     def test_sets_runningscript.instance.use_instrumentation(self):
# class RunningScript:
#           self.struct = OpenStruct()
#           self.struct.use_instrumentation = True
#           def self.instance:
#             self.struct
#         for stdout in capture_io():
#           self.assertTrue(RunningScript.instance.use_instrumentation)
#           disable_instrumentation do
#             self.assertFalse(RunningScript.instance.use_instrumentation)
#             puts "HI"
#           self.assertTrue(RunningScript.instance.use_instrumentation)
#           expect(stdout.getvalue()).to match("HI")

# class GetLineDelay, setLineDelay(unittest.TestCase):
#     def test_gets_and_sets_runningscript.line_delay(self):
# class RunningScript:
#           instance_attr_accessor :line_delay

#         set_line_delay(10)
#         self.assertEqual(RunningScript.line_delay,  10)
#         self.assertEqual(get_line_delay(),  10)

# class GetMaxOutput, setMaxOutput(unittest.TestCase):
#     def test_gets_and_sets_runningscript.max_output_characters(self):
# class RunningScript:
#           instance_attr_accessor :max_output_characters

#         set_max_output(100)
#         self.assertEqual(RunningScript.max_output_characters,  100)
#         self.assertEqual(get_max_output(),  100)

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
