#!/usr/bin/env python3

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

import os
import sys
import re
import tempfile
from openc3.utilities.extract import remove_quotes


class ConfigParser:
    """Reads OpenC3 style configuration data which consists of keywords followed
    by 0 or more comma delimited parameters. Parameters with spaces must be
    enclosed in quotes. Quotes should also be used to indicate a parameter is a
    string. Keywords are case-insensitive and will be returned in uppercase."""

    #     # self.return [String] The current keyword being parsed
    #     attr_accessor :keyword

    #     # self.return [Array<String>] The parameters found after the keyword
    #     attr_accessor :parameters

    #     # self.return [String] The name of the configuration file being parsed. This
    #     #   will be an empty string if the parse_string class method is used.
    #     attr_accessor :filename

    #     # self.return [String] The current line being parsed. This is the raw string
    #     #   which is useful when printing errors.
    #     attr_accessor :line

    #     # self.return [Integer] The current line number being parsed.
    #     #   This will still be populated when using parse_string because lines
    #     #   still must be delimited by newline characters.
    #     attr_accessor :line_number

    #     # self.return [String] The default URL to use in errors. The URL can still be
    #     #   overridden by directly passing it to the error method.
    #     attr_accessor :url

    # Regular expression used to break up an individual line into a keyword and
    # comma delimited parameters. Handles parameters in single or double quotes.
    PARSING_REGEX = "(?:\"(?:[^\\\"]|\\.)*\") | (?:'(?:[^\\']|\\.)*') | \S+"

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
            self, config_parser, message="Configuration Error", usage="", url=""
        ):
            super().__init__(message)
            self.keyword = config_parser.keyword
            self.parameters = config_parser.parameters
            self.filename = config_parser.filename
            self.line = config_parser.line
            self.line_number = config_parser.line_number
            self.usage = usage
            self.url = url

    # self.param url [String] The url to link to in error messages
    def __init__(self, url="https:/openc3.com/docs/v5"):
        self.url = url

    # self.param message [String] The string to set the Exception message to
    # self.param usage [String] The usage message
    # self.param url [String] Where to get help about this error
    # self.return [Error] The constructed error
    def error(self, message, usage="", url=None):
        if not url:
            url = self.url
        return self.Error(self, message, usage, url)

    # TODO: Mako? https://www.makotemplates.org/
    # # Called by the ERB template to render a partial
    # def render(template_name, options = {})
    #   raise ConfigParser.Error(self, "Partial name '{template_name}' must begin with an underscore.") if File.basename(template_name)[0] != '_'

    #   b = binding
    #   if options[:locals]
    #     options[:locals].each { |key, value| b.local_variable_set(key, value) }
    #

    #   return ERB.new(read_file(template_name), trim_mode: "-").result(b)

    #     # Can be called during parsing to read a referenced file
    #     def read_file(filename)
    #       # Assume the file is there. If not we raise a pretty obvious error
    #       if File.expand_path(filename) == filename # absolute path
    #         path = filename
    #       else # relative to the current self.filename
    #         path = File.join(File.dirname(self.filename), filename)
    #
    #       OpenC3.set_working_dir(File.dirname(path)) do
    #         return File.read(path)
    #
    #

    # Processes a file and yields |config| to the given block
    #
    # self.param filename [String] The full name and path of the configuration file
    # self.param yield_non_keyword_lines [Boolean] Whether to yield all lines including blank
    #   lines or comment lines.
    # self.param remove_quotes [Boolean] Whether to remove beginning and ending single
    #   or double quote characters from parameters.
    # self.param run_erb [Boolean] Whether or not to run ERB on the file
    # self.param variables [Hash] variables to pash to ERB context
    # self.param block [Block] The block to yield to
    # self.yieldparam keyword [String] The keyword in the current parsed line
    # self.yieldparam parameters [Array<String>] The parameters in the current parsed line
    def parse_file(
        self,
        filename,
        yield_non_keyword_lines=False,
        remove_quotes_arg=True,
        run_erb=True,
        variables={},
    ):
        if filename and not os.path.exists(filename):
            raise ConfigParser.Error(
                self, f"Configuration file {filename} does not exist."
            )

        self.filename = filename

        # Create a temp file where we write the ERB parsed output
        file = self._create_parsed_output_file(filename, run_erb, variables)

        try:
            # Loop through each line of the data
            yield from self.parse_loop(
                file,
                yield_non_keyword_lines,
                remove_quotes_arg,
                os.path.getsize(file.name),
                ConfigParser.PARSING_REGEX,
            )
        finally:
            if not file.closed:
                file.close()

    # Verifies the parameters in the config parameter have the specified
    # number of parameter and raises an Error if not.
    #
    # self.param [Integer] min_num_params The minimum number of parameters
    # self.param [Integer] max_num_params The maximum number of parameters. Pass
    #   None to indicate there is no maximum number of parameters.
    def verify_num_parameters(self, min_num_params, max_num_params, usage=""):
        # This syntax works with 0 because each doesn't return any values
        # for a backwards range
        for index in range(1, min_num_params + 1):
            # If the parameter is None (0 based) then we have a problem
            if not self.parameters[index - 1 : index]:
                raise ConfigParser.Error(
                    self, f"Not enough parameters for {self.keyword}.", usage, self.url
                )

        # If they pass None for max_params we don't check for a maximum number
        if max_num_params and self.parameters[max_num_params : max_num_params + 1]:
            raise ConfigParser.Error(
                self, f"Too many parameters for {self.keyword}.", usage, self.url
            )

    # Verifies the indicated parameter in the config doesn't start or
    # with an underscore, doesn't contain a double underscore, doesn't contain
    # spaces and doesn't start with a close bracket.
    #
    # self.param [Integer] index The index of the parameter to check
    def verify_parameter_naming(self, index, usage=""):
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

        if " " in param:
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot contain a space (' ').",
                usage,
                self.url,
            )

        if param[0] == "}":
            raise ConfigParser.Error(
                self,
                f"Parameter {index} ({param}) for {self.keyword} cannot start with a close bracket ('}}').",
                usage,
                self.url,
            )

    # Converts a String containing '', 'NONE', or 'NULL' to Python primitive.
    # All other arguments are simply returned.
    #
    # self.param value [Object]
    # self.return [None|Object]
    @classmethod
    def handle_none(cls, value):
        if type(value) == str:
            match value.upper():
                case "" | "NONE" | "NULL":
                    return None

        return value

    # Converts a String containing 'TRUE' or 'FALSE' to True or False Python
    # primitive. All other values are simply returned.
    #
    # self.param value [Object]
    # self.return [True|False|Object]
    @classmethod
    def handle_true_false(cls, value):
        if type(value) == str:
            match value.upper():
                case "TRUE":
                    return True
                case "FALSE":
                    return False
        return value

    # Converts a String containing '', 'NONE', 'NULL', 'TRUE' or 'FALSE' to None,
    # True or False Python primitives. All other values are simply returned.
    #
    # self.param value [Object]
    # self.return [True|False|None|Object]
    @classmethod
    def handle_true_false_none(cls, value):
        if type(value) == str:
            match value.upper():
                case "TRUE":
                    return True
                case "FALSE":
                    return False
                case "" | "NONE" | "NULL":
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
    def handle_defined_constants(cls, value, data_type=None, bit_size=None):
        if type(value) == str:
            match value.upper():
                case "MIN" | "MAX":
                    return ConfigParser.calculate_range_value(
                        value.upper(), data_type, bit_size
                    )
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
                case _:
                    raise AttributeError(f"Could not convert constant: {value}")

        return value

    # Writes the ERB parsed results
    def _create_parsed_output_file(self, filename, run_erb, variables):
        try:
            output = None
            if run_erb:
                # TODO: Mako? https://www.makotemplates.org/
                #   OpenC3.set_working_dir(File.dirname(filename)) do
                #     output = ERB.new(File.read(filename), trim_mode: "-").result(binding.set_variables(variables))
                with open(filename, "r") as f:
                    output = f.read()
            else:
                with open(filename, "r") as f:
                    output = f.read()

        except Exception as e:
            raise e
        # The first line of the backtrace indicates the line where the ERB
        # parse failed. Grab the line number for the error message.
        # match = r':(.*):'.match(e.backtrace[0])
        # line_number = match.captures[0] if match
        # raise e, "ERB error at {filename}:{line_number}\n{e}", e.backtrace

        # Make a copy of the filename since we're calling slice! which modifies it directly
        copy = filename[0:-1]
        config_index = copy.find("config")
        if config_index != -1:
            copy = copy[config_index:-1]
        elif ":" in copy:  # Check for Windows drive letter
            copy = copy.split(":")[1]

        # tmpdir = tempfile.TemporaryDirectory()
        # parsed_filename = os.path.join(tmpdir.name, "openc3", "tmp", copy)
        # os.makedirs(os.path.dirname(parsed_filename), exist_ok=True)  # Create the path
        # file = open(parsed_filename, "w+")
        file = tempfile.NamedTemporaryFile(mode="w+t")
        file.writelines(output)
        file.seek(0)  # Rewind so the file is ready to read
        return file

    @classmethod
    def calculate_range_value(cls, type, data_type, bit_size):
        value = 0  # Default for UINT minimum

        match data_type:
            case "INT":
                if type == "MIN":
                    value = -(2 ** (bit_size - 1))
                else:  # 'MAX'
                    value = 2 ** (bit_size - 1) - 1

            case "UINT":
                # Default is 0 for 'MIN'
                if type == "MAX":
                    value = 2**bit_size - 1

            case "FLOAT":
                match bit_size:
                    case 32:
                        value = 3.402823e38
                        if type == "MIN":
                            value *= -1
                    case 64:
                        value = sys.float_info.max
                        if type == "MIN":
                            value *= -1
                    case _:
                        raise AttributeError(
                            f"Invalid bit size {bit_size} for FLOAT type."
                        )

            case _:
                raise AttributeError(
                    f"Invalid data type {data_type} when calculating range."
                )

        return value

    def parse_errors(self, errors):
        if len(errors) == 0:
            return
        message = ""
        for error in errors:
            if issubclass(error, ConfigParser.Error):
                message += f"\n{os.path.basename(error.filename)}:{error.line_number}: {error.line}"
                message += f"\nError: {repr(error)}"
                if not error.usage:
                    message += f"\nUsage: {error.usage}"
            else:
                message += f"\n{repr(error)}"
        message += "\n"
        raise message

    # Iterates over each line of the io object and yields the keyword and parameters
    def parse_loop(self, io, yield_non_keyword_lines, remove_quotes_arg, size, rx):
        string_concat = False
        self.line_number = 0
        self.keyword = None
        self.parameters = []
        self.line = ""
        errors = []

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
                    self.line += trim[0:-1]
                    if newline:
                        self.line += "\n"
                    string_concat = True
                    continue
                case "&":  # Line continuation
                    self.line += line[0:-1]
                    continue
                case _:
                    self.line += line
            string_concat = False

            data = re.compile(rx, re.X).findall(self.line)
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

        self.parse_errors(errors)
        return None