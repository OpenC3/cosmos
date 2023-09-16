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

from datetime import datetime
import importlib
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.utilities.string import *
from openc3.utilities.logger import Logger


class QuoteIfNecessary(unittest.TestCase):
    def test_quotes_strings_with_spaces(self):
        self.assertEqual(quote_if_necessary("HelloWorld"), "HelloWorld")
        self.assertEqual(quote_if_necessary("Hello World"), '"Hello World"')


class SimpleFormatted(unittest.TestCase):
    def setUp(self):
        self.data = []
        for x in range(26, 48):
            self.data.append(x)
        self.data = bytes(self.data)

    def test_formats_the_data(self):
        self.assertEqual(
            simple_formatted(self.data), "1A1B1C1D1E1F202122232425262728292A2B2C2D2E2F"
        )


class TestFormatted(unittest.TestCase):
    def setUp(self):
        self.data = []
        for x in range(26, 48):
            self.data.append(x)
        self.data = bytes(self.data)

    def test_uses_1_byte_words(self):
        self.assertEqual(
            formatted(self.data).split("\n")[0],
            "00000000: 1A 1B 1C 1D 1E 1F 20 21 22 23 24 25 26 27 28 29         !\"#$%&'()",
        )
        self.assertEqual(
            formatted(self.data).split("\n")[1],
            "00000010: 2A 2B 2C 2D 2E 2F                                *+,-./          ",
        )

    def test_uses_2_byte_words(self):
        self.assertIn("00000000: 1A1B 1C1D 1E1F", formatted(self.data, 2, 8))  # ...
        self.assertIn("00000010: 2A2B 2C2D 2E2F", formatted(self.data, 2, 8))

    def test_changes_the_word_separator(self):
        self.assertIn("00000000: 1A1B_1C1D_1E1F_2021", formatted(self.data, 2, 4, "_"))
        self.assertIn("00000008: 2223_2425_2627_2829", formatted(self.data, 2, 4, "_"))
        self.assertIn("00000010: 2A2B_2C2D_2E2F", formatted(self.data, 2, 4, "_"))

    def test_indents_the_lines(self):
        self.assertIn("    00000000: 1A 1B 1C 1D", formatted(self.data, 1, 16, " ", 4))

    def test_does_not_show_the_address(self):
        self.assertIn("1A 1B 1C 1D", formatted(self.data, 1, 16, " ", 0, False))

    def test_changes_the_address_separator(self):
        self.assertIn(
            "00000000= 1A 1B 1C 1D", formatted(self.data, 1, 16, " ", 0, True, "= ")
        )

    def test_does_not_show_the_ascii(self):
        self.assertIn(
            "29         !\"#$%&'()", formatted(self.data, 1, 16, "", 0, True, "", True)
        )
        self.assertNotIn(
            "29         !\"#$%&'()",
            formatted(self.data, 1, 16, "", 0, True, "", False),
        )

    def test_changes_the_ascii_separator(self):
        self.assertIn(
            "29__       !\"#$%&'()",
            formatted(self.data, 1, 16, "", 0, True, "", True, "__"),
        )

    def test_changes_the_ascii_unprintable_character(self):
        self.assertIn(
            "29__xxxxxx !\"#$%&'()",
            formatted(self.data, 1, 16, "", 0, True, "", True, "__", "x"),
        )

    def test_changes_the_line_separator(self):
        self.assertEqual(
            formatted(self.data, 1, 16, " ", 0, True, ": ", True, "  ", " ", "~").split(
                "~"
            )[0],
            "00000000: 1A 1B 1C 1D 1E 1F 20 21 22 23 24 25 26 27 28 29         !\"#$%&'()",
        )
        self.assertEqual(
            formatted(self.data, 1, 16, " ", 0, True, ": ", True, "  ", " ", "~").split(
                "~"
            )[1],
            "00000010: 2A 2B 2C 2D 2E 2F                                *+,-./          ",
        )


class TestBuildTimestampedFilename(unittest.TestCase):
    def test_formats_the_time(self):
        time = datetime.now()
        timestamp = time.strftime("%Y_%m_%d_%H_%M_%S")
        self.assertIn(timestamp, build_timestamped_filename(None, ".txt", time))

    def test_allows_empty_tags(self):
        self.assertRegex(build_timestamped_filename([]), r"\d\d\.txt")

    def test_allows_none_tags(self):
        self.assertRegex(build_timestamped_filename(None), r"\d\d\.txt")

    def test_allows_some_none_tags(self):
        self.assertRegex(build_timestamped_filename([None, 1]), r"_1\.txt")

    def test_includes_the_tags(self):
        self.assertRegex(
            build_timestamped_filename(["this", "is", "a", "test"]), r"this_is_a_test"
        )

    def test_changes_the_extension(self):
        self.assertRegex(build_timestamped_filename(None, ".bin"), r"\.bin")


class ClassNameToFilename(unittest.TestCase):
    def test_converts_a_class_name_to_a_filename(self):
        self.assertEqual(class_name_to_filename("MyGreatClass"), "my_great_class")
        self.assertEqual(
            class_name_to_filename("MyGreatClass", True), "my_great_class.py"
        )


class FilenameToClassName(unittest.TestCase):
    def test_converts_a_filename_to_a_class_name(self):
        self.assertEqual(
            filename_to_class_name("path/to/something/my_great_class.rb"),
            "MyGreatClass",
        )


class ToClass(unittest.TestCase):
    def test_returns_the_class_for_the_string(self):
        importlib.import_module(".logger", "openc3.utilities")
        self.assertEqual(
            to_class("openc3.utilities.logger", "Logger").__class__.__name__,
            Logger.__class__.__name__,
        )
