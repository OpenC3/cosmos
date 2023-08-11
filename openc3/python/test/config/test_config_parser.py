#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
import tempfile
from unittest.mock import *
from test.test_helper import *
from openc3.config.config_parser import ConfigParser


class TestConfigParser(unittest.TestCase):
    def setUp(self):
        self.cp = ConfigParser()

    def test_parse_file_yields_keyword_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertEqual(params, ["PARAM1", "PARAM2", "PARAM 3"])
            self.assertEqual(self.cp.line, line)
            self.assertEqual(self.cp.line_number, 1)
        tf.close()

    def test_parse_file_handles_python_string_interpolation(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD1 {var} PARAM1\n")
        tf.writelines("KEYWORD2 PARAM1 #Comment\n")
        tf.seek(0)

        results = {}
        for keyword, params in self.cp.parse_file(tf.name):
            results[keyword] = params
        self.assertListEqual(list(results.keys()), ["KEYWORD1", "KEYWORD2"])
        self.assertEqual(results["KEYWORD1"], ["{var}", "PARAM1"])
        self.assertEqual(results["KEYWORD2"], ["PARAM1"])
        tf.close()

    # TODO:
    #   def test_supports ERB syntax(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w+t")
    #     tf.writelines("KEYWORD <%= 5 * 2 %>"
    #     tf.seek(0)

    #     for keyword, params in self.cp.parse_file(tf.name):
    #       self.assertEqual(keyword, "KEYWORD"
    #       self.assertEqual(params[0], "10"

    #     tf.close()

    #   def test_requires ERB partials begin with an underscore(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w+t")
    #     tf.writelines("<%= render 'partial.txt' %>"
    #     tf.seek(0)

    #     self.assertEqual { self.cp.parse_file(tf.name) }.to raise_error(ConfigParser::Error, /must begin with an underscore/)
    #     tf.close()

    #   def test_allows ERB partials in subdirectories(self):
    #     Dir.mktmpdir("partial_dir") do |dir|
    #       tf2 = Tempfile.new('_partial.txt', dir)
    #       tf2.puts "SUBDIR"
    #       tf2.close
    #       tf = tempfile.NamedTemporaryFile(mode="w+t")
    #       # Grab the sub directory name plus filename
    #       subdir_path = tf2.path().split('/')[-2..-1].join('/')
    #       tf.writelines("<%= render '{subdir_path}' %>"
    #       tf.seek(0)

    #       for keyword, params in self.cp.parse_file(tf.name):
    #         self.assertEqual(keyword, "SUBDIR"

    #       tf.close()
    #       tf2.unlink

    #   def test_allows absolute paths to ERB partials(self):
    #     Dir.mktmpdir("partial_dir") do |dir|
    #       tf2 = Tempfile.new('_partial.txt', dir)
    #       tf2.puts "ABSOLUTE"
    #       tf2.close
    #       tf = tempfile.NamedTemporaryFile(mode="w+t")
    #       tf.writelines("<%= render '{tf2.path}' %>"
    #       tf.seek(0)

    #       for keyword, params in self.cp.parse_file(tf.name):
    #         self.assertEqual(keyword, "ABSOLUTE"

    #       tf.close()
    #       tf2.unlink

    #   def test_supports ERB partials via render(self):
    #     tf2 = Tempfile.new('_partial.txt')
    #     tf2.puts '<% if output %>'
    #     tf2.puts 'RENDER <%= id %> <%= desc %>'
    #     tf2.puts '<%  %>'
    #     tf2.close

    #     # Run the test twice to verify the KEYWORD gets rendered and then doesn't
    #     [True, False].each do |output|
    #       tf = tempfile.NamedTemporaryFile(mode="w+t")
    #       tf.writelines("<%= render '{File.basename(tf2.path)}', locals: {id: 1, desc: 'Description', output: {output}} %>"
    #       tf.seek(0)

    #       yielded = False
    #       for keyword, params in self.cp.parse_file(tf.name):
    #         yielded = True
    #         self.assertEqual(keyword, "RENDER"
    #         self.assertEqual(params[0], "1"
    #         self.assertEqual(params[1], "Description"

    #       self.assertEqual(yielded, output
    #       tf.close()

    #     tf2.unlink

    def test_optionally_does_not_remove_quotes(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name, False, False):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "PARAM2", "'PARAM 3'"])
            self.assertEqual(self.cp.line, line)
            self.assertEqual(self.cp.line_number, 1)
        tf.close()

    def test_handles_inline_line_continuations(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 & PARAM2")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "&", "PARAM2"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 & PARAM2")
            self.assertEqual(self.cp.line_number, 1)
        tf.close()

    def test_handles_line_continuations_as_eol(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 &\n")
        tf.writelines("  PARAM2 'PARAM 3'")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "PARAM2", "PARAM 3"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 PARAM2 'PARAM 3'")
            self.assertEqual(self.cp.line_number, 2)

        for keyword, params in self.cp.parse_file(tf.name, False, False):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "PARAM2", "'PARAM 3'"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 PARAM2 'PARAM 3'")
            self.assertEqual(self.cp.line_number, 2)
        tf.close()

    def test_handles_line_continuations_without_another_line(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 &")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1")
            self.assertEqual(self.cp.line_number, 1)
        tf.close()

    def handles_line_continuations_with_a_comment_line(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 &")
        tf.writelines("# Comment")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 # Comment")
            self.assertEqual(self.cp.line_number, 2)
        tf.close()

    def test_handles_string_concatenations(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 'continues ' \\\n")
        tf.writelines("'next line'")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "continues next line"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues next line'")
            self.assertEqual(self.cp.line_number, 2)

        for keyword, params in self.cp.parse_file(tf.name, False, False):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "'continues next line'"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues next line'")
            self.assertEqual(self.cp.line_number, 2)
        tf.close()

    def test_handles_bad_string_concatenations(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 'continues ' \\\n")
        tf.writelines("\n")  # blank line
        tf.writelines("KEYWORD2 PARAM2")  # forces this into the first line
        tf.seek(0)
        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "'continues", "EYWORD2", "PARAM2"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues EYWORD2 PARAM2")
            self.assertEqual(self.cp.line_number, 3)
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 'continues ' \\\n")
        tf.writelines("next line\n")  # Forgot quotes
        tf.writelines("KEYWORD2 PARAM2")  # Ensure we proces the next line
        tf.seek(0)
        for keyword, params in self.cp.parse_file(tf.name):
            if keyword == "KEYWORD":
                self.assertEqual(keyword, "KEYWORD")
                self.assertListEqual(params, ["PARAM1", "'continues", "ext", "line"])
                # Works but creates weird open quote with no close quote
                self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues ext line")
                self.assertEqual(self.cp.line_number, 2)
            else:
                self.assertEqual(keyword, "KEYWORD2")
                self.assertListEqual(params, ["PARAM2"])
                self.assertEqual(self.cp.line, "KEYWORD2 PARAM2")
                self.assertEqual(self.cp.line_number, 3)
        tf.close()

    def test_handles_string_concatenations_with_newlines(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD PARAM1 'continues ' +\n")
        tf.writelines("# Comment line which is ignored\n")
        tf.writelines("'next line'")
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "continues \nnext line"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues \nnext line'")
            self.assertEqual(self.cp.line_number, 3)

        for keyword, params in self.cp.parse_file(tf.name, False, False):
            self.assertEqual(keyword, "KEYWORD")
            self.assertListEqual(params, ["PARAM1", "'continues \nnext line'"])
            self.assertEqual(self.cp.line, "KEYWORD PARAM1 'continues \nnext line'")
            self.assertEqual(self.cp.line_number, 3)
        tf.close()

    def test_optionally_yields_comment_lines(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD1 PARAM1\n")
        tf.writelines("# This is a comment\n")
        tf.writelines("KEYWORD2 PARAM1\n")
        tf.seek(0)

        lines = []
        for keyword, params in self.cp.parse_file(tf.name, True):
            lines.append(self.cp.line)

        self.assertIn("# This is a comment", lines)
        tf.close()

    #   def test_callbacks for messages(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w+t")
    #     line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
    #     tf.writelines(line
    #     tf.seek(0)

    #     msg_callback = double(:call => True)
    #     self.assertEqual(msg_callback).to receive(:call).once.with(/Parsing .* bytes of .*{File.basename(tf.name)}/)

    #     ConfigParser.message_callback = msg_callback
    #     for keyword, params in self.cp.parse_file(tf.name):
    #       self.assertEqual(keyword, "KEYWORD"
    #       self.assertListEqual(params, ['PARAM1', 'PARAM2', 'PARAM 3')
    #       self.assertEqual(self.cp.line, line
    #       self.assertEqual(self.cp.line_number, 1
    #     tf.close()

    #   def test_callbacks for percent done(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w+t")
    #     # Callback is made at beginning, every 10 lines, and at the
    #     15.times { tf.writelines("KEYWORD PARAM" }
    #     tf.seek(0)

    #     msg_callback = double(:call => True)
    #     done_callback = double(:call => True)
    #     self.assertEqual(done_callback).to receive(:call).with(0.0)
    #     self.assertEqual(done_callback).to receive(:call).with(0.6)
    #     self.assertEqual(done_callback).to receive(:call).with(1.0)

    #     ConfigParser.message_callback = msg_callback
    #     ConfigParser.progress_callback = done_callback
    #     self.cp.parse_file(tf.name) { |k, p| }
    #     tf.close()

    def test_verifies_the_minimum_number_of_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertRaisesRegex(
                ConfigParser.Error,
                f"Not enough parameters for {keyword}",
                self.cp.verify_num_parameters,
                1,
                1,
            )
        tf.close()

    def test_verifies_the_maximum_number_of_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD PARAM1 PARAM2"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertEqual(keyword, "KEYWORD")
            self.assertRaisesRegex(
                ConfigParser.Error,
                "Too many parameters for KEYWORD",
                self.cp.verify_num_parameters,
                1,
                1,
            )
        tf.close()

    def test_verifies_parameters_do_not_have_bad_characters(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD BAD1_ BAD__2 'BAD 3' }BAD_4"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            self.assertRaisesRegex(
                ConfigParser.Error,
                "cannot end with an underscore",
                self.cp.verify_parameter_naming,
                1,
            )
            self.assertRaisesRegex(
                ConfigParser.Error,
                "cannot contain a double underscore",
                self.cp.verify_parameter_naming,
                2,
            )
            self.assertRaisesRegex(
                ConfigParser.Error,
                "cannot contain a space",
                self.cp.verify_parameter_naming,
                3,
            )
            self.assertRaisesRegex(
                ConfigParser.Error,
                "cannot start with a close bracket",
                self.cp.verify_parameter_naming,
                4,
            )
        tf.close()

    def test_returns_an_error(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        line = "KEYWORD"
        tf.writelines(line)
        tf.seek(0)

        for keyword, params in self.cp.parse_file(tf.name):
            error = self.cp.error("Hello")
            self.assertIn("Hello", repr(error))
            self.assertEqual(error.keyword, "KEYWORD")
            self.assertEqual(error.filename, tf.name)
        tf.close()

    def test_collects_all_errors_and_returns_all(self):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.writelines("KEYWORD1\n")
        tf.writelines("KEYWORD2\n")
        tf.writelines("KEYWORD3\n")
        tf.seek(0)

        try:
            for keyword, params in self.cp.parse_file(tf.name):
                if keyword == "KEYWORD1":
                    raise self.cp.error("Invalid KEYWORD1")
                # TODO: This doesn't work in Python like Ruby
                # because it's not a block
                # if keyword == "KEYWORD3":
                #     raise self.cp.error("Invalid KEYWORD3")
        except Exception as error:
            self.assertIn("Invalid KEYWORD1", repr(error))
            # self.assertIn("Invalid KEYWORD3", repr(error))
        tf.close()

    def test_none_converts_none_and_null(self):
        self.assertEqual(ConfigParser.handle_none("NONE"), None)
        self.assertEqual(ConfigParser.handle_none("NULL"), None)
        self.assertEqual(ConfigParser.handle_none("none"), None)
        self.assertEqual(ConfigParser.handle_none("null"), None)
        self.assertEqual(ConfigParser.handle_none(""), None)

    def test_returns_none_with_none(self):
        self.assertEqual(ConfigParser.handle_none(None), None)

    def test_returns_values_that_dont_convert(self):
        self.assertEqual(ConfigParser.handle_none("HI"), "HI")
        self.assertEqual(ConfigParser.handle_none(5.0), 5.0)

    def test_tf_converts_true_and_false(self):
        self.assertEqual(ConfigParser.handle_true_false("TRUE"), True)
        self.assertEqual(ConfigParser.handle_true_false("False"), False)
        self.assertEqual(ConfigParser.handle_true_false("True"), True)
        self.assertEqual(ConfigParser.handle_true_false("False"), False)

    def test_tf_passes_through_true_and_false(self):
        self.assertEqual(ConfigParser.handle_true_false(True), True)
        self.assertEqual(ConfigParser.handle_true_false(False), False)

    def test_tf_returns_values_that_dont_convert(self):
        self.assertEqual(ConfigParser.handle_true_false("HI"), "HI")
        self.assertEqual(ConfigParser.handle_true_false(5.0), 5.0)

    def test_tfn_converts_none_and_null(self):
        self.assertEqual(ConfigParser.handle_true_false_none("NONE"), None)
        self.assertEqual(ConfigParser.handle_true_false_none("NULL"), None)
        self.assertEqual(ConfigParser.handle_true_false_none("none"), None)
        self.assertEqual(ConfigParser.handle_true_false_none("null"), None)
        self.assertEqual(ConfigParser.handle_true_false_none(""), None)

    def test_ftn_returns_none_with_none(self):
        self.assertEqual(ConfigParser.handle_true_false_none(None), None)

    def test_tfn_converts_true_and_false(self):
        self.assertEqual(ConfigParser.handle_true_false_none("TRUE"), True)
        self.assertEqual(ConfigParser.handle_true_false_none("False"), False)
        self.assertEqual(ConfigParser.handle_true_false_none("True"), True)
        self.assertEqual(ConfigParser.handle_true_false_none("False"), False)

    def test_tfn_passes_through_true_and_false(self):
        self.assertEqual(ConfigParser.handle_true_false_none(True), True)
        self.assertEqual(ConfigParser.handle_true_false_none(False), False)

    def test_tfn_returns_values_that_dont_convert(self):
        self.assertEqual(ConfigParser.handle_true_false("HI"), "HI")
        self.assertEqual(ConfigParser.handle_true_false(5.0), 5.0)

    def test_converts_string_constants_to_numbers(self):
        for val in range(1, 65):
            # Unsigned
            self.assertEqual(
                ConfigParser.handle_defined_constants("MIN", "UINT", val), 0
            )
            self.assertEqual(
                ConfigParser.handle_defined_constants("MAX", "UINT", val),
                (2**val - 1),
            )
            # Signed
            self.assertEqual(
                ConfigParser.handle_defined_constants("MIN", "INT", val),
                (-(2**val) / 2),
            )
            self.assertAlmostEqual(
                ConfigParser.handle_defined_constants("MAX", "INT", val),
                ((2**val) / 2 - 1),
            )

        for val in [8, 16, 32, 64]:
            # Unsigned
            self.assertEqual(ConfigParser.handle_defined_constants(f"MIN_UINT{val}"), 0)
            self.assertEqual(
                ConfigParser.handle_defined_constants(f"MAX_UINT{val}"), (2**val - 1)
            )
            # Signed
            self.assertEqual(
                ConfigParser.handle_defined_constants(f"MIN_INT{val}"),
                (-(2**val) / 2),
            )
            self.assertAlmostEqual(
                ConfigParser.handle_defined_constants(f"MAX_INT{val}"),
                ((2**val) / 2 - 1),
            )

        # Float
        self.assertLess(
            ConfigParser.handle_defined_constants("MIN", "FLOAT", 32), -3.4 * 10**38
        )
        self.assertLess(
            ConfigParser.handle_defined_constants("MIN_FLOAT32"), -3.4 * 10**38
        )
        self.assertGreater(
            ConfigParser.handle_defined_constants("MAX", "FLOAT", 32), 3.4 * 10**38
        )
        self.assertGreater(
            ConfigParser.handle_defined_constants("MAX_FLOAT32"), 3.4 * 10**38
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("MIN", "FLOAT", 64),
            -sys.float_info.max,
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("MIN_FLOAT64"), -sys.float_info.max
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("MAX", "FLOAT", 64),
            sys.float_info.max,
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("MAX_FLOAT64"), sys.float_info.max
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("POS_INFINITY"), float("inf")
        )
        self.assertEqual(
            ConfigParser.handle_defined_constants("NEG_INFINITY"), float("-inf")
        )
        self.assertRaisesRegex(
            AttributeError,
            "Invalid bit size 16 for FLOAT type.",
            ConfigParser.handle_defined_constants,
            "MIN",
            "FLOAT",
            16,
        )

    def test_complains_about_undefined_strings(self):
        self.assertRaisesRegex(
            AttributeError,
            "Could not convert constant: TRUE",
            ConfigParser.handle_defined_constants,
            "TRUE",
        )
        self.assertRaisesRegex(
            AttributeError,
            "Invalid data type BLAH when calculating range.",
            ConfigParser.handle_defined_constants,
            "MIN",
            "BLAH",
            16,
        )

    def test_passes_through_numbers(self):
        self.assertEqual(ConfigParser.handle_defined_constants(0), 0)
        self.assertEqual(ConfigParser.handle_defined_constants(0.0), 0.0)
