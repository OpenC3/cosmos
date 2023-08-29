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
from openc3.packets.packet_config import PacketConfig
from openc3.config.config_parser import ConfigParser


class TestPacketParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_there_are_not_enough_parameters(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword)
            tf.seek(0)  # Rewind so the file is ready to read
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Not enough parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "SYSTEM")
            tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet' extra")
            tf.seek(0)  # Rewind so the file is ready to read
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Too many parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_complains_about_invalid_endianness(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f'{keyword} tgt1 pkt1 MIDDLE_ENDIAN "Packet"')
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error,
                "Invalid endianness MIDDLE_ENDIAN. Must be BIG_ENDIAN or LITTLE_ENDIAN.",
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_processes_target_packet_endianness_description(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet'")
            tf.seek(0)
            self.pc.process_file(tf.name, "TGT1")
            if keyword == "COMMAND":
                pkt = self.pc.commands["TGT1"]["PKT1"]
            if keyword == "TELEMETRY":
                pkt = self.pc.telemetry["TGT1"]["PKT1"]
            self.assertEqual(pkt.target_name, "TGT1")
            self.assertEqual(pkt.packet_name, "PKT1")
            self.assertEqual(pkt.default_endianness, "LITTLE_ENDIAN")
            self.assertEqual(pkt.description, "Packet")
            tf.close()

    def test_substitutes_the_target_name(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet'")
            tf.seek(0)
            self.pc.process_file(tf.name, "NEW")
            if keyword == "COMMAND":
                print(self.pc.commands)
                pkt = self.pc.commands["NEW"]["PKT1"]
            if keyword == "TELEMETRY":
                print(self.pc.telemetry)
                pkt = self.pc.telemetry["NEW"]["PKT1"]
            self.assertEqual(pkt.target_name, "NEW")
            tf.close()

    def test_complains_if_a_packet_is_redefined(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet 1'\n")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet 2'\n")
            tf.seek(0)
            self.pc.process_file(tf.name, "SYSTEM")
            self.assertIn(
                f"{keyword.capitalize()} Packet TGT1 PKT1 redefined.", self.pc.warnings
            )
            tf.close()
