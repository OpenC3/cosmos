# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import tempfile
import unittest
from unittest.mock import *

from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig
from test.test_helper import *


class TestPacketParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_there_are_not_enough_parameters(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword)
            tf.seek(0)  # Rewind so the file is ready to read
            with self.assertRaisesRegex(ConfigParser.Error, f"Not enough parameters for {keyword}"):
                self.pc.process_file(tf.name, "SYSTEM")
            tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        for keyword in ["COMMAND", "TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(f"{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet' extra")
            tf.seek(0)  # Rewind so the file is ready to read
            with self.assertRaisesRegex(ConfigParser.Error, f"Too many parameters for {keyword}"):
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
                pkt = self.pc.commands["NEW"]["PKT1"]
            if keyword == "TELEMETRY":
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
            self.assertIn(f"{keyword.capitalize()} Packet TGT1 PKT1 redefined.", self.pc.warnings)
            tf.close()


class TestPacketParserCheckItemDefaultSizes(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def process(self, *lines):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("COMMAND TGT1 PKT1 BIG_ENDIAN\n")
        for line in lines:
            tf.write(line + "\n")
        tf.seek(0)
        try:
            self.pc.process_file(tf.name, "TGT1")
        finally:
            tf.close()

    def test_complains_about_string_and_block_defaults_that_do_not_fit(self):
        with self.assertRaisesRegex(
            ValueError, "TGT1 PKT1 ITEM1: default value of 8 bytes does not fit into 4 bytes for data_type STRING"
        ):
            self.process('  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"')
        self.pc = PacketConfig()
        with self.assertRaisesRegex(
            ValueError, "TGT1 PKT1 ITEM1: default value of 3 bytes does not fit into 2 bytes for data_type BLOCK"
        ):
            self.process('  APPEND_PARAMETER ITEM1 16 BLOCK 0x010203 "Description"')
        # DEFAULT_VALUE is applied before the check
        self.pc = PacketConfig()
        with self.assertRaisesRegex(ValueError, "ITEM1: default value of 8 bytes"):
            self.process('  APPEND_PARAMETER ITEM1 32 STRING "OK" "Description"', '    DEFAULT_VALUE "TOO LONG"')

    def test_complains_about_required_parameter_defaults_that_do_not_fit(self):
        with self.assertRaisesRegex(
            ValueError, "TGT1 PKT1 ITEM1: default value of 8 bytes does not fit into 4 bytes for data_type STRING"
        ):
            self.process('  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"', "    REQUIRED")

    def test_allows_defaults_that_fit_are_truncated_or_are_variably_sized(self):
        self.process(
            '  APPEND_PARAMETER ITEM1 32 STRING "FITS" "Description"',
            '  APPEND_PARAMETER ITEM2 32 STRING "TRUNCATED" "Description"',
            "    OVERFLOW TRUNCATE",
            '  APPEND_PARAMETER ITEM3 0 STRING "ANY SIZE AT ALL" "Description"',
        )
        self.assertEqual([w for w in self.pc.warnings if "does not fit" in w], [])

    def test_ignores_non_binary_accessors(self):
        self.process(
            "  ACCESSOR JsonAccessor",
            '  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"',
            "    KEY $.item1",
        )
        self.assertEqual([w for w in self.pc.warnings if "does not fit" in w], [])


class TestPacketParserNilDefaults(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def process(self, *lines):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("COMMAND TGT1 PKT1 BIG_ENDIAN\n")
        for line in lines:
            tf.write(line + "\n")
        tf.seek(0)
        try:
            self.pc.process_file(tf.name, "TGT1")
        finally:
            tf.close()
        return self.pc.commands["TGT1"]["PKT1"]

    def test_allows_nil_none_or_null_defaults_for_required_parameters(self):
        packet = self.process(
            '  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM2 16 INT MIN MAX None "INT"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM3 32 FLOAT MIN MAX NULL "FLOAT"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM4 32 STRING nil "STRING"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM5 32 BLOCK "none" "BLOCK"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM6 8 BOOL null "BOOL"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM7 64 ARRAY nil "ARRAY"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM8 64 OBJECT nil "OBJECT"',
            "    REQUIRED",
            # DEFAULT_VALUE and REQUIRED can come in either order
            '  APPEND_PARAMETER ITEM9 16 UINT MIN MAX 0 "UINT"',
            "    REQUIRED",
            "    DEFAULT_VALUE nil",
        )
        for i in range(1, 10):
            self.assertIsNone(packet.get_item(f"ITEM{i}").default)

    def test_complains_about_nil_defaults_for_numeric_parameters_that_are_not_required(self):
        with self.assertRaisesRegex(
            TypeError, "TGT1 PKT1 ITEM1: default of nil is only allowed for REQUIRED parameters"
        ):
            self.process('  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"')
        self.pc = PacketConfig()
        with self.assertRaisesRegex(
            TypeError, "TGT1 PKT1 ITEM1: default of NONE is only allowed for REQUIRED parameters"
        ):
            self.process('  APPEND_PARAMETER ITEM1 8 BOOL NONE "BOOL"')

    def test_keeps_nil_defaults_as_strings_for_string_and_block_parameters_that_are_not_required(self):
        packet = self.process(
            '  APPEND_PARAMETER ITEM1 32 STRING NONE "STRING"',
            '  APPEND_PARAMETER ITEM2 32 BLOCK null "BLOCK"',
        )
        self.assertEqual(packet.get_item("ITEM1").default, "NONE")
        self.assertEqual(packet.get_item("ITEM2").default, "null")

    def test_writes_nil_defaults_to_the_config(self):
        packet = self.process(
            '  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"',
            "    REQUIRED",
            '  APPEND_PARAMETER ITEM2 32 STRING nil "STRING"',
            "    REQUIRED",
        )
        config = packet.to_config("COMMAND")
        self.assertIn('PARAMETER ITEM1 0 16 UINT 0 65535 nil "UINT"', config)
        self.assertIn('PARAMETER ITEM2 16 32 STRING nil "STRING"', config)
        # The config loads back the same way
        self.pc = PacketConfig()
        packet = self.process(*config.split("\n")[1:])
        self.assertIsNone(packet.get_item("ITEM1").default)
        self.assertIsNone(packet.get_item("ITEM2").default)
