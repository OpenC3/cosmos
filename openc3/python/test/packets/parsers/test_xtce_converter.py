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
import sys
import tempfile
import unittest

from lxml import etree

from openc3.packets.packet_config import PacketConfig
from openc3.packets.parsers.xtce_converter import XtceConverter


class TestXtceConverter(unittest.TestCase):
    """Test the XtceConverter class"""

    # The schema is vendored once, in the Ruby gem's data directory, so the two
    # implementations can't drift onto different copies. Tests aren't packaged, so
    # reaching across the repo here is fine.
    SCHEMA_PATH = os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "data", "xtce_schemas", "SpaceSystem_20180204.xsd"
    )

    @classmethod
    def setUpClass(cls):
        cls._schema = etree.XMLSchema(etree.parse(cls.SCHEMA_PATH))

    def setUp(self):
        self.pc = PacketConfig()

    def process_config(self, config, target="TGT1"):
        """Write a config string to a temp file, process it, and clean up the file."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as tf:
            tf.write(config)
            path = tf.name
        try:
            self.pc.process_file(path, target)
        finally:
            os.unlink(path)

    def assert_schema_valid(self, xtce_file):
        """Assert the generated XTCE file validates against the OMG XTCE 1.2 schema."""
        doc = etree.parse(xtce_file)
        if not self._schema.validate(doc):
            errors = "\n".join(f"line {e.line}: {e.message}" for e in self._schema.error_log)
            self.fail(f"XTCE 1.2 schema validation errors:\n{errors}")

    def test_converter_creates_output_directory(self):
        """Test that converter creates the output directory"""
        with tempfile.TemporaryDirectory() as base_dir:
            output_dir = os.path.join(base_dir, "new_output")
            self.assertFalse(os.path.exists(output_dir))

            XtceConverter.convert({}, {}, output_dir)
            self.assertTrue(os.path.exists(output_dir))

    def test_converter_skips_unknown_target(self):
        """Test that converter skips UNKNOWN target"""
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # UNKNOWN directory should not exist
            unknown_dir = os.path.join(output_dir, "UNKNOWN")
            self.assertFalse(os.path.exists(unknown_dir))

    def test_converter_creates_xtce_file_for_telemetry(self):
        """Test that converter creates XTCE file for telemetry packets"""
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test Packet"\n  APPEND_ITEM ITEM1 16 UINT "Item 1"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # XTCE file should exist
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))
            self.assert_schema_valid(xtce_file)

    def test_converter_creates_xtce_file_for_commands(self):
        """Test that converter creates XTCE file for command packets"""
        self.process_config(
            'COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test Command"\n  APPEND_PARAMETER PARAM1 16 UINT 0 10 5 "Parameter 1"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            # XTCE file should exist
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))
            self.assert_schema_valid(xtce_file)

    def test_xtce_file_is_valid_xml(self):
        """Test that generated XTCE file is valid XML"""
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 16 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 16 INT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 32 FLOAT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 64 STRING "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 64 BLOCK "Item"\n')

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
        self.process_config(
            'TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 8 UINT "Item"\n'
            "    STATE OFF 0\n"
            "    STATE ON 1\n"
        )

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
        self.process_config('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')

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
        self.process_config('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')

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
        self.process_config('COMMAND TGT1 CMD1 LITTLE_ENDIAN "Test"\n  APPEND_PARAMETER PARAM1 8 UINT 0 10 5 "Param"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test Description"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

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
        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            # Call through PacketConfig.to_xtce()
            self.pc.to_xtce(output_dir)

            # Verify file was created
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assertTrue(os.path.exists(xtce_file))
            self.assert_schema_valid(xtce_file)

    def test_xtce_declares_version_1_2(self):
        """The converter declares XTCE 1.2, matching the Ruby converter"""
        self.assertEqual(XtceConverter.XTCE_NAMESPACE, "http://www.omg.org/spec/XTCE/20180204")

        self.process_config('TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            root = etree.parse(xtce_file).getroot()
            schema_location = root.get(f"{{{XtceConverter.XSI_NAMESPACE}}}schemaLocation")
            self.assertEqual(
                schema_location,
                "http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd",
            )

    def test_xtce_little_endian_byte_order(self):
        """Little endian items larger than a byte set byteOrder on the DataEncoding.

        XTCE 1.2 removed ByteOrderList in favor of the byteOrder attribute.
        """
        self.process_config(
            'TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 16 UINT "Integer"\n'
            '  APPEND_ITEM ITEM2 32 FLOAT "Float"\n'
            '  APPEND_ITEM ITEM3 16 UINT "Enumerated"\n'
            "    STATE OFF 0\n"
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # ByteOrderList does not exist in XTCE 1.2
            self.assertEqual(tree.findall(".//xtce:ByteOrderList", namespaces=nsmap), [])

            for type_name, encoding_name, item_name in [
                ("IntegerParameterType", "IntegerDataEncoding", "ITEM1_Type"),
                ("FloatParameterType", "FloatDataEncoding", "ITEM2_Type"),
                ("EnumeratedParameterType", "IntegerDataEncoding", "ITEM3_Type"),
            ]:
                item_type = tree.find(f'.//xtce:{type_name}[@name="{item_name}"]', namespaces=nsmap)
                encoding = item_type.find(f"xtce:{encoding_name}", namespaces=nsmap)
                self.assertEqual(encoding.get("byteOrder"), "leastSignificantByteFirst", item_name)

    def test_xtce_big_endian_omits_byte_order(self):
        """Big endian and single byte items omit byteOrder (mostSignificantByteFirst is the default)"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 16 UINT "Big endian"\n'
            'TELEMETRY TGT1 PKT2 LITTLE_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM2 8 UINT "Single byte little endian"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            for item_name in ["ITEM1_Type", "ITEM2_Type"]:
                item_type = tree.find(f'.//xtce:IntegerParameterType[@name="{item_name}"]', namespaces=nsmap)
                encoding = item_type.find("xtce:IntegerDataEncoding", namespaces=nsmap)
                self.assertIsNone(encoding.get("byteOrder"), item_name)

    def test_xtce_signed_integer_encoding(self):
        """Signed integers use the XTCE 1.2 twosComplement spelling"""
        self.process_config('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n  APPEND_ITEM ITEM1 16 INT "Item"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            encoding = tree.find(
                './/xtce:IntegerParameterType[@name="ITEM1_Type"]/xtce:IntegerDataEncoding', namespaces=nsmap
            )
            self.assertEqual(encoding.get("encoding"), "twosComplement")

    def test_xtce_array_type_dimension_list(self):
        """Array types use a DimensionList instead of the 1.0 numberOfDimensions attribute"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  ARRAY_ITEM ARRAY_ITEM 0 8 UINT 80 "Array"\n'
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  ARRAY_PARAMETER CMD_ARRAY 0 64 FLOAT 640 "Array"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Both arrays hold 10 elements (80 bits of 8, 640 bits of 64), so the
            # inclusive ending index is 9. The single Dimension is what makes the array
            # one-dimensional; the indices give that dimension's length.
            for type_name, item_name in [
                ("ArrayParameterType", "ARRAY_ITEM"),
                ("ArrayArgumentType", "CMD_ARRAY"),
            ]:
                array_type = tree.find(f'.//xtce:{type_name}[@name="{item_name}_ArrayType"]', namespaces=nsmap)
                self.assertIsNotNone(array_type, item_name)
                self.assertEqual(array_type.get("arrayTypeRef"), f"{item_name}_Type")
                self.assertIsNone(array_type.get("numberOfDimensions"), item_name)
                dimensions = array_type.findall("xtce:DimensionList/xtce:Dimension", namespaces=nsmap)
                self.assertEqual(len(dimensions), 1, item_name)
                start = dimensions[0].find("xtce:StartingIndex/xtce:FixedValue", namespaces=nsmap)
                end = dimensions[0].find("xtce:EndingIndex/xtce:FixedValue", namespaces=nsmap)
                self.assertEqual(start.text, "0")
                self.assertEqual(end.text, "9", item_name)

    def test_xtce_array_ref_entries(self):
        """Array entries reference argumentRef for commands and parameterRef for telemetry"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  ID_ITEM OPCODE 0 8 UINT 1 "Opcode"\n'
            '  ARRAY_ITEM ARRAY_ITEM 8 8 UINT 80 "Array"\n'
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  ARRAY_PARAMETER CMD_ARRAY 0 64 FLOAT 640 "Array"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            arg_entry = tree.find(".//xtce:ArrayArgumentRefEntry", namespaces=nsmap)
            self.assertIsNotNone(arg_entry)
            self.assertEqual(arg_entry.get("argumentRef"), "CMD_ARRAY")
            self.assertIsNone(arg_entry.get("parameterRef"))

            param_entry = tree.find(".//xtce:ArrayParameterRefEntry", namespaces=nsmap)
            self.assertIsNotNone(param_entry)
            self.assertEqual(param_entry.get("parameterRef"), "ARRAY_ITEM")

    def test_converter_overwrites_existing_file(self):
        """Converting twice into the same directory replaces the existing file"""
        self.process_config('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n  APPEND_ITEM ITEM1 8 UINT "Item"\n')

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            first = os.path.getsize(xtce_file)

            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)
            self.assertTrue(os.path.exists(xtce_file))
            self.assertEqual(os.path.getsize(xtce_file), first)
            self.assert_schema_valid(xtce_file)

    def test_xtce_duplicate_item_names(self):
        """An item name appearing in multiple packets produces a single type"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM SHARED 8 UINT "Shared"\n'
            'TELEMETRY TGT1 PKT2 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM SHARED 8 UINT "Shared"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            types = tree.findall('.//xtce:IntegerParameterType[@name="SHARED_Type"]', namespaces=nsmap)
            self.assertEqual(len(types), 1)

    def test_xtce_unpacked_items_have_fixed_locations(self):
        """Items in a packet with gaps get LocationInContainerInBits entries"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  ITEM ITEM1 0 8 UINT "Item"\n'
            '  ITEM ITEM2 16 8 UINT "Item after a gap"\n'
            '  ARRAY_ITEM ARRAY_ITEM 32 8 UINT 16 "Array after a gap"\n'
            '  ITEM PADDING 48 16 UINT "Padding so TRAILER does not overlap"\n'
            '  ITEM TRAILER -16 16 UINT "Item relative to the end of the packet"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            entry = tree.find('.//xtce:ParameterRefEntry[@parameterRef="ITEM2"]', namespaces=nsmap)
            location = entry.find("xtce:LocationInContainerInBits", namespaces=nsmap)
            self.assertEqual(location.get("referenceLocation"), "containerStart")
            self.assertEqual(location.find("xtce:FixedValue", namespaces=nsmap).text, "16")

            array_entry = tree.find('.//xtce:ArrayParameterRefEntry[@parameterRef="ARRAY_ITEM"]', namespaces=nsmap)
            array_location = array_entry.find("xtce:LocationInContainerInBits", namespaces=nsmap)
            self.assertEqual(array_location.find("xtce:FixedValue", namespaces=nsmap).text, "32")

            trailer = tree.find('.//xtce:ParameterRefEntry[@parameterRef="TRAILER"]', namespaces=nsmap)
            trailer_location = trailer.find("xtce:LocationInContainerInBits", namespaces=nsmap)
            self.assertEqual(trailer_location.get("referenceLocation"), "containerEnd")
            self.assertEqual(trailer_location.find("xtce:FixedValue", namespaces=nsmap).text, "16")

    def test_xtce_derived_type_raises(self):
        """DERIVED items cannot be represented in XTCE"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 8 UINT "Item"\n'
            '  ITEM DERIVED_ITEM 0 0 DERIVED "Derived"\n'
        )
        packet = self.pc.telemetry["TGT1"]["PKT1"]
        derived = packet.get_item("DERIVED_ITEM")
        converter = XtceConverter({}, {}, tempfile.mkdtemp())
        root = etree.Element("root")

        with self.assertRaisesRegex(ValueError, "DERIVED data type not supported in XTCE"):
            converter._to_xtce_type(derived, "Parameter", root)

    def test_xtce_enumerated_initial_value_and_any_state(self):
        """Enumerated defaults use the state name and the special ANY state is skipped"""
        self.process_config(
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  APPEND_PARAMETER PARAM1 8 UINT 0 2 1 "Param"\n'
            "    STATE OFF 0\n"
            "    STATE ON 1\n"
            "    STATE UNKNOWN ANY\n"
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            enum_type = tree.find('.//xtce:EnumeratedArgumentType[@name="PARAM1_Type"]', namespaces=nsmap)
            self.assertEqual(enum_type.get("initialValue"), "ON")
            labels = [e.get("label") for e in enum_type.findall(".//xtce:Enumeration", namespaces=nsmap)]
            self.assertEqual(labels, ["OFF", "ON"])

    def test_xtce_polynomial_conversion(self):
        """Items with a polynomial conversion become float types with a calibrator"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 16 UINT "Integer with conversion"\n'
            "    POLY_READ_CONVERSION 10.0 0.5\n"
            '  APPEND_ITEM ITEM2 32 FLOAT "Float with conversion"\n'
            "    POLY_READ_CONVERSION 1.0 2.0\n"
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # An integer with a polynomial conversion is exported as a float type
            int_type = tree.find('.//xtce:FloatParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            self.assertIsNotNone(int_type)
            terms = int_type.findall(
                "xtce:IntegerDataEncoding/xtce:DefaultCalibrator/xtce:PolynomialCalibrator/xtce:Term",
                namespaces=nsmap,
            )
            self.assertEqual([t.get("coefficient") for t in terms], ["10.0", "0.5"])

            float_type = tree.find('.//xtce:FloatParameterType[@name="ITEM2_Type"]', namespaces=nsmap)
            float_terms = float_type.findall(
                "xtce:FloatDataEncoding/xtce:DefaultCalibrator/xtce:PolynomialCalibrator/xtce:Term",
                namespaces=nsmap,
            )
            self.assertEqual([t.get("exponent") for t in float_terms], ["0", "1"])

    def test_xtce_valid_range_and_defaults(self):
        """Command parameter ranges become ValidRange and defaults become initialValue"""
        self.process_config(
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  APPEND_PARAMETER INT_PARAM 16 INT -100 100 5 "Int"\n'
            '  APPEND_PARAMETER FLOAT_PARAM 32 FLOAT -1.5 1.5 0.5 "Float"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # Arguments wrap the range in a ValidRangeSet per the XTCE schema
            int_type = tree.find('.//xtce:IntegerArgumentType[@name="INT_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(int_type.get("initialValue"), "5")
            int_range = int_type.find("xtce:ValidRangeSet/xtce:ValidRange", namespaces=nsmap)
            self.assertEqual(int_range.get("minInclusive"), "-100")
            self.assertEqual(int_range.get("maxInclusive"), "100")

            float_type = tree.find('.//xtce:FloatArgumentType[@name="FLOAT_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(float_type.get("initialValue"), "0.5")
            self.assertIsNotNone(float_type.find("xtce:ValidRangeSet/xtce:ValidRange", namespaces=nsmap))

    def test_xtce_string_and_binary_defaults(self):
        """String and binary defaults are exported as initialValue"""
        self.process_config(
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  APPEND_PARAMETER STR_PARAM 32 STRING "DEAD" "Printable string"\n'
            '  APPEND_PARAMETER BIN_PARAM 32 BLOCK 0xDEADBEEF "Binary"\n'
            '  APPEND_PARAMETER PRINTABLE_PARAM 32 STRING 0x44454144 "String given as printable bytes"\n'
            '  APPEND_PARAMETER UNPRINTABLE_PARAM 16 STRING 0xDEAD "String given as unprintable bytes"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # String initialValue is the value itself. Quoting it would make the quotes
            # part of the default for every reader but our own importer.
            str_type = tree.find('.//xtce:StringArgumentType[@name="STR_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(str_type.get("initialValue"), "DEAD")

            # Binary initialValue is xs:hexBinary: raw hex digits, no 0x prefix, upper
            # case (hexBinary's canonical form, and what the Ruby converter writes)
            bin_type = tree.find('.//xtce:BinaryArgumentType[@name="BIN_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(bin_type.get("initialValue"), "DEADBEEF")

            # A string default given as printable bytes round trips as text
            printable = tree.find('.//xtce:StringArgumentType[@name="PRINTABLE_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(printable.get("initialValue"), "DEAD")

            # A string default that isn't printable falls back to a hex literal
            unprintable = tree.find('.//xtce:StringArgumentType[@name="UNPRINTABLE_PARAM_Type"]', namespaces=nsmap)
            self.assertEqual(unprintable.get("initialValue"), "0xDEAD")

    def test_xtce_unrepresentable_default_is_skipped(self):
        """A default that cannot be rendered is omitted rather than raising"""

        class BadDefault:
            def __str__(self):
                raise RuntimeError("cannot render")

            def __bool__(self):
                return True

        self.process_config(
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n  APPEND_PARAMETER STR_PARAM 32 STRING "DEAD" "Str"\n'
        )
        item = self.pc.commands["TGT1"]["CMD1"].get_item("STR_PARAM")
        item.default = BadDefault()

        converter = XtceConverter({}, {}, tempfile.mkdtemp())
        root = etree.Element("root")
        converter._to_xtce_string(item, "Argument", root, "String")

        self.assertIsNone(root[0].get("initialValue"))

    def test_xtce_valid_range_skipped_when_unrepresentable(self):
        """An integer range wider than xs:long is skipped, a wide float range is not"""
        self.process_config(
            'COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n'
            '  APPEND_PARAMETER FLOAT_PARAM 64 FLOAT MIN MAX 0.0 "Float"\n'
            '  APPEND_PARAMETER UINT_PARAM 64 UINT MIN MAX 0 "Uint"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            # A full 64 bit UINT range exceeds IntegerRangeType's xs:long bounds, so
            # emitting it would be schema invalid
            uint_type = tree.find('.//xtce:IntegerArgumentType[@name="UINT_PARAM_Type"]', namespaces=nsmap)
            self.assertIsNone(uint_type.find("xtce:ValidRangeSet", namespaces=nsmap))

            # FloatRangeType is xs:double, so even the FLOAT MIN / MAX defaults fit
            float_type = tree.find('.//xtce:FloatArgumentType[@name="FLOAT_PARAM_Type"]', namespaces=nsmap)
            float_range = float_type.find("xtce:ValidRangeSet/xtce:ValidRange", namespaces=nsmap)
            self.assertIsNotNone(float_range)
            self.assertEqual(float(float_range.get("minInclusive")), -sys.float_info.max)
            self.assertEqual(float(float_range.get("maxInclusive")), sys.float_info.max)

    def test_xtce_valid_range_skipped_when_not_finite(self):
        """A non-finite float range has no valid xs:double form, so it is skipped"""
        self.process_config('COMMAND TGT1 CMD1 BIG_ENDIAN "Test"\n  APPEND_PARAMETER F 64 FLOAT 0.0 1.0 0.0 "F"\n')
        item = self.pc.commands["TGT1"]["CMD1"].get_item("F")
        item.minimum = float("-inf")
        item.maximum = float("inf")

        converter = XtceConverter({}, {}, tempfile.mkdtemp())
        root = etree.Element("root")
        converter._to_xtce_valid_range(item, "Argument", root)

        self.assertEqual(len(root), 0)

    def test_xtce_parameter_valid_range_is_not_wrapped(self):
        """Parameters emit a bare ValidRange while arguments use a ValidRangeSet"""
        self.process_config('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n  APPEND_ITEM ITEM1 16 INT "Item"\n')
        item = self.pc.telemetry["TGT1"]["PKT1"].get_item("ITEM1")
        item.minimum = -10
        item.maximum = 10

        converter = XtceConverter({}, {}, tempfile.mkdtemp())
        root = etree.Element("root")
        converter._to_xtce_valid_range(item, "Parameter", root)

        self.assertEqual(len(root), 1)
        self.assertEqual(root[0].tag, f"{{{XtceConverter.XTCE_NAMESPACE}}}ValidRange")
        self.assertEqual(root[0].get("minInclusive"), "-10")
        self.assertEqual(root[0].get("maxInclusive"), "10")

    def test_xtce_units_and_limits(self):
        """Units and DEFAULT limits are exported"""
        self.process_config(
            'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Test"\n'
            '  APPEND_ITEM ITEM1 32 FLOAT "Item"\n'
            "    UNITS Celsius C\n"
            "    LIMITS DEFAULT 1 ENABLED -80.0 -70.0 60.0 80.0\n"
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)

            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)
            tree = etree.parse(xtce_file)
            nsmap = {"xtce": XtceConverter.XTCE_NAMESPACE}

            float_type = tree.find('.//xtce:FloatParameterType[@name="ITEM1_Type"]', namespaces=nsmap)
            unit = float_type.find("xtce:UnitSet/xtce:Unit", namespaces=nsmap)
            self.assertEqual(unit.text, "C")
            self.assertEqual(unit.get("description"), "Celsius")

            warning = float_type.find("xtce:DefaultAlarm/xtce:StaticAlarmRanges/xtce:WarningRange", namespaces=nsmap)
            self.assertEqual(warning.get("minInclusive"), "-70.0")
            self.assertEqual(warning.get("maxInclusive"), "60.0")
            critical = float_type.find("xtce:DefaultAlarm/xtce:StaticAlarmRanges/xtce:CriticalRange", namespaces=nsmap)
            self.assertEqual(critical.get("minInclusive"), "-80.0")
            self.assertEqual(critical.get("maxInclusive"), "80.0")

    def test_xtce_validates_against_schema(self):
        """Generated XTCE validates against the OMG XTCE 1.2 schema.

        Exercises little-endian multi-byte integer/float, an enumeration, a string,
        and both telemetry and command array items so the byteOrder attribute and
        Array{Parameter,Argument}RefEntry references are covered.
        """
        self.process_config(
            'TELEMETRY TGT1 TLMPKT BIG_ENDIAN "Telemetry"\n'
            '  ID_ITEM OPCODE 0 8 UINT 1 "Opcode"\n'
            '  ITEM UNSIGNED 8 16 UINT "Unsigned"\n'
            "    STATE FALSE 0\n"
            "    STATE TRUE 1\n"
            '  ITEM FLOATER 24 32 FLOAT "Float"\n'
            "    POLY_READ_CONVERSION 10.0 0.5\n"
            '  ITEM STR 56 32 STRING "String"\n'
            '  ARRAY_ITEM ARRAY_ITEM 88 8 UINT 80 "Array"\n'
            'COMMAND TGT1 CMDPKT LITTLE_ENDIAN "Command"\n'
            '  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 "Opcode"\n'
            '  PARAMETER CMD_SIGNED 16 16 INT -100 100 0 "Signed"\n'
            '  ARRAY_PARAMETER CMD_ARRAY 32 64 FLOAT 640 "Array of 10 64bit floats"\n'
        )

        with tempfile.TemporaryDirectory() as output_dir:
            XtceConverter.convert(self.pc.commands, self.pc.telemetry, output_dir)
            xtce_file = os.path.join(output_dir, "TGT1", "cmd_tlm", "tgt1.xtce")
            self.assert_schema_valid(xtce_file)


if __name__ == "__main__":
    unittest.main()
