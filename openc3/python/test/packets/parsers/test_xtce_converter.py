# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import tempfile
import unittest

from lxml import etree

from openc3.packets.packet_config import PacketConfig
from openc3.packets.parsers.xtce_converter import XtceConverter


class TestXtceConverter(unittest.TestCase):
    """Test the XtceConverter class"""

    SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "xtce_schemas", "SpaceSystem_06-11-06.xsd")

    @classmethod
    def setUpClass(cls):
        cls._schema = etree.XMLSchema(etree.parse(cls.SCHEMA_PATH))

    def setUp(self):
        self.pc = PacketConfig()

    def assert_schema_valid(self, xtce_file):
        """Assert the generated XTCE file validates against the OMG XTCE 1.0 schema."""
        doc = etree.parse(xtce_file)
        if not self._schema.validate(doc):
            errors = "\n".join(f"line {e.line}: {e.message}" for e in self._schema.error_log)
            self.fail(f"XTCE 1.0 schema validation errors:\n{errors}")

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
            self.assert_schema_valid(xtce_file)

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
            self.assert_schema_valid(xtce_file)

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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)
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
            self.assert_schema_valid(xtce_file)

    def test_xtce_validates_against_schema(self):
        """Generated XTCE validates against the OMG XTCE 1.0 schema.

        Exercises little-endian multi-byte integer/float, an enumeration, a string,
        and both telemetry and command array items so the ByteOrderList placement and
        Array{Parameter,Argument}RefEntry references are covered.
        """
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write('TELEMETRY TGT1 TLMPKT BIG_ENDIAN "Telemetry"\n')
        tf.write('  ID_ITEM OPCODE 0 8 UINT 1 "Opcode"\n')
        tf.write('  ITEM UNSIGNED 8 16 UINT "Unsigned"\n')
        tf.write("    STATE FALSE 0\n")
        tf.write("    STATE TRUE 1\n")
        tf.write('  ITEM FLOATER 24 32 FLOAT "Float"\n')
        tf.write("    POLY_READ_CONVERSION 10.0 0.5\n")
        tf.write('  ITEM STR 56 32 STRING "String"\n')
        tf.write('  ARRAY_ITEM ARRAY_ITEM 88 8 UINT 80 "Array"\n')
        tf.write('COMMAND TGT1 CMDPKT LITTLE_ENDIAN "Command"\n')
        tf.write('  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 "Opcode"\n')
        tf.write('  PARAMETER CMD_SIGNED 16 16 INT -100 100 0 "Signed"\n')
        tf.write('  ARRAY_PARAMETER CMD_ARRAY 32 64 FLOAT 640 "Array of 10 64bit floats"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            doc = etree.parse(xtce_file)
            schema_dir = os.path.join(os.path.dirname(__file__), "xtce_schemas")
            schema = etree.XMLSchema(etree.parse(os.path.join(schema_dir, "SpaceSystem_06-11-06.xsd")))
            valid = schema.validate(doc)
            errors = "\n".join(f"line {e.line}: {e.message}" for e in schema.error_log)
            self.assertTrue(valid, f"XTCE 1.0 schema validation errors:\n{errors}")


if __name__ == "__main__":
    unittest.main()
