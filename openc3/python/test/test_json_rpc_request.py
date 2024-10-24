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
from openc3.io.json_rpc import JsonRpcRequest, RequestError


class TestJsonRpc(unittest.TestCase):
    def test_basic_5_request(self):
        """
        Test json request
        """
        json_request_example = """
            {
                "jsonrpc": "2.0",
                "method": "connect_interface",
                "params": ["EXAMPLE_INT"],
                "keyword_params": {"scope": "*"},
                "id": 110
            }
        """
        request = JsonRpcRequest.from_json(json_request_example, {})
        self.assertEqual(request.json_rpc, "2.0")
        self.assertIsNotNone(request.id)
        self.assertIsNotNone(request.method)
        self.assertIsNotNone(request.keyword_params)

    def test_basic_4_request(self):
        """
        Test json request
        """
        json_request_example = """
            {
                "jsonrpc": "2.0",
                "method": "connect_interface",
                "params": ["EXAMPLE_INT"],
                "id": 110
            }
        """
        request = JsonRpcRequest.from_json(json_request_example, {})
        self.assertEqual(request.json_rpc, "2.0")
        self.assertIsNotNone(request.id)
        self.assertIsNotNone(request.method)
        self.assertIsNotNone(request.params)

    def test_bad_json_rpc_version(self):
        """
        Test json request
        """
        json_request_example = '{"jsonrpc": "1.0", "method": "connect_interface", "params": ["EXAMPLE_INT"]}'
        with self.assertRaises(RequestError) as context:
            JsonRpcRequest.from_json(json_request_example, {})
            self.assertTrue("jsonrpc" in context.exception)

    def test_bad_request(self):
        """
        Test json request
        """
        json_request_example = (
            '{"method": "connect_interface", "params": ["EXAMPLE_INT"], "id": 110}'
        )
        with self.assertRaises(RequestError) as context:
            JsonRpcRequest.from_json(json_request_example, {})
        self.assertTrue("invalid json-rpc 2.0 request" in context.exception.__str__())


if __name__ == "__main__":
    unittest.main()
