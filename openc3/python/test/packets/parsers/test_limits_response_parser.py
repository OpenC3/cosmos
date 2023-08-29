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
from openc3.packets.packet_config import PacketConfig


class TestLimitsResponseParser(unittest.TestCase):
    # before(:all) do
    #     setup_system()

    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_a_current_item_is_not_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  LIMITS_RESPONSE\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "No current item for LIMITS_RESPONSE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("  LIMITS_RESPONSE\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for LIMITS_RESPONSE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_applied_to_a_command_parameter(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_PARAMETER item1 16 UINT 0 0 0 "Item"\n')
        tf.write("    LIMITS_RESPONSE test.rb\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "LIMITS_RESPONSE only applies to telemetry items"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    # def test_complains_about_missing_response_file(self):
    #     filename = File.join(File.dirname(__FILE__), "../../test_only.rb")
    #     File.delete(filename) if File.exist?(filename):
    #     self.pc = PacketConfig()

    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
    #     tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
    #     tf.write('    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n')
    #     tf.write('    LIMITS_RESPONSE test_only.rb\n')
    #     tf.seek(0)
    #     with self.assertRaisesRegex(ConfigParser.Error, f"Unable to require test_only.rb due to cannot load such file -- test_only.rb. Ensure test_only.rb is in the OpenC3 lib directory"):
    #          self.pc.process_file(tf.name, "TGT1")
    #     tf.close()

    # def test_complains_about_a_non_openc3::limitsresponse_class(self):
    #     filename = File.join(File.dirname(__FILE__), "../../limits_response1.rb")
    #     File.open(filename, 'w') do |file|
    #       file.puts "class LimitsResponse1"
    #       file.puts "  def call(target_name, packet_name, item, old_limits_state, new_limits_state)":
    #       file.puts "  end"
    #       file.puts "end"
    #     load 'limits_response1.rb'
    #     File.delete(filename) if File.exist?(filename):

    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
    #     tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
    #     tf.write('    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n')
    #     tf.write('    LIMITS_RESPONSE limits_response1.rb\n')
    #     tf.seek(0)
    #     with self.assertRaisesRegex(ConfigParser.Error, f"response must be a OpenC3:'L'imitsResponse but is a LimitsResponse1"):
    #          self.pc.process_file(tf.name, "TGT1")
    #     tf.close()

    # def test_sets_the_response(self):
    #     filename = os.path.join(os.path.dirname(__file__), "../../limits_response2.py")
    #     with open(filename, "w") as file:
    #         file.write("from openc3.packets.limits_response import LimitsResponse\n")
    #         file.write("class LimitsResponse2(LimitsResponse):\n")
    #         file.write(
    #             "  def call(self, target_name, packet_name, item, old_limits_state, new_limits_state):\n"
    #         )
    #         file.write(
    #             '    print(f"{target_name} {packet_name} {item.name} {old_limits_state} {new_limits_state}")\n'
    #         )

    #     # load 'limits_response2.rb'

    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
    #     tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
    #     tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 6 7 3 5\n")
    #     tf.write("    LIMITS_RESPONSE limits_response2.py\n")
    #     tf.seek(0)
    #     self.pc.process_file(tf.name, "TGT1")
    #     pkt = self.pc.telemetry["TGT1"]["PKT1"]
    #     self.assertEqual(
    #         pkt.get_item("ITEM1").limits.response.__class__.__name__, "LimitsResponse2"
    #     )

    #     filename.delete()
    #     tf.close()

    # def test_calls_the_response_with_parameters(self):
    #     filename = File.join(File.dirname(__FILE__), "../../limits_response2.rb")
    #     File.open(filename, 'w') do |file|
    #       file.puts "require 'openc3/packets/limits_response'"
    #       file.puts "class LimitsResponse2 < OpenC3:'L'imitsResponse"
    #       file.puts "  def __init__(self, val)":
    #       file.puts "    puts \"initialize= \{val}\""
    #       file.puts "  end"
    #       file.puts "  def call(target_name, packet_name, item, old_limits_state, new_limits_state)":
    #       file.puts "    puts \"\{target_name} \{packet_name} \{item.name} \{old_limits_state} \{new_limits_state}\""
    #       file.puts "  end"
    #       file.puts "end"
    #     load 'limits_response2.rb'

    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
    #     tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
    #     tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 6 7 3 5\n')
    #     tf.write('    LIMITS_RESPONSE limits_response2.rb 2\n')
    #     tf.seek(0)
    #     capture_io do |stdout|
    #       self.pc.process_file(tf.name, "TGT1")
    #       self.assertEqual(stdout.string, "initialize= 2\n")

    #     File.delete(filename) if File.exist?(filename):
    #     tf.close()
