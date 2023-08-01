#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
test_json_rpc_error.py
"""

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
