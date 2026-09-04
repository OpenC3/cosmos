# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import ast
import re


# Tokenizer for command parameters: matches double-quoted strings, single-quoted strings,
# bracket-delimited arrays (one level of nesting), a bare comma delimiter, or bare words.
# Commas are tokenized separately so whitespace around them is optional.
SCANNING_REGULAR_EXPRESSION = re.compile(
    r""" "(?:[^\\"]|\\.)*"            # double-quoted string (with escaped chars)
       | '(?:[^\\']|\\.)*'            # single-quoted string (with escaped chars)
       | \[(?:[^\\\[\]]|\\.|\[(?:[^\\\[\]]|\\.)*\])*\]   # array, one level of nesting
       | ,                            # comma delimiter
       | [^\s,]+                      # bare word
    """,
    re.VERBOSE,
)

# Operators supported by check(), wait() and wait_check() comparisons
COMPARISON_OPERATORS = ["==", "!=", ">=", "<=", ">", "<", "in"]

# Matches Infinity and NaN which literal_eval rejects but float() accepts
INFINITY_NAN_REGEX = re.compile(r"^[+-]?(inf(inity)?|nan)$", re.IGNORECASE)

# Matches an f-string prefix. Interpolation would be code execution so it is rejected.
INTERPOLATION_REGEX = re.compile(r"^(?:[fF][rRbB]?|[rRbB][fF])['\"]")

# Matches repr() of a bytearray, e.g. bytearray(b'\\x00'). tlm() returns BLOCK items as a
# bytearray so this is the natural way to write the operand, but it is a constructor call
# rather than a literal so literal_eval rejects it.
BYTEARRAY_REGEX = re.compile(r"^bytearray\((.*)\)$", re.DOTALL)

SPLIT_WITH_REGEX = re.compile(r"\s+with\s+", re.IGNORECASE)
SPLIT_WITH_OPTIONAL_WHITESPACE_REGEX = re.compile(r"\s*with\s*", re.IGNORECASE)

# Regular expression to identify a String as a floating point number
FLOAT_CHECK_REGEX = re.compile(r"\A\s*[-+]?\d*\.\d+\s*\Z")

# Regular expression to identify a String as a floating point number in
# scientific notation
SCIENTIFIC_CHECK_REGEX = re.compile(r"\A\s*[-+]?(\d+((\.\d+)?)|(\.\d+))[eE][-+]?\d+\s*\Z")

# Regular expression to identify a String as an integer
INT_CHECK_REGEX = re.compile(r"\A\s*[-+]?\d+\s*\Z")

# Regular expression to identify a String as an integer in hexadecimal format
HEX_CHECK_REGEX = re.compile(r"\A\s*0[xX][\dabcdefABCDEF]+\s*\Z")

# Regular expression to identify a String as an Array of numbers
ARRAY_CHECK_REGEX = re.compile(r"\A\s*\[.*\]\s*\Z")

# Regular expression to identify a String as an Object
OBJECT_CHECK_REGEX = re.compile(r"\A\s*\{.*\}\s*\Z")


# Pulls all string keyword arguments into the args array.
def extract_string_kwargs_to_args(args: list, kwargs: dict):
    # Split keywords into string keywords (part of our API, e.g. "PARAM" => 123)
    for _, v in kwargs:
        args.append(v)
    return args


def remove_quotes(string: str):
    """Returns the string with leading and trailing quotes removed"""
    if (string.startswith('"') and string.endswith('"')) or (string.startswith("'") and string.endswith("'")):
        return string[1:-1]
    return string


def is_float(string):
    """Returns whether the String represents a floating point number"""
    return bool(FLOAT_CHECK_REGEX.match(string) or SCIENTIFIC_CHECK_REGEX.match(string))


def is_int(string):
    """Returns whether the String represents an integer"""
    return bool(INT_CHECK_REGEX.match(string))


def is_hex(string):
    """Whether the String represents a hexadecimal number"""
    return bool(HEX_CHECK_REGEX.match(string))


def is_array(string):
    """Whether the String represents an Array"""
    return bool(ARRAY_CHECK_REGEX.match(string))


def is_object(string):
    """Whether the String represents an Object"""
    return bool(OBJECT_CHECK_REGEX.match(string))


def convert_to_value(string):
    """Converts the String into either a Float, Integer, or Array
    depending on what the String represents. It can successfully convert
    floating point numbers in both fixed and scientific notation, integers
    in hexadecimal notation, and Arrays. If it can not be converted into
    any of the above then the original String is returned.
    """
    return_value = string
    try:
        if is_float(string):
            # Floating Point in normal or scientific notation
            return_value = float(string)
        elif is_int(string):
            # Integer
            return_value = int(string)
        elif is_hex(string):
            # Hex
            return_value = int(string, 0)
        elif is_array(string) or is_object(string):
            # Array or Object
            return_value = ast.literal_eval(string)
    except Exception:
        # Something went wrong so just return the string as is
        pass
    return return_value


def hex_to_byte_string(string):
    """Converts the String representing a hexadecimal number (i.e. "0xABCD")
    to a binary String with the same data (i.e "\xab\xcd")
    @return [String] Binary byte string"""

    # Remove leading 0x or 0X
    if string.startswith("0x") or string.startswith("0X"):
        string = string[2:]
    # fromhex only works with an even number of characters to prepend
    # a zero in case we get something like '0xA' or '0xABC'
    if len(string) % 2 == 1:
        string = f"0{string}"

    return bytearray.fromhex(string)


def add_cmd_parameter(keyword, value, cmd_params):
    quotes_removed = remove_quotes(value)
    if value == quotes_removed:
        cmd_params[keyword] = convert_to_value(value)
    else:
        cmd_params[keyword] = quotes_removed


def extract_fields_from_cmd_text(text):
    split_string = re.split(SPLIT_WITH_REGEX, text, maxsplit=1)  # 1 split, therefore 2 elements
    if len(split_string) == 0 or split_string[0] == "":
        raise RuntimeError("ERROR: text must not be empty")
    if (len(split_string) == 1 and re.search(SPLIT_WITH_OPTIONAL_WHITESPACE_REGEX, text)) or (
        len(split_string) == 2 and split_string[1] == ""
    ):
        raise RuntimeError(f"ERROR: 'with' must be followed by parameters : {text:s}")

    # Extract target_name and cmd_name
    first_half = split_string[0].split(" ")
    if len(first_half) < 2:
        raise RuntimeError(f"ERROR: Both Target Name and Command Name must be given : {text:s}")
    if len(first_half) > 2:
        raise RuntimeError(f"ERROR: Only Target Name and Command Name must be given before 'with' : {text:s}")
    target_name = first_half[0]
    cmd_name = first_half[1]
    cmd_params = {}

    if len(split_string) == 2:
        # Extract Command Parameters
        second_half = SCANNING_REGULAR_EXPRESSION.findall(split_string[1])
        keyword = None
        value = None
        for item in second_half:
            if item == ",":
                # A comma completes the current keyword / value pair.
                # A comma with nothing pending is a leading or duplicated comma.
                if keyword is None:
                    raise RuntimeError(f"Missing command parameter before comma: {text:s}")
                if value is None:
                    raise RuntimeError(f"Missing value for last command parameter: {text:s}")
                add_cmd_parameter(keyword, value, cmd_params)
                keyword = None
                value = None
            elif keyword is None:
                keyword = item
            elif value is None:
                value = item
            else:
                raise RuntimeError(f"Missing comma in command parameters: {text:s}")
        if keyword is not None:
            if value is None:
                raise RuntimeError(f"Missing value for last command parameter: {text:s}")
            add_cmd_parameter(keyword, value, cmd_params)

    return target_name, cmd_name, cmd_params


def extract_fields_from_tlm_text(text):
    split_string = text.split()
    if len(split_string) != 3:
        raise RuntimeError(f"ERROR: Telemetry Item must be specified as 'TargetName PacketName ItemName' : {text}")
    target_name = split_string[0]
    packet_name = split_string[1]
    item_name = split_string[2]
    return target_name, packet_name, item_name


def extract_fields_from_set_tlm_text(text):
    error_msg = f"ERROR: Set Telemetry Item must be specified as 'TargetName PacketName ItemName = Value' : {text}"
    # We have to handle these cases:
    # set_tlm("TGT PKT ITEM='new item'")
    # set_tlm("TGT PKT ITEM = 'new item'")
    # set_tlm("TGT PKT ITEM= 'new item'")
    # set_tlm("TGT PKT ITEM ='new item'")
    initial_split = text.split("=")
    if len(initial_split) < 2 or not initial_split[1].strip():
        raise RuntimeError(error_msg)
    parts = initial_split[0].strip().split(" ") + [initial_split[1].strip()]

    if len(parts) != 4:  # Ensure tgt,pkt,item,value
        raise RuntimeError(error_msg)
    target_name = parts[0]
    packet_name = parts[1]
    item_name = parts[2]
    value = convert_to_value(parts[3])
    if isinstance(value, str):
        value = remove_quotes(value)
    return target_name, packet_name, item_name, value


def extract_fields_from_check_text(text):
    fields_split = text.split(None, 3)  # Python: second split arg is max number of splits
    if len(fields_split) < 3:
        raise RuntimeError(f"ERROR: Check improperly specified: {text}")
    target_name, packet_name, item_name, *comparison = fields_split

    # comparison is a list, guaranteed to be of length 0 or 1 because of the split 3 with the splat operator above.
    # We need it to be either None or the comparison string.
    if len(comparison):
        comparison = comparison[0]
    else:
        comparison = None

    if comparison and len(comparison):
        operator, *_ = comparison.split(None, 1)
        if operator == "=":
            raise RuntimeError(f"ERROR: Use '==' instead of '=' in {text}")

    return target_name, packet_name, item_name, comparison


# Splits `check()` comparison expressions, e.g. "== 'foo bar'" becomes ["==", "foo bar"]
def extract_operator_and_operand_from_comparison(comparison):
    parts = comparison.split(None, 1)  # Python: second split arg is max number of splits
    operator = parts[0] if len(parts) >= 1 else None
    operand = parts[1] if len(parts) >= 2 else None

    if operand is None:
        if operator is not None:
            raise RuntimeError(f"ERROR: Invalid comparison, must specify an operand: {comparison}")
        return [None, None]

    if operator not in COMPARISON_OPERATORS:
        raise RuntimeError(f"ERROR: Invalid operator: '{operator}'")

    operand = extract_operand(operand)
    # 'in' is containment against a list of values in both Ruby and Python.
    # Enforced here so check(), wait() and wait_check() all reject the same thing.
    if operator == "in" and not isinstance(operand, list):
        raise RuntimeError(f"ERROR: The 'in' operator requires a list operand: {operand!r}")

    return operator, operand


# Converts the operand of a `check()` comparison expression into a Python value.
# Note this deliberately does not eval the operand so only literal values are supported.
def extract_operand(operand):
    # A bytearray is spelled as a constructor call around a literal. Only this one wrapper is
    # recognized and its contents still go through extract_operand, so nothing is executed.
    bytearray_match = BYTEARRAY_REGEX.match(operand)
    if bytearray_match:
        contents = bytearray_match.group(1).strip()
        if not contents:
            return bytearray()
        value = extract_operand(contents)
        if not isinstance(value, bytes | bytearray | list):
            raise RuntimeError(f"ERROR: Unable to parse operand: {operand}")
        return bytearray(value)

    # literal_eval only parses Python literals, e.g. numbers, strings, bytes, lists and dicts,
    # so unlike eval it can not execute arbitrary code. It processes string escape sequences
    # and requires a single complete literal, so "== 'a' garbage 'b'" is a syntax error.
    try:
        return ast.literal_eval(operand)
    except (ValueError, SyntaxError, MemoryError, RecursionError):
        pass  # Fall through to the formats literal_eval does not support
    if INFINITY_NAN_REGEX.match(operand):
        return float(operand)

    # An f-string is interpolation which would be code execution. literal_eval already rejects
    # it but the generic error does not say why.
    if INTERPOLATION_REGEX.match(operand):
        raise RuntimeError(
            f"ERROR: String interpolation is not supported in an operand: {operand}. Interpolate in the script itself"
        )
    # A bare word is almost always a string the user forgot to quote
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", operand):
        raise NameError(f"Uninitialized constant {operand}. Did you mean '{operand}' as a string?")
    raise RuntimeError(f"ERROR: Unable to parse operand: {operand}")


# Compares a telemetry value against an operand using the given operator.
# Returns False rather than raising if the two values can not be compared.
def compare_values(value, operator, operand):
    try:
        if operator == "==":
            return value == operand
        elif operator == "!=":
            return value != operand
        elif operator == ">":
            return value > operand
        elif operator == ">=":
            return value >= operand
        elif operator == "<":
            return value < operand
        elif operator == "<=":
            return value <= operand
        elif operator == "in":
            # 'in' is containment against a list of values, matching Ruby
            return isinstance(operand, list) and value in operand
        else:
            raise RuntimeError(f"ERROR: Invalid operator: '{operator}'")
    except TypeError:
        # Comparing incompatible types, e.g. None > 1, is simply not a match
        return False
