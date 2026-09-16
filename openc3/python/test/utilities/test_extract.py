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
    compare_values,
    extract_fields_from_check_text,
    extract_fields_from_cmd_text,
    extract_fields_from_set_tlm_text,
    extract_fields_from_tlm_text,
    extract_operator_and_operand_from_comparison,
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

    def test_does_not_require_whitespace_after_comma(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1,KEY2 2,KEY3 '3',KEY4 4.0")
        assert result == ("TARGET", "PACKET", {"KEY1": "VALUE1", "KEY2": 2, "KEY3": "3", "KEY4": 4.0})

        # Mixed spacing around the commas
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1 ,KEY2 2, KEY3 '3' , KEY4 4.0")
        assert result == ("TARGET", "PACKET", {"KEY1": "VALUE1", "KEY2": 2, "KEY3": "3", "KEY4": 4.0})

    def test_allows_a_trailing_comma(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1, KEY2 2,")
        assert result == ("TARGET", "PACKET", {"KEY1": "VALUE1", "KEY2": 2})

    def test_complains_about_a_leading_or_duplicated_comma(self):
        for text in [
            "TARGET PACKET with ,",
            "TARGET PACKET with , KEY1 VALUE1",
            "TARGET PACKET with KEY1 VALUE1,,KEY2 2",
            "TARGET PACKET with KEY1 VALUE1,,",
        ]:
            with pytest.raises(RuntimeError, match="Missing command parameter before comma"):
                extract_fields_from_cmd_text(text)

    def test_preserves_commas_inside_quoted_strings_and_arrays(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 'A,B',KEY2 [1,2,3],KEY3 \"C, D\"")
        assert result == ("TARGET", "PACKET", {"KEY1": "A,B", "KEY2": [1, 2, 3], "KEY3": "C, D"})

    def test_handles_nested_array_parameters(self):
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 [[1,2],[3,4]]")
        assert result == ("TARGET", "PACKET", {"KEY1": [[1, 2], [3, 4]]})

        # Whitespace inside the nested array and no whitespace around the delimiter
        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 [[1, 2], [3, 4]],KEY2 5")
        assert result == ("TARGET", "PACKET", {"KEY1": [[1, 2], [3, 4]], "KEY2": 5})

        result = extract_fields_from_cmd_text("TARGET PACKET with KEY1 [['1','2'],['3','4']], KEY2 [[1,2],[3,4]]")
        assert result == ("TARGET", "PACKET", {"KEY1": [["1", "2"], ["3", "4"]], "KEY2": [[1, 2], [3, 4]]})

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

    def test_parses_hex_octal_and_binary_operands(self):
        assert extract_operator_and_operand_from_comparison("== 0x0001") == ("==", 1)
        assert extract_operator_and_operand_from_comparison("== 0o17") == ("==", 15)
        assert extract_operator_and_operand_from_comparison("== 0b1010") == ("==", 10)

    def test_parses_float_operands(self):
        assert extract_operator_and_operand_from_comparison("> 1.5") == (">", 1.5)
        assert extract_operator_and_operand_from_comparison("> 1e5") == (">", 100000.0)

    def test_parses_bytes_operands(self):
        assert extract_operator_and_operand_from_comparison("== b'\\xff'") == ("==", b"\xff")

    def test_complains_about_unparsable_operands(self):
        with pytest.raises(RuntimeError, match="ERROR: Unable"):
            extract_operator_and_operand_from_comparison("== 1.2.3")

    def test_suggests_a_string_for_bare_word_operands(self):
        with pytest.raises(NameError, match="Uninitialized constant foo. Did you mean 'foo' as a string"):
            extract_operator_and_operand_from_comparison("== foo")

    def test_processes_escape_sequences_using_python_string_literal_rules(self):
        assert extract_operator_and_operand_from_comparison(r'== "line\nnext"') == ("==", "line\nnext")
        assert extract_operator_and_operand_from_comparison(r"== 'line\nnext'") == ("==", "line\nnext")
        assert extract_operator_and_operand_from_comparison(r"== 'tab\there'") == ("==", "tab\there")
        assert extract_operator_and_operand_from_comparison(r"== 'it\'s'") == ("==", "it's")

    def test_requires_a_single_complete_quoted_literal(self):
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("== 'a' garbage 'b'")
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("== 'unterminated")

    def test_rejects_ambiguous_leading_zero_integers(self):
        # Ruby reads 010 as octal 8 while Python rejects it outright so require 0o10 or 10
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand: 010"):
            extract_operator_and_operand_from_comparison("== 010")
        assert extract_operator_and_operand_from_comparison("== 0o10") == ("==", 8)
        assert extract_operator_and_operand_from_comparison("== 10") == ("==", 10)
        # A leading zero is not ambiguous for a float
        assert extract_operator_and_operand_from_comparison("== 010.5") == ("==", 10.5)

    def test_parses_numbers_with_underscore_separators(self):
        assert extract_operator_and_operand_from_comparison("== 1_000") == ("==", 1000)
        assert extract_operator_and_operand_from_comparison("== 1_000.5") == ("==", 1000.5)

    def test_parses_a_bytearray_repr(self):
        # tlm() returns BLOCK items as a bytearray so f"... == {data}" produces this form
        data = bytearray(b"\x00\xff")
        assert extract_operator_and_operand_from_comparison(f"== {data}") == ("==", data)
        assert extract_operator_and_operand_from_comparison("== bytearray()") == ("==", bytearray())
        assert extract_operator_and_operand_from_comparison("== bytearray([1, 2])") == ("==", bytearray(b"\x01\x02"))

    def test_rejects_a_bytearray_wrapping_anything_but_a_literal(self):
        # Only the one wrapper is recognized and its contents still go through extract_operand
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("== bytearray(open('/etc/passwd').read())")
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("== bytearray(5)")

    def test_rejects_f_string_interpolation(self):
        # The eval based implementation interpolated this. Interpolating is code execution so
        # it is now an error rather than a silent comparison against the uninterpolated text.
        with pytest.raises(RuntimeError, match="String interpolation is not supported in an operand"):
            extract_operator_and_operand_from_comparison("== f'{1 + 1}'")
        with pytest.raises(RuntimeError, match="String interpolation is not supported in an operand"):
            extract_operator_and_operand_from_comparison('== f"{x}"')
        # A brace in a plain string is literal text
        assert extract_operator_and_operand_from_comparison("== '{1 + 1}'") == ("==", "{1 + 1}")

    def test_parses_list_elements_with_the_same_rules_as_a_bare_operand(self):
        assert extract_operator_and_operand_from_comparison("in ['ON', 'OFF']") == ("in", ["ON", "OFF"])
        assert extract_operator_and_operand_from_comparison("in [0xA, 0o17, 1_000]") == ("in", [10, 15, 1000])
        assert extract_operator_and_operand_from_comparison("in [True, None]") == ("in", [True, None])
        assert extract_operator_and_operand_from_comparison("in []") == ("in", [])
        assert extract_operator_and_operand_from_comparison("in [[1, 2], [3]]") == ("in", [[1, 2], [3]])
        # Commas and brackets inside a quoted element do not split it
        assert extract_operator_and_operand_from_comparison("in ['a,b', '[c]']") == ("in", ["a,b", "[c]"])

    def test_allows_a_trailing_comma_like_a_ruby_or_python_list_literal(self):
        assert extract_operator_and_operand_from_comparison("in [1,]") == ("in", [1])

    def test_rejects_malformed_lists(self):
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("in [1,,2]")
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("in [,1]")
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("in [1, 2]]")
        with pytest.raises(RuntimeError, match="ERROR: Unable to parse operand"):
            extract_operator_and_operand_from_comparison("in ['unterminated]")

    def test_allows_underscore_separators_in_an_exponent(self):
        assert extract_operator_and_operand_from_comparison("== 1e1_0") == ("==", 1e10)

    def test_requires_a_list_operand_for_the_in_operator(self):
        with pytest.raises(RuntimeError, match="ERROR: The 'in' operator requires a list operand"):
            extract_operator_and_operand_from_comparison("in 'abc'")
        with pytest.raises(RuntimeError, match="ERROR: The 'in' operator requires a list operand"):
            extract_operator_and_operand_from_comparison("in 5")


class TestCompareValues:
    def test_compares_with_all_the_supported_operators(self):
        assert compare_values(1, "==", 1) is True
        assert compare_values(1, "!=", 1) is False
        assert compare_values(2, ">", 1) is True
        assert compare_values(1, ">=", 1) is True
        assert compare_values(1, "<", 2) is True
        assert compare_values(1, "<=", 1) is True
        assert compare_values(2, "in", [1, 2, 3]) is True
        assert compare_values(4, "in", [1, 2, 3]) is False

    def test_returns_false_when_the_types_can_not_be_compared(self):
        assert compare_values(None, ">", 1) is False
        assert compare_values(1, ">", None) is False
        assert compare_values("STRING", ">", 1) is False
        # 'in' is containment against a list, matching Ruby, so a str operand is not a match
        assert compare_values(1, "in", 1) is False
        assert compare_values("a", "in", "abc") is False

    def test_complains_about_invalid_operators(self):
        with pytest.raises(RuntimeError, match="ERROR: Invalid operator: '&'"):
            compare_values(1, "&", 1)
