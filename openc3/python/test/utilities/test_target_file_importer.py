# Copyright 2023 OpenC3, Inc.
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

import unittest
from unittest.mock import *
from test.test_helper import *
import openc3.utilities.target_file_importer


class TestTargetFileImporter(unittest.TestCase):
    def setUp(self) -> None:
        mock_redis(self)

    def new_body(scope, arg):
        return """
class Helper:
    def help(self):
        return 42
""".encode()

    @classmethod
    def getClient(cls):
        class FakeBucket:
            def list_files(
                self, bucket, prefix=None, max_request=1000, max_total=100_000
            ):
                return ([prefix], [])

        return FakeBucket()

    @patch.object(openc3.utilities.target_file.TargetFile, "body", new_body)
    @patch.object(openc3.utilities.bucket.Bucket, "getClient", getClient)
    def test_import(self):
        from INST2.lib.helper import Helper

        helper = Helper()
        self.assertEqual(helper.help(), 42)
