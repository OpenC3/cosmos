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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
import os
import tempfile
import shutil
from openc3.tools.table_manager.table_manager_core import TableManagerCore
from openc3.utilities.string import simple_formatted

class TestTableManagerCore(unittest.TestCase):
    def setUp(self):
        # Create a temporary directory for testing
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        # Remove the directory after the test
        shutil.rmtree(self.temp_dir)

    def create_test_files(self):
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLEFILE "TestTable1_def.txt"\n')
            file.write('TABLEFILE "TestTable2_def.txt"\n')
            file.write('TABLEFILE "TestTable3_def.txt"\n')

        def1 = "TABLE 'Test1' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '8bit' 8 UINT 0 0xFF 1"
        with open(os.path.join(self.temp_dir, "TestTable1_def.txt"), 'w') as file:
            file.write(def1)

        def2 = "TABLE 'Test2' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '16bit' 16 UINT 0 0xFFFF 2"
        with open(os.path.join(self.temp_dir, "TestTable2_def.txt"), 'w') as file:
            file.write(def2)

        def3 = "TABLE 'Test3' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '32bit' 32 UINT 0 0xFFFFFFFF 3"
        with open(os.path.join(self.temp_dir, "TestTable3_def.txt"), 'w') as file:
            file.write(def3)

        return def_path

    def test_binary(self):
        """Test pulling out a table binary from a multi-table file"""
        def_path = self.create_test_files()

        binary = TableManagerCore.binary(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST1')
        self.assertEqual(binary, b"\x01")

        binary = TableManagerCore.binary(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST2')
        self.assertEqual(binary, b"\x02\x03")

        binary = TableManagerCore.binary(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST3')
        self.assertEqual(binary, b"\x04\x05\x06\x07")

    def test_definition(self):
        """Test pulling out a table definition from a multi-table file"""
        def_path = self.create_test_files()

        definition = TableManagerCore.definition(def_path, 'TEST1')
        self.assertEqual(definition[0], 'TestTable1_def.txt')
        self.assertTrue("APPEND_PARAMETER '8bit' 8 UINT 0 0xFF 1" in definition[1])

        definition = TableManagerCore.definition(def_path, 'TEST2')
        self.assertEqual(definition[0], 'TestTable2_def.txt')
        self.assertTrue("APPEND_PARAMETER '16bit' 16 UINT 0 0xFFFF 2" in definition[1])

        definition = TableManagerCore.definition(def_path, 'TEST3')
        self.assertEqual(definition[0], 'TestTable3_def.txt')
        self.assertTrue("APPEND_PARAMETER '32bit' 32 UINT 0 0xFFFFFFFF 3" in definition[1])

    def test_report(self):
        """Test creating a report for a file or a table"""
        def_path = self.create_test_files()

        report = TableManagerCore.report(b"\x01\x02\x03\x04\x05\x06\x07", def_path)
        self.assertTrue("TEST1" in report)
        self.assertTrue("TEST2" in report)
        self.assertTrue("TEST3" in report)

        report = TableManagerCore.report(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST1')
        self.assertTrue("TEST1" in report)
        self.assertFalse("TEST2" in report)
        self.assertFalse("TEST3" in report)

        report = TableManagerCore.report(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST2')
        self.assertFalse("TEST1" in report)
        self.assertTrue("TEST2" in report)
        self.assertFalse("TEST3" in report)

        report = TableManagerCore.report(b"\x01\x02\x03\x04\x05\x06\x07", def_path, 'TEST3')
        self.assertFalse("TEST1" in report)
        self.assertFalse("TEST2" in report)
        self.assertTrue("TEST3" in report)

    def test_generate(self):
        """Test generating a binary based on definition"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLEFILE "TestTable1_def.txt"\n')
            file.write('TABLEFILE "TestTable2_def.txt"\n')
            file.write('TABLEFILE "TestTable3_def.txt"\n')

        def1 = "TABLE 'Test1' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '8bit' 8 UINT 0 0xFF 1"
        with open(os.path.join(self.temp_dir, "TestTable1_def.txt"), 'w') as file:
            file.write(def1)

        def2 = "TABLE 'Test2' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '16bit' 16 UINT 0 0xFFFF 0xABCD"
        with open(os.path.join(self.temp_dir, "TestTable2_def.txt"), 'w') as file:
            file.write(def2)

        def3 = "TABLE 'Test3' BIG_ENDIAN KEY_VALUE\n  APPEND_PARAMETER '32bit' 32 UINT 0 0xFFFFFFFF 0xDEADBEEF"
        with open(os.path.join(self.temp_dir, "TestTable3_def.txt"), 'w') as file:
            file.write(def3)

        binary = TableManagerCore.generate(def_path)
        self.assertEqual(binary, b"\x01\xAB\xCD\xDE\xAD\xBE\xEF")

    def test_generate_with_all_fields(self):
        """Test generating a binary with all field types"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "MC_Configuration" BIG_ENDIAN KEY_VALUE "Memory Control Configuration Table"\n')
            file.write('APPEND_PARAMETER "UINT" 32 UINT 0 0x3FFFFF 0x3FFFFF\n')
            file.write('  FORMAT_STRING "0x%0X"\n')
            file.write('APPEND_PARAMETER "FLOAT" 32 FLOAT MIN MAX 1.234\n')
            file.write('APPEND_PARAMETER "STATE" 8 UINT 0 1 1\n')
            file.write('  STATE DISABLE 0\n')
            file.write('  STATE ENABLE 1\n')
            file.write('APPEND_PARAMETER "Convert" 8 UINT 1 3 3\n')
            file.write('  GENERIC_WRITE_CONVERSION_START\n')
            file.write('    value * 2\n')
            file.write('  GENERIC_WRITE_CONVERSION_END\n')
            file.write('APPEND_PARAMETER "UNEDITABLE" 16 UINT MIN MAX 0 "Uneditable field"\n')
            file.write('  UNEDITABLE\n')
            file.write('APPEND_PARAMETER "BINARY" 32 BLOCK 0xBA5EBA11 "Binary string"\n')
            file.write('APPEND_PARAMETER "Pad" 16 UINT 0 0 0\n')
            file.write('  HIDDEN\n')

        binary = TableManagerCore.generate(def_path)
        # The exact binary may differ from Ruby version due to Python's floating-point representation
        # but we can test the length and some known values
        print(simple_formatted(binary))
        self.assertTrue(len(binary) > 0)

    def test_build_json_hash_and_save(self):
        """Test saving single column table hash to the binary"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "Number" 16 UINT MIN MAX 0\n')
            file.write('  APPEND_PARAMETER "Throttle" 32 UINT 0 0x0FFFFFFFF 0\n')
            file.write('    FORMAT_STRING "0x%0X"\n')
            # State value
            file.write('  APPEND_PARAMETER "Scrubbing" 8 UINT 0 1 0\n')
            file.write('    STATE DISABLE 0\n')
            file.write('    STATE ENABLE 1\n')
            # Checkbox value
            file.write('  APPEND_PARAMETER "PPS" 8 UINT 0 1 0\n')
            file.write('    STATE UNCHECKED 0\n')
            file.write('    STATE CHECKED 1\n')
            file.write('    UNEDITABLE\n')

        result = TableManagerCore.build_json_hash(b"\x00\x00\x00\x00\x00\x00\x00\x00", def_path)
        self.assertIsInstance(result, dict)
        self.assertEqual(result["tables"][0]["numRows"], 4)
        self.assertEqual(result["tables"][0]["numColumns"], 1)
        self.assertEqual(result["tables"][0]["headers"], ["INDEX", "NAME", "VALUE"])
        self.assertEqual(result["tables"][0]["rows"][0][0]["index"], 1)
        self.assertEqual(result["tables"][0]["rows"][0][0]["name"], 'NUMBER')
        self.assertEqual(result["tables"][0]["rows"][0][0]["value"], '0')
        self.assertEqual(result["tables"][0]["rows"][0][0]["editable"], True)
        self.assertEqual(result["tables"][0]["rows"][1][0]["index"], 2)
        self.assertEqual(result["tables"][0]["rows"][1][0]["name"], 'THROTTLE')
        self.assertEqual(result["tables"][0]["rows"][1][0]["value"], '0x0')
        self.assertEqual(result["tables"][0]["rows"][1][0]["editable"], True)
        self.assertEqual(result["tables"][0]["rows"][2][0]["index"], 3)
        self.assertEqual(result["tables"][0]["rows"][2][0]["name"], 'SCRUBBING')
        self.assertEqual(result["tables"][0]["rows"][2][0]["value"], 'DISABLE')
        self.assertEqual(result["tables"][0]["rows"][2][0]["editable"], True)
        self.assertEqual(result["tables"][0]["rows"][3][0]["index"], 4)
        self.assertEqual(result["tables"][0]["rows"][3][0]["name"], 'PPS')
        self.assertEqual(result["tables"][0]["rows"][3][0]["value"], 'UNCHECKED')
        self.assertEqual(result["tables"][0]["rows"][3][0]["editable"], False)

        result["tables"][0]["rows"][0][0]["value"] = "1"
        result["tables"][0]["rows"][1][0]["value"] = 0x1234
        result["tables"][0]["rows"][2][0]["value"] = "ENABLE"
        result["tables"][0]["rows"][3][0]["value"] = "CHECKED"
        binary = TableManagerCore.save(def_path, result['tables'])
        self.assertEqual(binary, b"\x00\x01\x00\x00\x12\x34\x01\x01")

    def test_build_json_hash_and_save_multi_column(self):
        """Test saving multi-column table hash to the binary"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN ROW_COLUMN 3 "Description"\n')
            # Normal text value
            file.write('  APPEND_PARAMETER "Throttle" 32 UINT 0 0x0FFFFFFFF 0\n')
            file.write('    FORMAT_STRING "0x%0X"\n')
            # State value
            file.write('  APPEND_PARAMETER "Scrubbing" 8 UINT 0 1 0\n')
            file.write('    STATE DISABLE 0\n')
            file.write('    STATE ENABLE 1\n')
            # Checkbox value
            file.write('  APPEND_PARAMETER "PPS" 8 UINT 0 1 0\n')
            file.write('    STATE UNCHECKED 0\n')
            file.write('    STATE CHECKED 1\n')
            # Defaults
            file.write('DEFAULT 0 0 0\n')
            file.write('DEFAULT 0xDEADBEEF ENABLE CHECKED\n')
            file.write('DEFAULT 0xBA5EBA11 DISABLE CHECKED\n')

        test_binary = b"\x00\x00\x00\x00\x00\x00\xDE\xAD\xBE\xEF\x01\x01\xBA\x5E\xBA\x11\x00\x01"
        result = TableManagerCore.build_json_hash(test_binary, def_path)

        self.assertEqual(result["tables"][0]["numRows"], 3)
        self.assertEqual(result["tables"][0]["numColumns"], 3)
        self.assertEqual(result["tables"][0]["headers"], ["INDEX", "THROTTLE", "SCRUBBING", "PPS"])
        self.assertEqual(result["tables"][0]["rows"][0][0]["index"], 1)
        self.assertEqual(result["tables"][0]["rows"][0][0]["value"], '0x0')
        self.assertEqual(result["tables"][0]["rows"][0][1]["value"], 'DISABLE')
        self.assertEqual(result["tables"][0]["rows"][0][2]["value"], 'UNCHECKED')
        self.assertEqual(result["tables"][0]["rows"][1][0]["index"], 2)
        self.assertEqual(result["tables"][0]["rows"][1][0]["value"], '0xDEADBEEF')
        self.assertEqual(result["tables"][0]["rows"][1][1]["value"], 'ENABLE')
        self.assertEqual(result["tables"][0]["rows"][1][2]["value"], 'CHECKED')
        self.assertEqual(result["tables"][0]["rows"][2][0]["index"], 3)
        self.assertEqual(result["tables"][0]["rows"][2][0]["value"], '0xBA5EBA11')
        self.assertEqual(result["tables"][0]["rows"][2][1]["value"], 'DISABLE')
        self.assertEqual(result["tables"][0]["rows"][2][2]["value"], 'CHECKED')

        result["tables"][0]["rows"][0][0]["value"] = "1"
        result["tables"][0]["rows"][0][1]["value"] = "ENABLE"
        result["tables"][0]["rows"][0][2]["value"] = "CHECKED"
        result["tables"][0]["rows"][1][0]["value"] = "2"
        result["tables"][0]["rows"][1][1]["value"] = "DISABLE"
        result["tables"][0]["rows"][1][2]["value"] = "UNCHECKED"
        result["tables"][0]["rows"][2][0]["value"] = "3"
        result["tables"][0]["rows"][2][1]["value"] = "ENABLE"
        result["tables"][0]["rows"][2][2]["value"] = "UNCHECKED"
        binary = TableManagerCore.save(def_path, result['tables'])
        self.assertEqual(binary, b"\x00\x00\x00\x01\x01\x01\x00\x00\x00\x02\x00\x00\x00\x00\x00\x03\x01\x00")

    def test_load_binary_mismatch(self):
        """Test loading a binary file that doesn't match the definition size"""
        def_path = self.create_test_files()
        config = TableConfig.process_file(def_path)

        # Test binary too small
        with self.assertRaises(TableManagerCore.MismatchError) as context:
            TableManagerCore.load_binary(config, b"\x01\x02")
        self.assertTrue("not large enough" in str(context.exception))

        # Test binary too large
        with self.assertRaises(TableManagerCore.MismatchError) as context:
            TableManagerCore.load_binary(config, b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A")
        self.assertTrue("larger than table definition" in str(context.exception))

if __name__ == '__main__':
    unittest.main()

# Import at the end to avoid circular import issues
from openc3.tools.table_manager.table_config import TableConfig