# Copyright 2023 OpenC3, Inc
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
# if purchased from OpenC3, Inc.:

import unittest
from openc3.io.json_rpc import JsonRpcError


class TestJsonRpcError(unittest.TestCase):
    def test_error(self):
        """
        Test json request
        """
        json_request_example = {"code": "1234", "message": "foobar", "data": {}}
        request = JsonRpcError.from_hash(json_request_example)
        self.assertEqual(request.code, 1234)
        self.assertIsNotNone(request.message)
        self.assertIsNotNone(request.data)

    def test_bad_error(self):
        """
        Test json request
        """
        json_request_example = {"message": "foobar", "data": {}}
        with self.assertRaises(KeyError) as context:
            JsonRpcError.from_hash(json_request_example)
            self.assertTrue("Invalid" in context.exception)


if __name__ == "__main__":
    unittest.main()
