# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import Mock

import openc3.script
from openc3.script.tables import table_create_binary, table_create_report


class TestTables(unittest.TestCase):
    def setUp(self):
        self.api_server_mock = Mock()
        openc3.script.API_SERVER = self.api_server_mock
        self.response = Mock()
        self.response.status_code = 200
        self.response.text = '{"filename":"INST/tables/bin/table.csv","contents":"report"}'
        self.api_server_mock.request.return_value = self.response

    def test_table_create_binary(self):
        table_create_binary("INST/tables/config/table_def.txt")
        args, kwargs = self.api_server_mock.request.call_args
        self.assertEqual(args[0], "post")
        self.assertEqual(args[1], "/openc3-api/tables/generate")
        self.assertEqual(kwargs["data"], {"definition": "INST/tables/config/table_def.txt"})

    def test_table_create_report_saves_by_default(self):
        """The report must be written to the target so get_target_file can read it"""
        result = table_create_report("INST/tables/bin/table.bin", "INST/tables/config/table_def.txt")
        args, kwargs = self.api_server_mock.request.call_args
        self.assertEqual(args[0], "post")
        self.assertEqual(args[1], "/openc3-api/tables/report")
        self.assertEqual(
            kwargs["data"],
            {
                "binary": "INST/tables/bin/table.bin",
                "definition": "INST/tables/config/table_def.txt",
                "save": True,
            },
        )
        self.assertEqual(result["filename"], "INST/tables/bin/table.csv")
        self.assertEqual(result["contents"], "report")

    def test_table_create_report_table_name_and_save_false(self):
        table_create_report(
            "INST/tables/bin/table.bin",
            "INST/tables/config/table_def.txt",
            table_name="MY_TABLE",
            save=False,
        )
        _args, kwargs = self.api_server_mock.request.call_args
        self.assertEqual(kwargs["data"]["table_name"], "MY_TABLE")
        self.assertFalse(kwargs["data"]["save"])

    def test_table_create_report_error_message(self):
        self.response.status_code = 500
        self.response.text = '{"message":"boom"}'
        with self.assertRaisesRegex(RuntimeError, "Failed to create report due to boom"):
            table_create_report("INST/tables/bin/table.bin", "INST/tables/config/table_def.txt")
