# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import pytest
from openc3.utilities.extract import (
    add_cmd_parameter,
    extract_fields_from_cmd_text,
    extract_fields_from_tlm_text,
    extract_fields_from_set_tlm_text,
    extract_fields_from_check_text,
    extract_operator_and_operand_from_comparison,
    remove_quotes,
    convert_to_value,
)


class TestAddCmdParameter:
    def test_removes_quotes_and_preserves_quoted_strings(self):
        cmd_params = {}
        add_cmd_parameter("TEST", '"3"', cmd_params)
        assert cmd_params["TEST"] == "3"

    def test_converts_unquoted_strings_to_correct_value_type(self):
        cmd_params = {}
        add_cmd_parameter("TEST", "3", cmd_params)
        assert cmd_params["TEST"] == 3
        add_cmd_parameter("TEST2", "3.0", cmd_params)
        assert cmd_params["TEST2"] == 3.0
        add_cmd_parameter("TEST3", "0xA", cmd_params)
        assert cmd_params["TEST3"] == 0xA
        add_cmd_parameter("TEST4", "3e3", cmd_params)
        assert cmd_params["TEST4"] == 3e3
        add_cmd_parameter("TEST5", "Ryan", cmd_params)
        assert cmd_params["TEST5"] == "Ryan"
        add_cmd_parameter("TEST6", "3 4", cmd_params)
        assert cmd_params["TEST6"] == "3 4"


class TestExtractFieldsFromCmdText:
    def test_complains_about_empty_strings(self):
        with pytest.raises(RuntimeError, match="text must not be empty"):
            extract_fields_from_cmd_text("")

    def test_complains_about_strings_ending_with_with_but_no_params(self):
        with pytest.raises(RuntimeError, match="must be followed by parameters"):
            extract_fields_from_cmd_text("TEST COMMAND with")
        with pytest.raises(RuntimeError, match="must be followed by parameters"):
            extract_fields_from_cmd_text("TEST COMMAND with            ")

    def test_complains_if_target_or_packet_name_missing(self):
        with pytest.raises(RuntimeError, match="Both Target Name and Command Name must be given"):
            extract_fields_from_cmd_text("TEST")

    def test_complains_if_too_many_words_before_with(self):
        with pytest.raises(RuntimeError, match="Only Target Name and Command Name must be given"):
            extract_fields_from_cmd_text("TEST TEST TEST")

    def test_complains_if_key_value_pairs_are_malformed(self):
        with pytest.raises(RuntimeError, match="Missing value for last command parameter"):
            extract_fields_from_cmd_text("TEST TEST with KEY VALUE, KEY VALUE, VALUE")
        with pytest.raises(RuntimeError, match="Missing comma in command parameters"):
            extract_fields_from_cmd_text("TEST TEST with KEY VALUE KEY VALUE")
        with pytest.raises(RuntimeError, match="Missing comma in command parameters"):
            extract_fields_from_cmd_text("TEST TEST with KEY VALUE KEY, KEY VALUE")
        with pytest.raises(RuntimeError, match="Missing value for last command parameter"):
            extract_fields_from_cmd_text("TEST TEST with KEY VALUE, KEY")

    def test_parses_commands_correctly(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1, KEY2 2, KEY3 '3', KEY4 4.0")
        assert result == ("TARGET", "PACKET", {"KEY1": "VALUE1", "KEY2": 2, "KEY3": "3", "KEY4": 4.0})

    def test_handles_multiple_array_parameters(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 [1,2,3,4], KEY2 2, KEY3 '3', KEY4 [5, 6, 7, 8]")
        assert result == ("TARGET", "PACKET", {"KEY1": [1, 2, 3, 4], "KEY2": 2, "KEY3": "3", "KEY4": [5, 6, 7, 8]})

        result = extract_fields_from_cmd_text(
            "TARGET PACKET with KEY1 [1,2,3,4], KEY2 2, KEY3 '3', KEY4 ['1', '2', '3', '4']"
        )
        assert result == (
            "TARGET",
            "PACKET",
            {"KEY1": [1, 2, 3, 4], "KEY2": 2, "KEY3": "3", "KEY4": ["1", "2", "3", "4"]},
        )


class TestExtractFieldsFromTlmText:
    def test_requires_exactly_target_packet_item(self):
        with pytest.raises(RuntimeError, match="Telemetry Item must be specified as"):
            extract_fields_from_tlm_text("")
        with pytest.raises(RuntimeError, match="Telemetry Item must be specified as"):
            extract_fields_from_tlm_text("TARGET")
        with pytest.raises(RuntimeError, match="Telemetry Item must be specified as"):
            extract_fields_from_tlm_text("TARGET PACKET")
        with pytest.raises(RuntimeError, match="Telemetry Item must be specified as"):
            extract_fields_from_tlm_text("TARGET PACKET         ")
        with pytest.raises(RuntimeError, match="Telemetry Item must be specified as"):
            extract_fields_from_tlm_text("TARGET PACKET ITEM OTHER")

    def test_parses_telemetry_names_correctly(self):
        assert extract_fields_from_tlm_text("TARGET PACKET ITEM") == ("TARGET", "PACKET", "ITEM")
        assert extract_fields_from_tlm_text("        TARGET         PACKET       ITEM        ") == (
            "TARGET",
            "PACKET",
            "ITEM",
        )


class TestExtractFieldsFromSetTlmText:
    def test_complains_if_formatted_incorrectly(self):
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET ITEM")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET ITEM=")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET ITEM=      ")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET ITEM =")
        with pytest.raises(RuntimeError, match="Set Telemetry Item must be specified as"):
            extract_fields_from_set_tlm_text("TARGET PACKET ITEM =     ")

    def test_parses_set_tlm_text_correctly(self):
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM= 5") == ("TARGET", "PACKET", "ITEM", 5)
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM = 5") == ("TARGET", "PACKET", "ITEM", 5)
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM =5") == ("TARGET", "PACKET", "ITEM", 5)
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM=5") == ("TARGET", "PACKET", "ITEM", 5)
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM = 5.0") == ("TARGET", "PACKET", "ITEM", 5.0)
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM = Ryan") == ("TARGET", "PACKET", "ITEM", "Ryan")
        assert extract_fields_from_set_tlm_text("TARGET PACKET ITEM = [1,2,3]") == (
            "TARGET",
            "PACKET",
            "ITEM",
            [1, 2, 3],
        )


class TestExtractFieldsFromCheckText:
    def test_complains_if_formatted_incorrectly(self):
        with pytest.raises((RuntimeError, ValueError), match="Check improperly specified"):
            extract_fields_from_check_text("")
        with pytest.raises((RuntimeError, ValueError), match="Check improperly specified"):
            extract_fields_from_check_text("TARGET")
        with pytest.raises((RuntimeError, ValueError), match="Check improperly specified"):
            extract_fields_from_check_text("TARGET PACKET")

    def test_supports_no_comparison(self):
        assert extract_fields_from_check_text("TARGET PACKET ITEM") == ("TARGET", "PACKET", "ITEM", None)
        assert extract_fields_from_check_text("TARGET PACKET ITEM             ") == ("TARGET", "PACKET", "ITEM", None)

    def test_supports_comparisons(self):
        assert extract_fields_from_check_text("TARGET PACKET ITEM == 5") == ("TARGET", "PACKET", "ITEM", "== 5")
        assert extract_fields_from_check_text("TARGET PACKET ITEM > 5") == ("TARGET", "PACKET", "ITEM", "> 5")
        assert extract_fields_from_check_text("TARGET PACKET ITEM < 5") == ("TARGET", "PACKET", "ITEM", "< 5")

    def test_supports_target_packet_items_named_the_same(self):
        assert extract_fields_from_check_text("TEST TEST TEST == 5") == ("TEST", "TEST", "TEST", "== 5")

    def test_complains_about_trying_to_do_an_equal_comparison(self):
        with pytest.raises(RuntimeError, match="ERROR: Use"):
            extract_fields_from_check_text("TARGET PACKET ITEM = 5")

    def test_handles_spaces_with_quotes_correctly(self):
        assert extract_fields_from_check_text('TARGET PACKET ITEM == "This   is  a test"') == (
            "TARGET",
            "PACKET",
            "ITEM",
            '== "This   is  a test"',
        )
        assert extract_fields_from_check_text("TARGET   PACKET  ITEM   ==    'This is  a test   '") == (
            "TARGET",
            "PACKET",
            "ITEM",
            "==    'This is  a test   '",
        )


class TestExtractOperatorAndOperandFromComparison:
    def test_parses_string_operands(self):
        assert extract_operator_and_operand_from_comparison("== 'foo'") == ("==", "foo")

    def test_parses_number_operands(self):
        assert extract_operator_and_operand_from_comparison("== 1") == ("==", 1)

    def test_parses_list_operands(self):
        assert extract_operator_and_operand_from_comparison("in [1, 2, 3]") == ("in", [1, 2, 3])

    def test_parses_none_operands(self):
        assert extract_operator_and_operand_from_comparison("== None") == ("==", None)

    def test_complains_about_invalid_operators(self):
        with pytest.raises(RuntimeError, match="ERROR: Invalid"):
            extract_operator_and_operand_from_comparison("^ 'foo'")

    def test_complains_about_unparseable_operands(self):
        with pytest.raises(RuntimeError, match="ERROR: Unable"):
            extract_operator_and_operand_from_comparison("== foo")

