#!/usr/bin/env python3

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
from openc3.io.json_rpc import (
    JsonRpcResponse,
    JsonRpcSuccessResponse,
    JsonRpcErrorResponse,
)


class TestJsonRpc(unittest.TestCase):
    def test_advanced_byte_response(self):
        """
        Test json response
        """
        json_response_example = {
            "jsonrpc": "2.0",
            "id": 13,
            "result": {
                "foo": bytearray(b"\x00\x01\xcaj\x01\x81`\x00\xe4\xe3\x00\t"),
            },
        }
        response = JsonRpcSuccessResponse.from_hash(json_response_example)
        self.assertEqual(response.json_rpc, "2.0")
        self.assertIsNotNone(response.id)
        self.assertNotEqual(response.result, 0)

    def test_advanced_response(self):
        """
        Test json response
        """
        json_response_example = {
            "jsonrpc": "2.0",
            "id": 13,
            "result": [
                {"json_class": "Float", "raw": "Infinity"},
                {"json_class": "Float", "raw": "-Infinity"},
                {"json_class": "Float", "raw": "NaN"},
            ],
        }
        response = JsonRpcSuccessResponse.from_hash(json_response_example)
        self.assertEqual(response.json_rpc, "2.0")
        self.assertIsNotNone(response.id)
        self.assertNotEqual(response.result, 0)

    def test_error_response(self):
        """
        Test json response
        """
        json_response_example = {
            "jsonrpc": "2.0",
            "id": 107,
            "error": {"code": "1234", "message": "foobar", "data": {"foo": "bar"}},
        }
        response = JsonRpcErrorResponse.from_hash(json_response_example)
        self.assertEqual(response.json_rpc, "2.0")
        self.assertIsNotNone(response.id)
        self.assertIsNotNone(response.error)
        self.assertIsNotNone(response.error.code)

    def test_bad_json(self):
        """
        Test json request
        """
        json_response_example = b"foobar"
        with self.assertRaises(Exception) as context:
            JsonRpcResponse.from_bytes(json_response_example)
            self.assertTrue("msg" in context.exception)


if __name__ == "__main__":
    unittest.main()
