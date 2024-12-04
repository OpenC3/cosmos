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

    class FakeBucket:
        def list_files(self, bucket, prefix=None, max_request=1000, max_total=100_000):
            return ([prefix], [])

    # Seems like this creates a mock which allows us to import target_file_importer
    # but then the mock that actually gets passed into the method is a different
    # mock which we don't have control on so I'm not sure how to install methods on it
    with patch("openc3.utilities.bucket.Bucket.getClient") as mock_method:
        import openc3.utilities.bucket
        import openc3.utilities.target_file
        import openc3.utilities.target_file_importer

        # mock_method.return_value = FakeBucket()
        # mock_method.list_files = [1, 2]

    @patch.object(openc3.utilities.target_file.TargetFile, "body", new_body)
    @patch.object(openc3.utilities.bucket.Bucket, "getClient", getClient)
    def test_import(self):
        pass
        # from INST2.lib.helper import Helper

        # helper = Helper()
        # self.assertEqual(helper.print_help(), 42)
