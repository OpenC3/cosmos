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

import json
import unittest
import tempfile
from unittest.mock import *
from test.test_helper import *
from openc3.packets.packet_config import PacketConfig
from openc3.packets.parsers.packet_parser import PacketParser


class TestPacketParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    # def test_complains_if_there_are_not_enough_parameters(self):
    #     for keyword in ["COMMAND", "TELEMETRY"]:
    #         tf = tempfile.NamedTemporaryFile(mode="w+t")
    #         tf.writelines(keyword)
    #         tf.seek(0)
    #         self.assertRaisesRegex(
    #             RuntimeError,
    #             rf"Not enough parameters for {keyword}",
    #             self.pc.process_file,
    #             tf.name,
    #             "SYSTEM",
    #         )
    #         tf.close()

    #   it "complains if there are too many parameters" do
    #     %w(COMMAND TELEMETRY).each do |keyword|
    #       tf = Tempfile.new('unittest')
    #       tf.puts "#{keyword} tgt1 pkt1 LITTLE_IAN 'Packet' extra"
    #       tf.close
    #       expect { @pc.process_file(tf.path, "TGT1") }.to raise_error(RuntimeError, /Too many parameters for #{keyword}/)
    #       tf.unlink

    #   it "complains about invalid ianness" do
    #     %w(COMMAND TELEMETRY).each do |keyword|
    #       tf = Tempfile.new('unittest')
    #       tf.puts keyword + ' tgt1 pkt1 MIDDLE_IAN "Packet"'
    #       tf.close
    #       expect { @pc.process_file(tf.path, "TGT1") }.to raise_error(RuntimeError, /Invalid ianness MIDDLE_IAN. Must be BIG_IAN or LITTLE_IAN./)
    #       tf.unlink

    #   it "processes target, packet, ianness, description" do
    #     %w(COMMAND TELEMETRY).each do |keyword|
    #       tf = Tempfile.new('unittest')
    #       tf.puts keyword + ' tgt1 pkt1 LITTLE_IAN "Packet"'
    #       tf.close
    #       @pc.process_file(tf.path, "TGT1")
    #       pkt = @pc.commands["TGT1"]["PKT1"] if keyword == 'COMMAND'
    #       pkt = @pc.telemetry["TGT1"]["PKT1"] if keyword == 'TELEMETRY'
    #       expect(pkt.target_name).to eql "TGT1"
    #       expect(pkt.packet_name).to eql "PKT1"
    #       expect(pkt.default_ianness).to eql :LITTLE_IAN
    #       expect(pkt.description).to eql "Packet"
    #       tf.unlink

    #   it "substitutes the target name" do
    #     %w(COMMAND TELEMETRY).each do |keyword|
    #       tf = Tempfile.new('unittest')
    #       tf.puts keyword + ' tgt1 pkt1 LITTLE_IAN "Packet"'
    #       tf.close
    #       @pc.process_file(tf.path, "NEW")
    #       pkt = @pc.commands["NEW"]["PKT1"] if keyword == 'COMMAND'
    #       pkt = @pc.telemetry["NEW"]["PKT1"] if keyword == 'TELEMETRY'
    #       expect(pkt.target_name).to eql "NEW"
    #       tf.unlink

    #   it "complains if a packet is redefined" do
    #     %w(COMMAND TELEMETRY).each do |keyword|
    #       tf = Tempfile.new('unittest')
    #       tf.puts keyword + ' tgt1 pkt1 LITTLE_IAN "Packet 1"'
    #       tf.puts keyword + ' tgt1 pkt1 LITTLE_IAN "Packet 2"'
    #       tf.close
    #       @pc.process_file(tf.path, "SYSTEM")
    #       expect(@pc.warnings).to include("#{keyword.capitalize} Packet TGT1 PKT1 redefined.")
    #       tf.unlink
