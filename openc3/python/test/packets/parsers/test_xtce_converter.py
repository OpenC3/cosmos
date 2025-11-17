# Copyright 2025 OpenC3, Inc.
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
import tempfile
import unittest
from lxml import etree
from openc3.packets.parsers.xtce_converter import XtceConverter
from openc3.packets.packet_config import PacketConfig


class TestXtceConverter(unittest.TestCase):
    """Test the XtceConverter class"""

    def setUp(self):
        self.pc = PacketConfig()

    def test_converter_creates_output_directory(self):
        """Test that converter creates the output directory"""
        with tempfile.TemporaryDirectory() as base_dir:
            output_dir = os.path.join(base_dir, "new_output")
            self.assertFalse(os.path.exists(output_dir))

            XtceConverter.convert({}, {}, output_dir)
            self.assertTrue(os.path.exists(output_dir))

    def test_converter_skips_unknown_target(self):
        """Test that converter skips UNKNOWN target"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # UNKNOWN directory should not exist
            unknown_dir = os.path.join(output_dir, "UNKNOWN")
            self.assertFalse(os.path.exists(unknown_dir))

    def test_converter_creates_xtce_file_for_telemetry(self):
        """Test that converter creates XTCE file for telemetry packets"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test Packet"\n')
        tf.write('  APPEND_ITEM ITEM1 16 UINT "Item 1"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # XTCE file should exist
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))

    def test_converter_creates_xtce_file_for_commands(self):
        """Test that converter creates XTCE file for command packets"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test Command"\n')
        tf.write('  APPEND_PARAMETER PARAM1 16 UINT 0 10 5 "Parameter 1"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # XTCE file should exist
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))

    def test_xtce_file_is_valid_xml(self):
        """Test that generated XTCE file is valid XML"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            # Should parse without errors
            tree = etree.parse(xtce_file)
            root = tree.getroot()
            self.assertIsNotNone(root)

    def test_xtce_has_correct_namespace(self):
        """Test that XTCE file has correct namespace"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            root = tree.getroot()

            # Check namespace
            self.assertEqual(root.tag, f"{{{XtceConverter.XTCE_NAMESPACE}}}SpaceSystem")
            self.assertEqual(root.get("name"), "TGT1")

    def test_xtce_contains_telemetry_metadata(self):
        """Test that XTCE contains TelemetryMetaData section"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            tlm_meta = tree.find(".//xtce:TelemetryMetaData", namespaces=nsmap)
            self.assertIsNotNone(tlm_meta)

    def test_xtce_contains_parameter_type_set(self):
        """Test that XTCE contains ParameterTypeSet"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            param_type_set = tree.find(".//xtce:ParameterTypeSet", namespaces=nsmap)
            self.assertIsNotNone(param_type_set)

    def test_xtce_contains_parameter_set(self):
        """Test that XTCE contains ParameterSet"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            param_set = tree.find(".//xtce:ParameterSet", namespaces=nsmap)
            self.assertIsNotNone(param_set)

    def test_xtce_contains_container_set(self):
        """Test that XTCE contains ContainerSet"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            container_set = tree.find(".//xtce:ContainerSet", namespaces=nsmap)
            self.assertIsNotNone(container_set)

    def test_xtce_uint_item_type(self):
        """Test that UINT items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 16 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find IntegerParameterType
            int_type = tree.find('.//xtce:IntegerParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(int_type)
            self.assertEqual(int_type.get("signed"), "false")

    def test_xtce_int_item_type(self):
        """Test that INT items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 16 INT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find IntegerParameterType
            int_type = tree.find('.//xtce:IntegerParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(int_type)
            self.assertEqual(int_type.get("signed"), "true")

    def test_xtce_float_item_type(self):
        """Test that FLOAT items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 32 FLOAT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find FloatParameterType
            float_type = tree.find('.//xtce:FloatParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(float_type)
            self.assertEqual(float_type.get("sizeInBits"), "32")

    def test_xtce_string_item_type(self):
        """Test that STRING items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 64 STRING "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find StringParameterType
            str_type = tree.find('.//xtce:StringParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(str_type)
            self.assertEqual(str_type.get("characterWidth"), "8")

    def test_xtce_block_item_type(self):
        """Test that BLOCK items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 64 BLOCK "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find BinaryParameterType
            bin_type = tree.find('.//xtce:BinaryParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(bin_type)

    def test_xtce_enumerated_item(self):
        """Test that enumerated items are converted correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.write("    STATE OFF 0\n")
        tf.write("    STATE ON 1\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find EnumeratedParameterType
            enum_type = tree.find('.//xtce:EnumeratedParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(enum_type)

            # Find EnumerationList
            enum_list = enum_type.find(".//xtce:EnumerationList", namespaces=nsmap)
            self.assertIsNotNone(enum_list)

            # Find Enumeration elements
            enums = enum_list.findall(".//xtce:Enumeration", namespaces=nsmap)
            self.assertEqual(len(enums), 2)

    def test_xtce_command_metadata(self):
        """Test that command metadata is created correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find CommandMetaData
            cmd_meta = tree.find(".//xtce:CommandMetaData", namespaces=nsmap)
            self.assertIsNotNone(cmd_meta)

    def test_xtce_argument_type_set(self):
        """Test that ArgumentTypeSet is created correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find ArgumentTypeSet
            arg_type_set = tree.find(".//xtce:ArgumentTypeSet", namespaces=nsmap)
            self.assertIsNotNone(arg_type_set)

    def test_xtce_meta_command_set(self):
        """Test that MetaCommandSet is created correctly"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find MetaCommandSet
            meta_cmd_set = tree.find(".//xtce:MetaCommandSet", namespaces=nsmap)
            self.assertIsNotNone(meta_cmd_set)

    def test_xtce_includes_packet_description(self):
        """Test that packet descriptions are included in XTCE"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test Description"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Find SequenceContainer with shortDescription
            container = tree.find('.//xtce:SequenceContainer[@name="PKT1"]', namespaces=nsmap)
            self.assertIsNotNone(container)
            self.assertEqual(container.get("shortDescription"), "Test Description")

    def test_packet_config_to_xtce_integration(self):
        """Test integration with PacketConfig.to_xtce()"""
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n')
        tf.write('  APPEND_ITEM ITEM1 8 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            # Call through PacketConfig.to_xtce()
            self.pc.to_xtce(output_dir)

            # Verify file was created
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))


if __name__ == "__main__":
    unittest.main()
