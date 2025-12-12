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

import os
import sys
import re
import traceback
from typing import Any, Generator, Optional, Union
from openc3.utilities.extract import remove_quotes


class ConfigParser:
    """Reads OpenC3 style configuration data which consists of keywords followed
    by 0 or more comma delimited parameters. Parameters with spaces must be
    enclosed in quotes. Quotes should also be used to indicate a parameter is a
    string. Keywords are case-insensitive and will be returned in uppercase."""

    # Regular expression used to break up an individual line into a keyword and
    # comma delimited parameters. Handles parameters in single or double quotes.
    PARSING_REGEX = r"(?:\"(?:[^\\\"]|\\.)*\") | (?:'(?:[^\\']|\\.)*') | \S+"

    class Error(Exception):
        """Error which gets raised by ConfigParser in #verify_num_parameters. This
        is also the error that classes using ConfigParser should raise when they
        encounter a configuration error."""

        # self.param config_parser [ConfigParser] Instance of ConfigParser so Error
        #   has access to the ConfigParser attributes
        # self.param message [String] The error message which gets passed to the
        #   StandardError constructor
        # self.param usage [String] The usage string representing how this keyword should
        #   be formatted.
        # self.param url [String] URL which should point to usage information. By
        #   default this gets constructed to point to the generic configuration
        #   Guide on the OpenC3 Wiki.
        def __init__(
            self, config_parser: "ConfigParser", message: str = "Configuration Error", usage: str = "", url: str = ""
        ) -> None:
            super().__init__(message)
            self.keyword: Optional[str] = config_parser.keyword
            self.parameters: Optional[list[str]] = config_parser.parameters
            self.filename: Optional[str] = config_parser.filename
            self.line: Optional[str] = config_parser.line
            self.line_number: Optional[int] = config_parser.line_number
            self.usage: str = usage
            self.url: str = url

    # self.param url [String] The url to link to in error messages
    def __init__(self, url: str = "https://docs.openc3.com/docs") -> None:
        self.url: str = url
        self.keyword: Optional[str] = None
        self.parameters: Optional[list[str]] = None
        self.filename: Optional[str] = None
        self.line: Optional[str] = None
        self.line_number: Optional[int] = None

    # self.param message [String] The string to set the Exception message to
    # self.param usage [String] The usage message
    # self.param url [String] Where to get help about this error
    # self.return [Error] The constructed error
    def error(self, message: str, usage: str = "", url: Optional[str] = None) -> "ConfigParser.Error":
        if not url:
            url = self.url
        return self.Error(self, message, usage, url)

    # Can be called during parsing to read a referenced file
    def read_file(self, filename: str) -> bytes:
        # Assume the file is there. If not we raise a pretty obvious error
        if os.path.abspath(filename) == filename:  # absolute path
            path = filename
        else:  # relative to the current @filename
            if not self.filename:
                raise ValueError(f"Cannot resolve relative path '{filename}' - no current file context")
            path = os.path.join(os.path.dirname(self.filename), filename)
        data: bytes = b""
        with open(path, "rb") as file:
            data = file.read()
        return data

    def parse_file(
        self,
        filename: str,
        yield_non_keyword_lines: bool = False,
        remove_quotes_arg: bool = True,
        run_erb: bool = True,
        variables: dict[str, Any] = {},
    ) -> Generator[tuple[Optional[str], list[str]], None, None]:
        """Parse a file and call the callback for each line

        Args:
            filename (str): The file to parse
            yield_non_keyword_lines (bool, optional): Whether to yield lines without keywords
            remove_quotes_arg (bool, optional): Whether to remove quotes from parameters
            run_erb (bool, optional): No effect in Python
            variables (dict, optional): No effect in Python

        Returns:
            Generator yielding (keyword, parameters) tuples
        """
        if filename and not os.path.exists(filename):
            raise ConfigParser.Error(self, f"Configuration file {filename} does not exist.")

        self.filename = filename
        with open(filename, "r") as file:
            # Loop through each line of the data
            yield from self.parse_loop(
                file,
                yield_non_keyword_lines,
                remove_quotes_arg,
                os.path.getsize(file.name),
                ConfigParser.PARSING_REGEX,
            )

    def verify_num_parameters(self, min_num_params: int, max_num_params: Optional[int], usage: str = "") -> None:
        """
        Verifies the parameters in the ConfigParser have the specified number of arguments

        Args:
            min_num_params (int): The minimum number of parameters
            max_num_params (int): The maximum number of parameters (None for unlimited)
            usage (str): Usage description to display in error message

        Raises:
            Error: Insufficient/Excessive parameters for keyword
        """
        if not self.parameters:
            if min_num_params > 0:
                raise ConfigParser.Error(self, f"Not enough parameters for {self.keyword}.", usage, self.url)
            return

        # This syntax works with 0 because each doesn't return any values
        # for a backwards range
        for index in range(1, min_num_params + 1):
            # If the parameter is None (0 based) then we have a problem
            if not self.parameters[index - 1 : index]:
                raise ConfigParser.Error(self, f"Not enough parameters for {self.keyword}.", usage, self.url)

        # If they pass None for max_params we don't check for a maximum number
        if max_num_params is not None and self.parameters[max_num_params : max_num_params + 1]:
            raise ConfigParser.Error(self, f"Too many parameters for {self.keyword}.", usage, self.url)

    def verify_parameter_naming(self, index: int, usage: str = "") -> None:
        """
        Verifies that the parameter does not contain reserved characters

        Args:
            index (int): The index of the parameter to be verified (1-based)
            usage (str): Usage description to display in error message
        """
        if not self.parameters or index < 1 or index > len(self.parameters):
            raise ConfigParser.Error(self, f"Parameter {index} does not exist for {self.keyword}.", usage, self.url)
        param = self.parameters[index - 1]
        if param[-1] == "_":
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot end with an underscore ('_').",
                usage,
                self.url,
            )

        if "__" in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain a double underscore ('__').",
                usage,
                self.url,
            )

        if "[[" in param or "]]" in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain double brackets ('[[' or ']]').",
                usage,
                self.url,
            )

        if " " in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain a space (' ').",
                usage,
                self.url,
            )

        if "'" in param or '"' in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain a quote (' or \").",
                usage,
                self.url,
            )

        if "{" in param or "}" in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain a curly bracket ('{{' or '}}').",
                usage,
                self.url,
            )

    # Converts a String containing '', 'NONE', or 'NULL' to Python primitive.
    # All other arguments are simply returned.
    #
    # self.param value [Object]
    # self.return [None|Object]
    @classmethod
    def handle_none(cls, value: Any) -> Optional[Any]:
        if isinstance(value, str):
            match value.upper():
                case "" | "NIL" | "NONE" | "NULL":
                    return None

        return value

    # Converts a String containing 'TRUE' or 'FALSE' to True or False Python
    # primitive. All other values are simply returned.
    #
    # self.param value [Object]
    # self.return [True|False|Object]
    @classmethod
    def handle_true_false(cls, value: Any) -> Union[bool, Any]:
        if isinstance(value, str):
            match value.upper():
                case "TRUE":
                    return True
                case "FALSE":
                    return False
        return value

    # Converts a String containing '', 'NONE', 'NULL', 'NIL', 'TRUE' or 'FALSE' to None,
    # True or False Python primitives. All other values are simply returned.
    #
    # self.param value [Object]
    # self.return [True|False|None|Object]
    @classmethod
    def handle_true_false_none(cls, value: Any) -> Optional[Union[bool, Any]]:
        if isinstance(value, str):
            match value.upper():
                case "TRUE":
                    return True
                case "FALSE":
                    return False
                # Convert nil for the Rubyists
                case "" | "NONE" | "NULL" | "NIL":
                    return None
        return value

    # Converts a string representing a defined constant into its value. The
    # defined constants are the minimum and maximum values for all the
    # allowable data types. [MIN/MAX]_[U]INT[8/16/32] and
    # [MIN/MAX]_FLOAT[32/64]. Thus MIN_UINT8, MAX_INT32, and MIN_FLOAT64 are
    # all allowable values. Any other strings raise ArgumentError but all other
    # types are simply returned.
    #
    # self.param value [Object] Can be anything
    # self.return [Numeric] The converted value. Either a Fixnum or Float.
    @classmethod
    def handle_defined_constants(
        cls, value: Any, data_type: Optional[str] = None, bit_size: Optional[int] = None
    ) -> Union[int, float, Any]:
        if isinstance(value, str):
            match value.upper():
                case "MIN" | "MAX":
                    return ConfigParser.calculate_range_value(value.upper(), data_type, bit_size)
                case "MIN_INT8":
                    return -128
                case "MAX_INT8":
                    return 127
                case "MIN_INT16":
                    return -32768
                case "MAX_INT16":
                    return 32767
                case "MIN_INT32":
                    return -2147483648
                case "MAX_INT32":
                    return 2147483647
                case "MIN_INT64":
                    return -9223372036854775808
                case "MAX_INT64":
                    return 9223372036854775807
                case "MIN_UINT8" | "MIN_UINT16" | "MIN_UINT32" | "MIN_UINT64":
                    return 0
                case "MAX_UINT8":
                    return 255
                case "MAX_UINT16":
                    return 65535
                case "MAX_UINT32":
                    return 4294967295
                case "MAX_UINT64":
                    return 18446744073709551615
                case "MIN_FLOAT64":
                    return -sys.float_info.max
                case "MAX_FLOAT64":
                    return sys.float_info.max
                case "MIN_FLOAT32":
                    return -3.402823e38
                case "MAX_FLOAT32":
                    return 3.402823e38
                case "POS_INFINITY":
                    return float("inf")
                case "NEG_INFINITY":
                    return float("-inf")
                # NOTE: No else case because of the following scenario:
                # If the value type is a UINT but they have a WRITE_CONVERSION that takes a string
                # then the default value will be a string. In that case we just want to return the string.
                # For example, the IP_ADDRESS parameter in the TIME_OFFSET command in the Demo plugin.

        return value

    @classmethod
    def calculate_range_value(cls, type: str, data_type: Optional[str], bit_size: Optional[int]) -> Union[int, float]:
        """
        Calculate the min or max value for a given data type and bit size

        Args:
            type: MIN or MAX
            data_type: Data type (INT, UINT, etc.)
            bit_size: Size in bits

        Returns:
            Min or max value
        """
        value = 0  # Default for UINT minimum

        match data_type:
            case "INT":
                if (bs := bit_size) is None:
                    raise ValueError("bit_size is required for INT type")
                value = -(2 ** (bs - 1)) if type == "MIN" else 2 ** (bs - 1) - 1

            case "UINT":
                # Default is 0 for 'MIN'
                if type == "MAX":
                    if (bs := bit_size) is None:
                        raise ValueError("bit_size is required for UINT type")
                    value = 2**bs - 1

            case "FLOAT":
                if (bs := bit_size) is None:
                    raise ValueError("bit_size is required for FLOAT type")

                match bs:
                    case 32:
                        value = 3.402823e38 if type == "MAX" else -3.402823e38
                    case 64:
                        value = sys.float_info.max if type == "MAX" else -sys.float_info.max
                    case _:
                        raise ValueError(f"Invalid bit size {bs} for FLOAT type.")

            case _:
                raise TypeError(f"Invalid data type {data_type} when calculating range.")

        return value

    def parse_errors(self, errors: list[Exception]) -> None:
        if len(errors) == 0:
            return
        message = ""
        for error in errors:
            if isinstance(error, ConfigParser.Error):
                filename = os.path.basename(error.filename) if error.filename else "unknown"
                line_num = error.line_number if error.line_number else 0
                line_text = error.line if error.line else ""
                message += f"\n{filename}:{line_num}: {line_text}"
                message += f"\nError: {traceback.format_exc()}"
                if error.usage:
                    message += f"\nUsage: {error.usage}"
            else:
                message += f"\n{traceback.format_exc()}"
        message += "\n"
        raise ConfigParser.Error(self, message)

    # Iterates over each line of the io object and yields the keyword and parameters
    def parse_loop(
        self, io: Any, yield_non_keyword_lines: bool, remove_quotes_arg: bool, size: int, rx: str
    ) -> Generator[tuple[Optional[str], list[str]], None, None]:
        string_concat = False
        self.line_number = 0
        self.keyword = None
        self.parameters = []
        self.line = ""
        errors = []

        # Type checker hint: line_buffer is guaranteed to be str within this method
        line_buffer: str = self.line

        while line := io.readline():
            self.line_number += 1

            line = line.strip()
            # Ensure the line length is not 0
            if len(line) == 0:
                continue

            if string_concat:
                # Skip comment lines after a string concatenation
                if line[0] == "#":
                    continue
                # Remove the opening quote if we're continuing the line
                line = line[1:]

            # Check for string continuation
            match line[-1]:
                case "+" | "\\":  # String concatenation
                    newline = line[-1] == "+"
                    # Trim off the concat character plus any spaces, e.g. "line" \
                    trim = line[0:-1].strip()
                    # Now trim off the last quote so it will flow into the next line
                    line_buffer += trim[0:-1]
                    if newline:
                        line_buffer += "\n"
                    string_concat = True
                    continue
                case "&":  # Line continuation
                    line_buffer += line[0:-1]
                    continue
                case _:
                    line_buffer += line
            string_concat = False

            # Update self.line for external access
            self.line = line_buffer

            data = re.compile(rx, re.X).findall(line_buffer)
            first_item = ""
            if len(data) > 0:
                first_item += data[0]

            if (len(first_item) == 0) or (first_item[0] == "#"):
                self.keyword = None
            else:
                self.keyword = first_item.upper()
            self.parameters = []

            # Ignore lines without keywords: comments and blank lines
            if not self.keyword:
                if yield_non_keyword_lines:
                    try:
                        yield self.keyword, self.parameters
                    except Exception as error:
                        errors.append(error)
                self.line = ""
                line_buffer = ""
                continue

            length = len(data)
            if length > 1:
                for index in range(1, length):
                    string = data[index]

                    # Don't process trailing comments such as:
                    # KEYWORD PARAM #This is a comment
                    # But still process Ruby string interpolations such as:
                    # KEYWORD PARAM {var}
                    if (len(string) > 0) and (string[0] == "#"):
                        if not ((len(string) > 1) and (string[1] == "{")):
                            break

                    if remove_quotes_arg:
                        self.parameters.append(remove_quotes(string))
                    else:
                        self.parameters.append(string)

            try:
                yield self.keyword, self.parameters
            except Exception as error:
                errors.append(error)
            self.line = ""
            line_buffer = ""

        self.parse_errors(errors)
        return None
