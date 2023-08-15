#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
test_json_rpc_request.py
"""

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
            self.assertTrue("jsonrpc" in context.exception)


if __name__ == "__main__":
    unittest.main()
